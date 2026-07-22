defmodule Api.Conversations do
  @moduledoc """
  Private conversations and groups, and the membership that governs them.

  Both conversation kinds share two tables, so this context is the substrate the
  message, inbox, search, presence and channel features all read. It owns the
  rules that outlive a single request: a group's membership is a timeline of
  join/leave timestamps rather than a set, its `creator_id` is immutable, and a
  member removed or departed stops being "active" the instant `left_at` is set.

  Every function is scoped to a user, and the caller's identity is always a
  `%User{}` argument — never a value read from params — so no request body can
  act as somebody it is not. `active_participant?/2` is the membership predicate
  later features consume; it is evaluated at request time, so a membership change
  takes effect on the very next call.
  """

  use Boundary,
    deps: [Api, Api.Accounts, Api.Contacts],
    exports: [Conversation, ConversationParticipant]

  import Ecto.Query

  alias Api.Accounts.User
  alias Api.Contacts
  alias Api.Conversations.Conversation
  alias Api.Conversations.ConversationParticipant
  alias Api.Repo
  alias Ecto.Changeset

  # Creator plus at least one other member, up to a hard ceiling. The lower
  # bound is structural — a one-person group is a private conversation — and the
  # upper bound is the PRD's stated limit.
  @max_members 256

  @create_types %{name: :string, member_ids: {:array, Ecto.UUID}}
  @member_ids_types %{member_ids: {:array, Ecto.UUID}}

  @doc """
  Creates a group, seating the creator and the given members in one transaction.

  The decision order is the contract: the body shape is validated first, then
  the creator's own id is stripped and the list de-duplicated, then the contact
  set is checked (so a non-contact is named rather than hidden behind a size
  complaint), then the size, and only then are the rows written. A failure at
  any step inserts nothing.
  """
  def create_group(%User{} = creator, name, member_ids) do
    with {:ok, name, members} <- validate_create(creator, name, member_ids),
         :ok <- Contacts.reject_non_contacts(creator, members) do
      insert_group(creator, name, members)
    end
  end

  @doc """
  Loads a conversation the caller actively participates in, or `:not_found`.

  A non-member — an outsider or a departed member — is answered exactly as a
  missing conversation is, so a group's existence is never disclosed. The active
  members are preloaded through their user, ordered accent-insensitively like the
  contact list, and the creator is preloaded so the view can render its id.
  """
  def get_for_user(%User{} = user, id) do
    with {:ok, uuid} <- cast_id(id) do
      case load_for_member(user, uuid) do
        %Conversation{} = conversation -> {:ok, conversation}
        nil -> {:error, :not_found}
      end
    end
  end

  @doc """
  Adds contacts of the creator to the group, re-activating any who had left.

  Creator-gated behind the same visibility rule as every management action: a
  non-participant is answered `:not_found`, a participant who is not the creator
  `:not_group_creator`. A supplied id already active is rejected; one who
  previously left is reactivated in place with a fresh `joined_at`.
  """
  def add_members(%User{} = creator, id, member_ids) do
    with {:ok, uuid} <- cast_id(id),
         {:ok, conversation} <- load_manageable(creator, uuid),
         {:ok, ids} <- validate_member_ids(member_ids),
         :ok <- Contacts.reject_non_contacts(creator, ids),
         :ok <- refute_already_members(conversation, ids),
         :ok <- refute_over_capacity(conversation, ids),
         {:ok, _} <- seat_or_reactivate(conversation, ids) do
      get_for_user(creator, uuid)
    end
  end

  @doc """
  Removes a member by setting `left_at`, creator only.

  The creator cannot target themselves here — that is a leave, and it lives at
  `/members/me` so the last-member rule has a single home. A target who is not an
  active member is answered `:not_found`, disclosing nothing.
  """
  def remove_member(%User{} = creator, id, user_id) do
    with {:ok, uuid} <- cast_id(id),
         {:ok, target_id} <- cast_id(user_id),
         {:ok, conversation} <- load_manageable(creator, uuid),
         :ok <- refute_self_removal(creator, target_id) do
      deactivate(conversation.id, target_id)
    end
  end

  @doc """
  Lets an active member leave by setting their own `left_at`.

  The last active member — creator or not — cannot leave, so a group is never
  emptied. The count is taken after locking the conversation's active rows, so
  two last-ish members leaving at once can never both succeed. `creator_id` is
  never rewritten, so a group keeps its recorded owner after the creator leaves.
  """
  def leave(%User{} = user, id) do
    with {:ok, uuid} <- cast_id(id) do
      commit_leave(uuid, user)
    end
  end

  defp commit_leave(uuid, user) do
    case Repo.transaction(fn -> resolve_leave(uuid, user) end) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_leave(uuid, user) do
    active = active_participants_locked(uuid)

    cond do
      not Enum.any?(active, &(&1.user_id == user.id)) -> Repo.rollback(:not_found)
      match?([_], active) -> Repo.rollback(:last_member)
      true -> deactivate!(uuid, user.id)
    end
  end

  @doc """
  Whether the given user is an active member of the given conversation.

  Takes a `%Conversation{}` or its id and a `%User{}` or its id, so callers pass
  whichever they hold. A malformed id is simply not an active member rather than
  an error.
  """
  def active_participant?(%Conversation{id: id}, user), do: active_participant?(id, user)
  def active_participant?(id, %User{id: user_id}), do: active_participant?(id, user_id)

  def active_participant?(id, user_id) do
    with {:ok, conversation_id} <- cast_id(id),
         {:ok, uuid} <- cast_id(user_id) do
      Repo.exists?(
        from p in ConversationParticipant,
          where:
            p.conversation_id == ^conversation_id and p.user_id == ^uuid and is_nil(p.left_at)
      )
    else
      {:error, :invalid_id} -> false
    end
  end

  defp validate_create(creator, name, member_ids) do
    changeset =
      {%{}, @create_types}
      |> Changeset.cast(%{name: name, member_ids: member_ids}, [:name, :member_ids])
      |> Changeset.update_change(:name, &String.trim/1)
      |> Changeset.validate_required([:name, :member_ids])
      |> Changeset.validate_length(:name, min: 1, max: 60)

    with {:ok, %{name: name, member_ids: ids}} <- Changeset.apply_action(changeset, :insert),
         members = ids |> Enum.reject(&(&1 == creator.id)) |> Enum.uniq(),
         {:ok, members} <- refute_empty(changeset, members),
         {:ok, members} <- refute_create_capacity(changeset, members) do
      {:ok, name, members}
    end
  end

  defp refute_empty(changeset, []),
    do: {:error, member_error(changeset, "must include at least one member other than yourself")}

  defp refute_empty(_changeset, members), do: {:ok, members}

  defp refute_create_capacity(changeset, members) do
    if length(members) + 1 > @max_members do
      {:error, member_error(changeset, "a group cannot have more than #{@max_members} members")}
    else
      {:ok, members}
    end
  end

  defp insert_group(creator, name, members) do
    Repo.transaction(fn ->
      conversation =
        %Conversation{creator_id: creator.id}
        |> Conversation.group_changeset(%{name: name})
        |> Repo.insert!()

      seat!(conversation.id, [creator.id | members])

      load_for_member(creator, conversation.id)
    end)
  end

  defp validate_member_ids(member_ids) do
    {%{}, @member_ids_types}
    |> Changeset.cast(%{member_ids: member_ids}, [:member_ids])
    |> Changeset.validate_required([:member_ids])
    |> Changeset.validate_length(:member_ids, min: 1)
    |> Changeset.apply_action(:insert)
    |> case do
      {:ok, %{member_ids: ids}} -> {:ok, Enum.uniq(ids)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp refute_already_members(conversation, ids) do
    if Repo.exists?(active_members_query(conversation.id, ids)) do
      {:error, :already_member}
    else
      :ok
    end
  end

  defp refute_over_capacity(conversation, ids) do
    current = Repo.aggregate(active_members_query(conversation.id), :count)

    if current + length(ids) > @max_members do
      changeset =
        {%{}, @member_ids_types}
        |> Changeset.cast(%{member_ids: []}, [])

      {:error, member_error(changeset, "a group cannot have more than #{@max_members} members")}
    else
      :ok
    end
  end

  defp seat_or_reactivate(conversation, ids) do
    Repo.transaction(fn -> seat!(conversation.id, ids) end)
  end

  # Insert one row per user, or reactivate a departed one in place: the unique
  # (conversation_id, user_id) index turns a returning member into an update
  # rather than a duplicate. `id` and the timestamps are set by the database
  # default and the constant below.
  defp seat!(conversation_id, user_ids) do
    now = DateTime.utc_now()

    entries =
      Enum.map(
        user_ids,
        &%{conversation_id: conversation_id, user_id: &1, joined_at: now, last_read_at: nil}
      )

    Repo.insert_all(ConversationParticipant, entries,
      on_conflict: [set: [joined_at: now, left_at: nil]],
      conflict_target: [:conversation_id, :user_id]
    )
  end

  defp deactivate(conversation_id, user_id) do
    {count, _} =
      active_member_row(conversation_id, user_id)
      |> Repo.update_all(set: [left_at: DateTime.utc_now()])

    if count == 0, do: {:error, :not_found}, else: :ok
  end

  defp deactivate!(conversation_id, user_id) do
    active_member_row(conversation_id, user_id)
    |> Repo.update_all(set: [left_at: DateTime.utc_now()])
  end

  defp refute_self_removal(%User{id: id}, id), do: {:error, :cannot_remove_self}
  defp refute_self_removal(_creator, _target_id), do: :ok

  # Loads the conversation only if the caller is an active member of it, then
  # gates management on being its creator: an outsider or departed member is
  # `:not_found`, a plain member `:not_group_creator`.
  defp load_manageable(user, uuid) do
    case load_active(user, uuid) do
      nil ->
        {:error, :not_found}

      %Conversation{creator_id: creator_id} = conversation ->
        if creator_id == user.id,
          do: {:ok, conversation},
          else: {:error, :not_group_creator}
    end
  end

  defp load_active(user, uuid) do
    Conversation
    |> join(:inner, [c], p in ConversationParticipant,
      on: p.conversation_id == c.id and p.user_id == ^user.id and is_nil(p.left_at)
    )
    |> where([c], c.id == ^uuid)
    |> Repo.one()
  end

  defp load_for_member(user, uuid) do
    case load_active(user, uuid) do
      nil ->
        nil

      conversation ->
        Repo.preload(conversation, [:creator, participants: active_members_preload()])
    end
  end

  defp active_members_preload do
    from p in ConversationParticipant,
      where: is_nil(p.left_at),
      join: u in assoc(p, :user),
      order_by: [asc: fragment("lower(unaccent(?))", u.name), asc: u.id],
      preload: [user: u]
  end

  defp active_members_query(conversation_id) do
    from p in ConversationParticipant,
      where: p.conversation_id == ^conversation_id and is_nil(p.left_at)
  end

  defp active_members_query(conversation_id, user_ids) do
    from p in active_members_query(conversation_id), where: p.user_id in ^user_ids
  end

  defp active_member_row(conversation_id, user_id) do
    from p in ConversationParticipant,
      where: p.conversation_id == ^conversation_id and p.user_id == ^user_id and is_nil(p.left_at)
  end

  defp active_participants_locked(conversation_id) do
    from(p in active_members_query(conversation_id), lock: "FOR UPDATE")
    |> Repo.all()
  end

  defp member_error(changeset, message),
    do: Changeset.add_error(changeset, :member_ids, message)

  defp cast_id(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :invalid_id}
    end
  end
end
