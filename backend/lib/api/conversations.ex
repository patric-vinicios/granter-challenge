defmodule Api.Conversations do
  @moduledoc """
  Every conversation in the product, private or group.

  A private conversation is not a table of its own: it is a `conversations` row
  of `type: :private` with exactly two participant rows. A group is a row of
  `type: :group` carrying a name and a creator, with one participant row per
  member. Modelling both kinds on the same tables is what lets the later
  features write one message foreign key, join one channel topic and answer one
  inbox query rather than branching on a kind they would have to detect.

  `participant?/2` is the context's real deliverable to the rest of the system,
  the same way `contact?/2` is the contacts context's: the history read, the
  channel join and the send path are three code paths that must answer one
  question — may this user see this conversation? — and answering it here keeps
  the rule from diverging across them. `read_access/2` asks the same participant
  row the other question, the one with three answers: writing is a yes-or-no
  about the present, reading may be bounded at the moment a member left.

  Membership is a timeline, not a set. A participant is a row with a `joined_at`
  and a nullable `left_at`, and leaving sets `left_at` rather than deleting the
  row. That soft record is what lets a departed member keep read access to what
  they saw, a re-added member reuse their row with a fresh `joined_at`, and a
  group keep functioning after its immutable `creator_id` has left.
  """

  use Boundary, deps: [Api, Api.Accounts, Api.Contacts], exports: [Conversation, Participant]

  import Ecto.Query, warn: false

  alias Api.Accounts
  alias Api.Accounts.User
  alias Api.Contacts
  alias Api.Conversations.Conversation
  alias Api.Conversations.Participant
  alias Api.Conversations.Preview
  alias Api.Repo
  alias Ecto.Changeset
  alias Ecto.Multi

  # Creator plus at least one other member, up to a hard ceiling. The lower
  # bound is structural — a one-person group is a private conversation — and the
  # upper bound is the PRD's stated limit.
  @max_members 256

  # The inbox is rendered whole, not paged: a client that pages it cannot show a
  # global unread state. A caller above the cap loses their least recently
  # active conversations, which is the correct thing to lose.
  @list_limit 200

  @create_types %{name: :string, member_ids: {:array, Ecto.UUID}}
  @member_ids_types %{member_ids: {:array, Ecto.UUID}}

  @doc """
  Opens the private conversation between `caller` and the user named by
  `target_id`, or returns the existing one.

  The guards run in a fixed order — self, existence, contact — so the error a
  caller sees when more than one condition holds is the contract, not an
  accident: passing one's own id is `self_conversation`, not `not_a_contact`,
  and an unknown id is a 404, not a 403 that would confuse a typo for a
  permission problem.

  Idempotency has two layers. The pre-check returns the existing conversation
  for the ordinary double-click or reload; the `participant_key` unique index is
  the backstop that turns two genuinely concurrent creates into one winner and
  one caught error re-read as the existing row, never a duplicate or a 500.
  """
  def create_private_conversation(%User{} = caller, target_id) do
    with :ok <- refute_self(caller, target_id),
         {:ok, target} <- resolve_target(target_id),
         :ok <- refute_non_contact(caller, target) do
      key = participant_key(caller, target)

      case Repo.get_by(Conversation, participant_key: key, type: :private) do
        %Conversation{} = existing -> {:ok, :existing, load(existing)}
        nil -> insert_pair(caller, target, key)
      end
    end
  end

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
  Reads a conversation the caller actively participates in, with its members
  loaded.

  The read is gated on active participation, never on contact, which is what
  lets the recipient of a private conversation read it without having added the
  initiator. A malformed id is rejected before any query; a well-formed id that
  names no conversation, or one the caller is not an active member of — an
  outsider or a departed group member — gets one indistinguishable `:not_found`,
  so a conversation's existence is never disclosed.
  """
  def get_conversation(%User{} = caller, id) do
    with {:ok, uuid} <- cast_id(id),
         %Conversation{} = conversation <- Repo.get(Conversation, uuid) || {:error, :not_found} do
      authorize_read(load(conversation), caller)
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
      get_conversation(creator, uuid)
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

  @doc """
  Whether `user` is an active member of `conversation`, taking a record or an id
  on either side.

  Active means a participant row with `left_at` null. Evaluated at request time
  by every caller, so a leave or removal takes effect on the very next call.
  """
  def participant?(%Conversation{id: id}, user), do: participant?(id, user)
  def participant?(conversation_id, %User{id: id}), do: participant?(conversation_id, id)

  def participant?(conversation_id, user_id) do
    with {:ok, cid} <- cast_id(conversation_id),
         {:ok, uid} <- cast_id(user_id) do
      Repo.exists?(active_member_row(cid, uid))
    else
      {:error, :invalid_id} -> false
    end
  end

  @doc """
  How much of `conversation` this user may read: all of it, everything up to the
  moment they left, or nothing at all.

  The read counterpart to `participant?/2`, over the very same participant row.
  The predicate stays a yes-or-no about the present — may this user write here,
  or hold a channel open — because that is what its callers ask. Reading has a
  third answer: a member who left a group keeps the history they saw and gains
  not one message written afterwards, and that bound is a timestamp, not a
  boolean. Widening the predicate to carry it would force every existing caller
  to match a shape it has no use for.

  An outsider and an unknown conversation share one answer, so the existence of
  a conversation is never disclosed by the difference between them.
  """
  def read_access(%Conversation{id: id}, user), do: read_access(id, user)
  def read_access(conversation_id, %User{id: id}), do: read_access(conversation_id, id)

  def read_access(conversation_id, user_id) do
    with {:ok, cid} <- cast_id(conversation_id),
         {:ok, uid} <- cast_id(user_id) do
      case Repo.one(member_row(cid, uid)) do
        nil -> {:error, :not_found}
        %{left_at: nil} -> {:ok, :active}
        %{left_at: left_at} -> {:ok, {:until, left_at}}
      end
    end
  end

  @doc """
  The caller's whole inbox in one round trip: every conversation they actively
  participate in, ordered by last activity, capped at #{@list_limit}.

  The driving scan is the caller's own active participant rows, so the number of
  rows entering the plan is bounded by their membership before any join runs.
  Four correlated `LEFT JOIN LATERAL` sub-plans attach the last message, the
  capped unread count, the private counterpart and the active member count, each
  yielding at most one row, so one conversation is always one result row and no
  fact costs a query per conversation.

  The `messages` table is reached as a bare source rather than through
  `Api.Messages.Message`, because that boundary already depends on this one and
  the reverse edge would close a cycle the compiler rejects; every column read
  from it is wrapped in `type/2` to recover the Ecto type a schema would carry.
  """
  def list_conversations(%User{} = caller) do
    caller
    |> inbox_query()
    |> Repo.all()
    |> Enum.map(&to_summary/1)
  end

  @doc """
  Moves the caller's own read marker forward, or refuses.

  The write is `GREATEST(last_read_at, now)`, so two devices marking at once both
  succeed and a cleared badge can never reappear: commit order stops mattering
  because the marker only ever grows. A departed member is answered
  `:not_a_participant` rather than the `:not_found` an outsider gets — they
  already know the conversation exists, so 404 would conceal nothing.
  """
  def mark_read(%User{} = caller, id) do
    with {:ok, uuid} <- cast_id(id) do
      case read_access(uuid, caller) do
        {:ok, :active} -> write_marker(uuid, caller.id)
        {:ok, {:until, _left_at}} -> {:error, :not_a_participant}
        {:error, :not_found} -> {:error, :not_found}
      end
    end
  end

  # --- Inbox internals ----------------------------------------------------

  defp inbox_query(%User{id: caller_id}) do
    from(p in Participant,
      as: :participant,
      join: c in Conversation,
      as: :conversation,
      on: c.id == p.conversation_id,
      where: p.user_id == ^caller_id and is_nil(p.left_at)
    )
    |> join(
      :left_lateral,
      [conversation: c],
      lm in fragment(
        "SELECT m.id AS id, m.body AS body, m.sender_id AS sender_id, m.inserted_at AS inserted_at FROM messages AS m WHERE m.conversation_id = ? ORDER BY m.inserted_at DESC, m.id DESC LIMIT 1",
        c.id
      ),
      on: true,
      as: :last_message
    )
    |> join(
      :left_lateral,
      [participant: p, conversation: c],
      un in fragment(
        "SELECT count(*) AS unread FROM (SELECT 1 FROM messages AS m WHERE m.conversation_id = ? AND m.sender_id <> ? AND m.inserted_at > GREATEST(?, ?) LIMIT 100) AS capped",
        c.id,
        type(^caller_id, Ecto.UUID),
        p.last_read_at,
        p.joined_at
      ),
      on: true,
      as: :unread
    )
    |> join(:left_lateral, [], cp in subquery(counterpart_query(caller_id)),
      on: true,
      as: :counterpart
    )
    |> join(:left_lateral, [], mc in subquery(member_count_query()), on: true, as: :members)
    |> order_by([conversation: c, last_message: lm],
      asc: fragment("?.id IS NULL", lm),
      desc: fragment("?.inserted_at", lm),
      desc: c.inserted_at,
      desc: c.id
    )
    |> limit(^@list_limit)
    |> select(
      [participant: p, conversation: c, last_message: lm, unread: un, counterpart: cp, members: mc],
      %{
        id: c.id,
        type: c.type,
        name: c.name,
        inserted_at: c.inserted_at,
        last_read_at: p.last_read_at,
        last_message_id: type(fragment("?.id", lm), Ecto.UUID),
        last_message_body: type(fragment("?.body", lm), :string),
        last_message_sender_id: type(fragment("?.sender_id", lm), Ecto.UUID),
        last_message_inserted_at: type(fragment("?.inserted_at", lm), :utc_datetime_usec),
        unread: fragment("?.unread", un),
        counterpart_id: cp.id,
        counterpart_username: cp.username,
        counterpart_name: cp.name,
        counterpart_last_seen_at: cp.last_seen_at,
        member_count: mc.members
      }
    )
  end

  defp counterpart_query(caller_id) do
    from o in Participant,
      join: u in User,
      on: u.id == o.user_id,
      where:
        parent_as(:conversation).type == :private and
          o.conversation_id == parent_as(:conversation).id and
          o.user_id != ^caller_id and is_nil(o.left_at),
      select: %{id: u.id, username: u.username, name: u.name, last_seen_at: u.last_seen_at},
      limit: 1
  end

  defp member_count_query do
    from a in Participant,
      where:
        parent_as(:conversation).type == :group and
          a.conversation_id == parent_as(:conversation).id and is_nil(a.left_at),
      select: %{members: count(a.id)}
  end

  defp to_summary(row) do
    %{
      id: row.id,
      type: row.type,
      title: title(row),
      counterpart: counterpart(row),
      member_count: member_count(row),
      last_message: last_message(row),
      unread_count: min(row.unread, 99),
      unread_overflow: row.unread > 99,
      last_read_at: row.last_read_at
    }
  end

  defp title(%{type: :group, name: name}), do: name
  defp title(%{type: :private, counterpart_name: name}), do: name

  defp counterpart(%{type: :private, counterpart_id: id} = row) when not is_nil(id) do
    %User{
      id: id,
      username: row.counterpart_username,
      name: row.counterpart_name,
      last_seen_at: row.counterpart_last_seen_at
    }
  end

  defp counterpart(_row), do: nil

  defp member_count(%{type: :group, member_count: count}), do: count
  defp member_count(_row), do: nil

  defp last_message(%{last_message_id: nil}), do: nil

  defp last_message(row) do
    %{
      id: row.last_message_id,
      body: Preview.truncate(row.last_message_body),
      sender_id: row.last_message_sender_id,
      inserted_at: row.last_message_inserted_at
    }
  end

  defp write_marker(conversation_id, user_id) do
    now = DateTime.utc_now()

    query =
      from p in Participant,
        where:
          p.conversation_id == ^conversation_id and p.user_id == ^user_id and is_nil(p.left_at),
        update: [
          set: [
            last_read_at: fragment("GREATEST(?, ?)", p.last_read_at, ^now),
            updated_at: ^now
          ]
        ],
        select: p.last_read_at

    case Repo.update_all(query, []) do
      {1, [last_read_at]} ->
        {:ok, %{conversation_id: conversation_id, last_read_at: last_read_at}}

      {0, _} ->
        {:error, :not_a_participant}
    end
  end

  # --- Private conversation internals -------------------------------------

  # Sorting the pair before joining is what makes the key symmetric, so
  # A-opens-B and B-opens-A collapse onto one conversation.
  defp participant_key(%User{id: a}, %User{id: b}), do: Enum.join(Enum.sort([a, b]), ":")

  defp refute_self(%User{id: id}, id), do: {:error, :self_conversation}
  defp refute_self(_caller, _target_id), do: :ok

  defp resolve_target(target_id) do
    case Accounts.get_user(target_id) do
      %User{} = target -> {:ok, target}
      nil -> {:error, :user_not_found}
    end
  end

  defp refute_non_contact(caller, target) do
    if Contacts.contact?(caller, target), do: :ok, else: {:error, :not_a_contact}
  end

  # The pre-check already answered the common repeat, so a unique violation here
  # means two requests raced past it. That is a 200 returning the winner's row,
  # never a 500 — the same constraint-as-backstop shape the contacts context
  # uses for a duplicate contact, now guarding a three-row transaction.
  defp insert_pair(caller, target, key) do
    now = DateTime.utc_now()

    multi =
      Multi.new()
      |> Multi.insert(:conversation, Conversation.private_changeset(%Conversation{}, key))
      |> Multi.insert(:caller, &member_changeset(&1.conversation, caller, now))
      |> Multi.insert(:target, &member_changeset(&1.conversation, target, now))

    case Repo.transaction(multi) do
      {:ok, %{conversation: conversation}} ->
        {:ok, :created, load(conversation)}

      {:error, :conversation, %Ecto.Changeset{}, _changes} ->
        existing = Repo.get_by!(Conversation, participant_key: key, type: :private)
        {:ok, :existing, load(existing)}
    end
  end

  defp member_changeset(conversation, %User{} = user, joined_at) do
    %Participant{conversation_id: conversation.id, user_id: user.id}
    |> Participant.changeset(%{joined_at: joined_at})
  end

  defp authorize_read(%Conversation{} = conversation, caller) do
    if Enum.any?(conversation.participants, &(&1.user_id == caller.id)) do
      {:ok, conversation}
    else
      {:error, :not_found}
    end
  end

  # --- Group internals ----------------------------------------------------

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
      conversation
    end)
    |> case do
      {:ok, conversation} -> {:ok, load(conversation)}
      other -> other
    end
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
      changeset = Changeset.cast({%{}, @member_ids_types}, %{member_ids: []}, [])
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
  # rather than a duplicate. `id` is filled by the database default; the
  # timestamps are set here since `insert_all` runs no autogeneration.
  defp seat!(conversation_id, user_ids) do
    now = DateTime.utc_now()

    entries =
      Enum.map(user_ids, fn user_id ->
        %{
          conversation_id: conversation_id,
          user_id: user_id,
          joined_at: now,
          last_read_at: nil,
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(Participant, entries,
      on_conflict: [set: [joined_at: now, left_at: nil, updated_at: now]],
      conflict_target: [:conversation_id, :user_id]
    )
  end

  defp deactivate(conversation_id, user_id) do
    {count, _} =
      conversation_id
      |> active_member_row(user_id)
      |> Repo.update_all(set: [left_at: DateTime.utc_now(), updated_at: DateTime.utc_now()])

    if count == 0, do: {:error, :not_found}, else: :ok
  end

  defp deactivate!(conversation_id, user_id) do
    now = DateTime.utc_now()

    conversation_id
    |> active_member_row(user_id)
    |> Repo.update_all(set: [left_at: now, updated_at: now])
  end

  defp refute_self_removal(%User{id: id}, id), do: {:error, :cannot_remove_self}
  defp refute_self_removal(_creator, _target_id), do: :ok

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
    |> join(:inner, [c], p in Participant,
      on: p.conversation_id == c.id and p.user_id == ^user.id and is_nil(p.left_at)
    )
    |> where([c], c.id == ^uuid)
    |> Repo.one()
  end

  # --- Shared query shapes ------------------------------------------------

  defp load(%Conversation{} = conversation) do
    Repo.preload(conversation, [:creator, participants: active_members_preload()])
  end

  defp active_members_preload do
    from p in Participant,
      where: is_nil(p.left_at),
      join: u in assoc(p, :user),
      order_by: [asc: fragment("lower(unaccent(?))", u.name), asc: u.id],
      preload: [user: u]
  end

  defp active_members_query(conversation_id) do
    from p in Participant,
      where: p.conversation_id == ^conversation_id and is_nil(p.left_at)
  end

  defp active_members_query(conversation_id, user_ids) do
    from p in active_members_query(conversation_id), where: p.user_id in ^user_ids
  end

  # The membership row whether or not it is active: a departed member is a
  # distinct answer to the read question rather than an absent one, so the
  # `left_at` filter that `active_member_row/2` applies would erase it.
  defp member_row(conversation_id, user_id) do
    from p in Participant,
      where: p.conversation_id == ^conversation_id and p.user_id == ^user_id,
      select: %{left_at: p.left_at}
  end

  defp active_member_row(conversation_id, user_id) do
    from p in Participant,
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
