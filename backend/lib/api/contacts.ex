defmodule Api.Contacts do
  @moduledoc """
  Personal contact lists.

  A contact list is unidirectional and private: every function is scoped to one
  owner and never reads or writes another owner's list.

  `contact?/2` is as much the point of the context as the three endpoints are.
  Opening a private conversation and seating a group member both ask whether a
  user is in an owner's list, and answering it in one place keeps the rule from
  diverging across features.
  """

  use Boundary, deps: [Api, Api.Accounts], exports: [Contact]

  import Ecto.Query, warn: false

  alias Api.Accounts
  alias Api.Accounts.User
  alias Api.Contacts.Contact
  alias Api.Contacts.Cursor
  alias Api.Repo
  alias Api.UUID

  # Ceiling on a list. A soft guardrail — two adds racing at 499 may both pass,
  # and 501 rows harm nothing, so no database trigger defends it.
  @contact_limit 500

  # Page cap, matching the conversation inbox's so both lists paginate alike.
  @list_limit 200

  # Username length cap, so an echoed name in an error detail can never reflect
  # an unbounded slice of the request body.
  @username_max_length 20

  @doc """
  Adds the user with `username` to `owner`'s list.

  ## Parameters

    * `owner` — the `%User{}` whose list is modified
    * `username` — the `@username` of the user to add

  Returns `{:ok, contact}` on success. Failures are tagged tuples —
  `:user_not_found`, `:self_contact`, `:contact_already_exists` and
  `:contact_limit_reached` — the last three carrying a client-facing detail
  string. The guards run in a fixed order (unknown, self, duplicate, ceiling),
  so a caller who is both at the limit and re-adding an existing contact is told
  the more useful reason.

  ## Examples

      iex> Api.Contacts.add_contact(owner, "anabeatriz")
      {:ok, %Api.Contacts.Contact{}}

      iex> Api.Contacts.add_contact(owner, "ghost")
      {:error, :user_not_found, "No user with @ghost exists in the system"}
  """
  @spec add_contact(User.t(), String.t()) ::
          {:ok, Contact.t()}
          | {:error, :self_contact}
          | {:error, :user_not_found | :contact_already_exists | :contact_limit_reached,
             String.t()}
  def add_contact(%User{} = owner, username) when is_binary(username) do
    with {:ok, target} <- resolve_target(username),
         :ok <- refute_self(owner, target),
         :ok <- refute_duplicate(owner, target),
         :ok <- refute_limit(owner) do
      insert_pair(owner, target)
    end
  end

  @doc """
  Lists one page of `owner`'s contacts, ascending by display name.

  ## Parameters

    * `owner` — the `%User{}` whose contacts are listed
    * `opts` — the options below (string or atom keys)

  ## Options

    * `:limit` — page size, defaulting to and capped at #{@list_limit}
    * `:cursor` — the opaque position from a previous page's `next_cursor`
    * `:q` — narrows the list by `Api.Accounts.matching_user/1`, the same
      condition the conversation inbox searches by

  Returns `%{contacts: contacts, next_cursor: cursor | nil, has_more: bool}`, or
  `{:error, :invalid_cursor}` for a malformed `opts[:cursor]`. Ordering and
  search are server obligations: a JavaScript sort places `Álvaro` after `Zoe`,
  and a client that filters locally must hold every contact in memory. `id`
  breaks ties so the order is total, and one row is read beyond the page so
  `has_more` is exact.

  ## Examples

      iex> Api.Contacts.list_contacts(owner, %{limit: 50})
      %{contacts: [%Api.Contacts.Contact{}], next_cursor: nil, has_more: false}

      iex> Api.Contacts.list_contacts(owner, %{q: "ana"})
      %{contacts: [%Api.Contacts.Contact{}], next_cursor: nil, has_more: false}
  """
  @spec list_contacts(User.t(), map()) ::
          %{contacts: [Contact.t()], next_cursor: String.t() | nil, has_more: boolean()}
          | {:error, :invalid_cursor}
  def list_contacts(%User{} = owner, opts \\ %{}) do
    limit = Api.Cursor.normalize_limit(get_opt(opts, :limit), @list_limit, @list_limit)

    with {:ok, cursor} <- Api.Cursor.decode_or_nil(get_opt(opts, :cursor), &Cursor.decode/1) do
      Contact
      |> where([c], c.owner_id == ^owner.id)
      |> join(:inner, [c], u in assoc(c, :user), as: :user)
      |> apply_name_filter(get_opt(opts, :q))
      |> apply_cursor(cursor)
      |> order_by([c, user: u], asc: fragment("lower(immutable_unaccent(?))", u.name), asc: u.id)
      |> limit(^(limit + 1))
      |> preload([c, user: u], user: u)
      |> Repo.all()
      |> assemble_page(limit)
    end
  end

  # The controller hands over string keys and a direct caller atom ones.
  defp get_opt(opts, key) when is_atom(key),
    do: Map.get(opts, key) || Map.get(opts, Atom.to_string(key))

  defp apply_name_filter(query, term) do
    case Accounts.search_term(term) do
      {:ok, trimmed} -> where(query, ^Accounts.matching_user(trimmed))
      :none -> query
    end
  end

  defp apply_cursor(query, nil), do: query

  # A row constructor, so the planner reads it as a single range bound (see
  # `Api.Messages`). The bound compares the folded name, matching the `ORDER BY`;
  # comparing the raw name would sort by a different expression and skip rows at
  # every page boundary.
  defp apply_cursor(query, {sort_name, id}) do
    where(
      query,
      [c, user: u],
      fragment(
        "(lower(immutable_unaccent(?)), ?) > (?, ?)",
        u.name,
        u.id,
        ^sort_name,
        type(^id, Ecto.UUID)
      )
    )
  end

  defp assemble_page(rows, limit) do
    has_more = Enum.count(rows) > limit
    page = Enum.take(rows, limit)

    %{
      contacts: page,
      next_cursor: if(has_more, do: page |> List.last() |> Cursor.encode()),
      has_more: has_more
    }
  end

  @doc """
  Removes one contact from `owner`'s list.

  ## Parameters

    * `owner` — the `%User{}` whose list is modified
    * `id` — the contact row's id, as a UUID string

  Returns `:ok`, `{:error, :invalid_id}` for a malformed id, or
  `{:error, :not_found}` for an id that is well-formed but unknown, already
  deleted or another owner's — one indistinguishable answer, so contact
  ownership is never disclosed.

  ## Examples

      iex> Api.Contacts.delete_contact(owner, contact.id)
      :ok

      iex> Api.Contacts.delete_contact(owner, "not-a-uuid")
      {:error, :invalid_id}
  """
  @spec delete_contact(User.t(), term()) :: :ok | {:error, :not_found | :invalid_id}
  def delete_contact(%User{} = owner, id) do
    with {:ok, uuid} <- UUID.cast(id) do
      case Repo.get_by(Contact, id: uuid, owner_id: owner.id) do
        %Contact{} = contact ->
          Repo.delete!(contact)
          :ok

        nil ->
          {:error, :not_found}
      end
    end
  end

  @doc """
  Whether `user` is in `owner`'s list, taking a record or an id.

  ## Parameters

    * `owner` — the `%User{}` whose list is checked
    * `user` — a `%User{}` or a user id to look for

  Evaluated at request time by every caller, so removing a contact takes effect
  on the very next call.

  ## Examples

      iex> Api.Contacts.contact?(owner, other)
      true

      iex> Api.Contacts.contact?(owner, "not-a-uuid")
      false
  """
  @spec contact?(User.t(), User.t() | term()) :: boolean()
  def contact?(%User{} = owner, %User{} = user), do: contact?(owner, user.id)

  def contact?(%User{} = owner, user_id) do
    case UUID.cast(user_id) do
      {:ok, uuid} -> Repo.exists?(pair_query(owner.id, uuid))
      {:error, :invalid_id} -> false
    end
  end

  @doc """
  Reports which of `ids` are not in `owner`'s list.

  ## Parameters

    * `owner` — the `%User{}` whose list is checked
    * `ids` — user ids, already cast to UUIDs, to verify

  Returns `:ok` when every id is a contact, or `{:error, :not_a_contact, detail}`
  whose detail names the offenders' `@username`s for the 403. `contact?/2`
  decides one id at a time and cannot express "all or none"; a group creation
  must accept every member or reject the whole request, so a member removed from
  contacts between opening a dialog and submitting fails the call rather than
  silently dropping out.

  ## Examples

      iex> Api.Contacts.reject_non_contacts(owner, [contact.id])
      :ok

      iex> Api.Contacts.reject_non_contacts(owner, [stranger.id])
      {:error, :not_a_contact, "These users are not in your contacts: @stranger"}
  """
  @spec reject_non_contacts(User.t(), [Ecto.UUID.t()]) ::
          :ok | {:error, :not_a_contact, String.t()}
  def reject_non_contacts(%User{} = owner, ids) when is_list(ids) do
    requested = MapSet.new(ids)

    present =
      pair_query(owner.id)
      |> where([c], c.contact_user_id in ^ids)
      |> select([c], c.contact_user_id)
      |> Repo.all()
      |> MapSet.new()

    case MapSet.to_list(MapSet.difference(requested, present)) do
      [] -> :ok
      offenders -> {:error, :not_a_contact, offenders_detail(offenders)}
    end
  end

  # Only offenders that resolve to a user contribute a name; an id that names no
  # user still failed the contact check but has no `@username` to show. Ordered
  # for a deterministic message.
  defp offenders_detail(offender_ids) do
    usernames =
      User
      |> where([u], u.id in ^offender_ids)
      |> order_by([u], asc: u.username)
      |> select([u], u.username)
      |> Repo.all()
      |> Enum.map_join(", ", &"@#{&1}")

    "These users are not in your contacts: #{usernames}"
  end

  defp resolve_target(username) do
    case Accounts.get_user_by_username(username) do
      %User{} = target ->
        {:ok, target}

      nil ->
        {:error, :user_not_found,
         "No user with @#{searched_username(username)} exists in the system"}
    end
  end

  defp refute_self(%User{id: id}, %User{id: id}), do: {:error, :self_contact}
  defp refute_self(_owner, _target), do: :ok

  defp refute_duplicate(owner, target) do
    if Repo.exists?(pair_query(owner.id, target.id)) do
      duplicate_error(target)
    else
      :ok
    end
  end

  defp refute_limit(owner) do
    if Repo.aggregate(where(Contact, [c], c.owner_id == ^owner.id), :count) >= @contact_limit do
      {:error, :contact_limit_reached,
       "You have reached the maximum of #{@contact_limit} contacts"}
    else
      :ok
    end
  end

  # The pre-check above already answered the common duplicate, so reaching a
  # constraint error here means two requests raced past it. That is a 409 like
  # any other duplicate, never a 500.
  defp insert_pair(owner, target) do
    %Contact{owner_id: owner.id, contact_user_id: target.id}
    |> Contact.changeset()
    |> Repo.insert()
    |> case do
      {:ok, contact} -> {:ok, %{contact | user: target}}
      {:error, %Ecto.Changeset{}} -> duplicate_error(target)
    end
  end

  defp duplicate_error(target),
    do: {:error, :contact_already_exists, "@#{target.username} is already in your contacts"}

  defp pair_query(owner_id), do: where(Contact, [c], c.owner_id == ^owner_id)

  defp pair_query(owner_id, contact_user_id),
    do: where(pair_query(owner_id), [c], c.contact_user_id == ^contact_user_id)

  defp searched_username(username) do
    username
    |> User.normalize_username()
    |> String.slice(0, @username_max_length)
  end
end
