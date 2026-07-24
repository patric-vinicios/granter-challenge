defmodule Api.Contacts do
  @moduledoc """
  Personal contact lists.

  A contact list is unidirectional and private: every function here is scoped to
  one owner, and no call ever writes to, or reads, somebody else's list.

  `contact?/2` is the reason the context exists as much as the three endpoints
  are. Opening a private conversation and seating a member in a group both ask
  the same question — is this user in that user's list? — and answering it in
  one place is what keeps the rule from being reimplemented, and diverging,
  across features.
  """

  use Boundary, deps: [Api, Api.Accounts], exports: [Contact]

  import Ecto.Query, warn: false

  alias Api.Accounts
  alias Api.Accounts.User
  alias Api.Contacts.Contact
  alias Api.Contacts.Cursor
  alias Api.Repo

  # Bounds the response size and the unindexed sort behind `list_contacts/1`.
  # A soft guardrail: two adds racing at exactly 499 may both pass, and 501
  # rows harm neither, which is why no trigger defends the number.
  @contact_limit 500

  # The page cap, matching the conversation inbox's so a client that paginates
  # one list paginates the other with the same numbers.
  @list_limit 200

  # The maximum username length, so an echoed name in an error detail can never
  # reflect an unbounded slice of the request body.
  @username_max_length 20

  @doc """
  Adds the user carrying `username` to `owner`'s list.

  The guards run in a fixed order — unknown, self, duplicate, then ceiling — so
  a caller who is both at the limit and re-adding an existing contact is told
  the truth rather than being asked to prune their list.
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
  One page of `owner`'s contacts, ascending by display name, optionally narrowed
  by a search term in `opts[:q]`.

  The ordering is a server obligation rather than a client one: sorting a
  JavaScript array with the default comparator places `Álvaro` after `Zoe`,
  so the fold happens here and every client renders the same order. `id` is the
  tie-break, so two contacts sharing a display name still have a total order,
  and the pair is what the cursor bounds on.

  The search is a server obligation for the same kind of reason. A list this
  size is small enough to send whole, but "small enough to send" is not "small
  enough to send on every keystroke", and a client that filters locally has to
  hold every contact in memory to do it. Matching is `Api.Accounts.matching_user/1`,
  the same condition the conversation inbox searches by, so a person found in
  one list is never missed in the other.

  Paging works exactly as the inbox's does — `:limit`, `:cursor`, and one row
  read beyond the page so `has_more` is exact rather than inferred from a count
  the client did not choose.
  """
  @spec list_contacts(User.t(), map()) ::
          %{contacts: [Contact.t()], next_cursor: String.t() | nil, has_more: boolean()}
          | {:error, :invalid_cursor}
  def list_contacts(%User{} = owner, opts \\ %{}) do
    limit = normalize_limit(get_opt(opts, :limit))

    with {:ok, cursor} <- decode_cursor(get_opt(opts, :cursor)) do
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

  defp normalize_limit(nil), do: @list_limit
  defp normalize_limit(limit) when is_integer(limit) and limit < 1, do: 1
  defp normalize_limit(limit) when is_integer(limit) and limit > @list_limit, do: @list_limit
  defp normalize_limit(limit) when is_integer(limit), do: limit
  defp normalize_limit(_limit), do: @list_limit

  defp decode_cursor(nil), do: {:ok, nil}
  defp decode_cursor(""), do: {:ok, nil}
  defp decode_cursor(cursor), do: Cursor.decode(cursor)

  defp apply_name_filter(query, term) do
    case Accounts.search_term(term) do
      {:ok, trimmed} -> where(query, ^Accounts.matching_user(trimmed))
      :none -> query
    end
  end

  defp apply_cursor(query, nil), do: query

  # A row constructor rather than the equivalent chain of ORs, for the reason
  # `Api.Messages` gives: the row form is what the planner reads as a single
  # range bound. The sort key is the folded name, so the cursor carries the
  # folded name — comparing against the raw one would order by a different
  # expression than the query sorts by and skip rows at every page boundary.
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
  Removes one contact row from `owner`'s list.

  A malformed id is rejected before any query: a value that fails a UUID cast
  cannot name a row, so answering `:invalid_id` reports a malformed request and
  discloses nothing a `:not_found` would have hidden. An id that is well-formed
  but unknown, already deleted or somebody else's gets one indistinguishable
  answer, so contact ownership is never disclosed.
  """
  @spec delete_contact(User.t(), term()) :: :ok | {:error, :not_found | :invalid_id}
  def delete_contact(%User{} = owner, id) do
    with {:ok, uuid} <- cast_id(id) do
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
  Whether `user` is in `owner`'s list, taking either a record or an id.

  Evaluated at request time by every caller, so removing a contact takes effect
  on the very next call rather than on the next session.
  """
  @spec contact?(User.t(), User.t() | term()) :: boolean()
  def contact?(%User{} = owner, %User{} = user), do: contact?(owner, user.id)

  def contact?(%User{} = owner, user_id) do
    case cast_id(user_id) do
      {:ok, uuid} -> Repo.exists?(pair_query(owner.id, uuid))
      {:error, :invalid_id} -> false
    end
  end

  @doc """
  Answers *which of these ids are not in `owner`'s list*, naming the offenders.

  `contact?/2` decides one id at a time, which cannot express "seat all of
  these or none of them": a group creation must either accept every member or
  reject the whole request naming the ones that failed, so a member removed from
  contacts between opening a dialog and submitting fails the call rather than
  silently dropping out of the group. This is that set check — one query
  subtracting the owner's contacts from the requested set — and it returns the
  offenders' `@username`s so the 403 can list them. `id`s are assumed already
  cast to UUIDs by the caller.
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

  # Only offenders that resolve to a user contribute a name; an id that is not a
  # user at all still failed the contact check and keeps the call rejected, it
  # simply has no `@username` to show. Ordered so the message is deterministic.
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

  defp cast_id(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :invalid_id}
    end
  end

  defp searched_username(username) do
    username
    |> User.normalize_username()
    |> String.slice(0, @username_max_length)
  end
end
