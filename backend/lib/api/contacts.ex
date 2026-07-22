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
  alias Api.Repo

  # Bounds the response size and the unindexed sort behind `list_contacts/1`.
  # A soft guardrail: two adds racing at exactly 499 may both pass, and 501
  # rows harm neither, which is why no trigger defends the number.
  @contact_limit 500

  # The maximum username length, so an echoed name in an error detail can never
  # reflect an unbounded slice of the request body.
  @username_max_length 20

  @doc """
  Adds the user carrying `username` to `owner`'s list.

  The guards run in a fixed order — unknown, self, duplicate, then ceiling — so
  a caller who is both at the limit and re-adding an existing contact is told
  the truth rather than being asked to prune their list.
  """
  def add_contact(%User{} = owner, username) when is_binary(username) do
    with {:ok, target} <- resolve_target(username),
         :ok <- refute_self(owner, target),
         :ok <- refute_duplicate(owner, target),
         :ok <- refute_limit(owner) do
      insert_pair(owner, target)
    end
  end

  @doc """
  Every contact of `owner`, ascending by display name.

  The ordering is a server obligation rather than a client one: sorting a
  JavaScript array with the default comparator places `Álvaro` after `Zoe`,
  so the fold happens here and every client renders the same order. `id` is the
  tie-break, so two contacts sharing a display name still have a total order.
  """
  def list_contacts(%User{} = owner) do
    Contact
    |> where([c], c.owner_id == ^owner.id)
    |> join(:inner, [c], u in assoc(c, :user))
    |> order_by([c, u], asc: fragment("lower(unaccent(?))", u.name), asc: u.id)
    |> preload([c, u], user: u)
    |> Repo.all()
  end

  @doc """
  Removes one contact row from `owner`'s list.

  A malformed id is rejected before any query: a value that fails a UUID cast
  cannot name a row, so answering `:invalid_id` reports a malformed request and
  discloses nothing a `:not_found` would have hidden. An id that is well-formed
  but unknown, already deleted or somebody else's gets one indistinguishable
  answer, so contact ownership is never disclosed.
  """
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
  def contact?(%User{} = owner, %User{} = user), do: contact?(owner, user.id)

  def contact?(%User{} = owner, user_id) do
    case cast_id(user_id) do
      {:ok, uuid} -> Repo.exists?(pair_query(owner.id, uuid))
      {:error, :invalid_id} -> false
    end
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

  defp pair_query(owner_id, contact_user_id),
    do: where(Contact, [c], c.owner_id == ^owner_id and c.contact_user_id == ^contact_user_id)

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
