defmodule Api.Conversations do
  @moduledoc """
  Conversations, private and group.

  A private conversation is a `conversations` row of `type: :private` with
  exactly two participant rows; a group is a `type: :group` row carrying a name
  and a creator, with one participant row per member. One set of tables for both
  kinds lets the later features write one message foreign key, join one channel
  topic and answer one inbox query instead of branching on a kind.

  Two predicates over the participant row are the context's main deliverable:

    * `participant?/2` — may this user see the conversation? — asked by the
      history read, the channel join and the send path, so the rule cannot
      diverge across them.
    * `read_access/2` — the same row, with three answers: an active member reads
      everything, a departed one reads up to their `left_at`, an outsider reads
      nothing.

  Membership is a timeline, not a set. A participant row has a `joined_at` and a
  nullable `left_at`, and leaving sets `left_at` rather than deleting the row.
  That soft record lets a departed member keep read access to what they saw, a
  re-added member reuse their row with a fresh `joined_at`, and a group keep
  functioning after its immutable `creator_id` has left.
  """

  use Boundary, deps: [Api, Api.Accounts, Api.Contacts], exports: [Conversation, Participant]

  import Ecto.Query, warn: false

  alias Api.Accounts
  alias Api.Accounts.User
  alias Api.Contacts
  alias Api.Conversations.Conversation
  alias Api.Conversations.Cursor
  alias Api.Conversations.Participant
  alias Api.Conversations.Preview
  alias Api.Repo
  alias Api.UUID
  alias Ecto.Changeset

  @typedoc "How much of a conversation a user may read: all of it, or up to the moment they left."
  @type read_scope :: :active | {:until, DateTime.t()}

  @typedoc "The last-message preview carried by one inbox entry."
  @type last_message :: %{
          id: Ecto.UUID.t(),
          body: String.t(),
          sender_id: Ecto.UUID.t(),
          inserted_at: DateTime.t()
        }

  @typedoc "One inbox entry: a conversation with its title, preview and unread state."
  @type summary :: %{
          id: Ecto.UUID.t(),
          type: Conversation.kind(),
          title: String.t() | nil,
          counterpart: User.t() | nil,
          member_count: non_neg_integer() | nil,
          last_message: last_message() | nil,
          unread_count: non_neg_integer(),
          unread_overflow: boolean(),
          last_read_at: DateTime.t() | nil
        }

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
  Opens the private conversation between `caller` and `target_id`, or returns
  the existing one.

  ## Parameters

    * `caller` — the `%User{}` opening the conversation
    * `target_id` — the other user's id, as a UUID string

  Returns `{:ok, :created, conversation}` the first time and
  `{:ok, :existing, conversation}` thereafter. Failures are `:self_conversation`,
  `:user_not_found` and `:not_a_contact`. The guards run in a fixed order (self,
  existence, contact), so passing one's own id is `:self_conversation` and an
  unknown id is a 404 rather than a 403 that would read a typo as a permission
  problem.

  Idempotency has two layers: the pre-check returns the existing conversation
  for the ordinary double-click or reload, and the `participant_key` unique
  index is the backstop that collapses two concurrent creates into one winner
  and one caught error re-read as the existing row — never a duplicate or a 500.

  ## Examples

      iex> Api.Conversations.create_private_conversation(caller, target.id)
      {:ok, :created, %Api.Conversations.Conversation{type: :private}}

      iex> Api.Conversations.create_private_conversation(caller, caller.id)
      {:error, :self_conversation}
  """
  @spec create_private_conversation(User.t(), term()) ::
          {:ok, :created | :existing, Conversation.t()}
          | {:error, :self_conversation | :user_not_found | :not_a_contact}
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
  Creates a group, seating the creator and `member_ids` in one transaction.

  ## Parameters

    * `creator` — the `%User{}` who owns the group
    * `name` — the group's display name (1–60 characters)
    * `member_ids` — user ids to seat, as UUID strings; must be contacts of the
      creator and include at least one user other than the creator

  Returns `{:ok, conversation}`, `{:error, changeset}` for an invalid body, or
  `{:error, :not_a_contact, detail}`. The decision order is the contract: body
  shape, then stripping the creator's own id and de-duplicating, then the
  contact set (so a non-contact is named rather than hidden behind a size
  complaint), then the size, and only then the writes. A failure at any step
  inserts nothing.

  ## Examples

      iex> Api.Conversations.create_group(creator, "Time de Produto", [ana.id, carlos.id])
      {:ok, %Api.Conversations.Conversation{type: :group}}

      iex> Api.Conversations.create_group(creator, "Solo", [])
      {:error, %Ecto.Changeset{valid?: false}}
  """
  @spec create_group(User.t(), term(), term()) ::
          {:ok, Conversation.t()}
          | {:error, Changeset.t()}
          | {:error, :not_a_contact, String.t()}
  def create_group(%User{} = creator, name, member_ids) do
    with {:ok, name, members} <- validate_create(creator, name, member_ids),
         :ok <- Contacts.reject_non_contacts(creator, members) do
      insert_group(creator, name, members)
    end
  end

  @doc """
  Reads a conversation the caller actively participates in, with its members
  loaded.

  ## Parameters

    * `caller` — the `%User{}` requesting the conversation
    * `id` — the conversation id, as a UUID string

  Returns `{:ok, conversation}`, `{:error, :invalid_id}` for a malformed id, or
  `{:error, :not_found}`. The read is gated on active participation, never on
  contact, which lets the recipient of a private conversation read it without
  having added the initiator. An outsider, a departed group member and an
  unknown conversation all get `:not_found`, so existence is never disclosed.

  ## Examples

      iex> Api.Conversations.get_conversation(caller, conversation.id)
      {:ok, %Api.Conversations.Conversation{}}

      iex> Api.Conversations.get_conversation(outsider, conversation.id)
      {:error, :not_found}
  """
  @spec get_conversation(User.t(), term()) ::
          {:ok, Conversation.t()} | {:error, :not_found | :invalid_id}
  def get_conversation(%User{} = caller, id) do
    with {:ok, uuid} <- UUID.cast(id),
         %Conversation{} = conversation <- Repo.get(Conversation, uuid) || {:error, :not_found} do
      authorize_read(load(conversation), caller)
    end
  end

  @doc """
  Adds contacts of the creator to the group, re-activating any who had left.

  ## Parameters

    * `creator` — the `%User{}` who owns the group
    * `id` — the group's conversation id, as a UUID string
    * `member_ids` — user ids to add, as UUID strings; must be contacts of the
      creator

  Returns `{:ok, conversation}` with members reloaded. Failures are
  `:invalid_id`, `:not_found`, `:not_group_creator`, `:already_member`, a
  changeset, or `{:error, :not_a_contact, detail}`. A supplied id already active
  is rejected; one who previously left is reactivated in place with a fresh
  `joined_at`.

  ## Examples

      iex> Api.Conversations.add_members(creator, group.id, [rafael.id])
      {:ok, %Api.Conversations.Conversation{type: :group}}

      iex> Api.Conversations.add_members(member, group.id, [rafael.id])
      {:error, :not_group_creator}
  """
  @spec add_members(User.t(), term(), term()) ::
          {:ok, Conversation.t()}
          | {:error, Changeset.t()}
          | {:error, :invalid_id | :not_found | :not_group_creator | :already_member}
          | {:error, :not_a_contact, String.t()}
  def add_members(%User{} = creator, id, member_ids) do
    with {:ok, uuid} <- UUID.cast(id),
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
  Removes a member by setting `left_at`. Creator only.

  ## Parameters

    * `creator` — the `%User{}` who owns the group
    * `id` — the group's conversation id, as a UUID string
    * `user_id` — the member to remove, as a UUID string

  Returns `:ok`, or `:invalid_id`, `:not_found`, `:not_group_creator` or
  `:cannot_remove_self`. The creator cannot target themselves here — that is a
  leave, which lives at `/members/me` so the last-member rule has a single home.

  ## Examples

      iex> Api.Conversations.remove_member(creator, group.id, member.id)
      :ok

      iex> Api.Conversations.remove_member(creator, group.id, creator.id)
      {:error, :cannot_remove_self}
  """
  @spec remove_member(User.t(), term(), term()) ::
          :ok
          | {:error, :invalid_id | :not_found | :not_group_creator | :cannot_remove_self}
  def remove_member(%User{} = creator, id, user_id) do
    with {:ok, uuid} <- UUID.cast(id),
         {:ok, target_id} <- UUID.cast(user_id),
         {:ok, conversation} <- load_manageable(creator, uuid),
         :ok <- refute_self_removal(creator, target_id) do
      deactivate(conversation.id, target_id)
    end
  end

  @doc """
  Lets an active member leave by setting their own `left_at`.

  ## Parameters

    * `user` — the `%User{}` leaving
    * `id` — the conversation id, as a UUID string

  Returns `:ok`, or `:invalid_id`, `:not_found`, `:last_member` or
  `:creator_has_members`. A group may hold just its creator, and a plain member
  may always leave; the creator may leave only once every other member is gone.
  When the sole remaining member leaves, the group is deleted outright,
  cascading its participants and messages. A private conversation's last active
  participant cannot leave, so a two-person thread is never half-emptied. The
  active count is taken after locking the active rows, so two last-ish members
  leaving at once can never both succeed.

  ## Examples

      iex> Api.Conversations.leave(member, group.id)
      :ok

      iex> Api.Conversations.leave(counterpart, private.id)
      {:error, :last_member}
  """
  @spec leave(User.t(), term()) ::
          :ok | {:error, :invalid_id | :not_found | :last_member | :creator_has_members}
  def leave(%User{} = user, id) do
    with {:ok, uuid} <- UUID.cast(id) do
      commit_leave(uuid, user)
    end
  end

  @doc """
  Whether `user` is an active member of `conversation`, taking a record or an id
  on either side.

  ## Parameters

    * `conversation` — a `%Conversation{}` or a conversation id
    * `user` — a `%User{}` or a user id

  Active means a participant row with `left_at` null. Evaluated at request time
  by every caller, so a leave or removal takes effect on the very next call.

  ## Examples

      iex> Api.Conversations.participant?(conversation.id, user.id)
      true

      iex> Api.Conversations.participant?(conversation, departed_user)
      false
  """
  @spec participant?(Conversation.t() | term(), User.t() | term()) :: boolean()
  def participant?(%Conversation{id: id}, user), do: participant?(id, user)
  def participant?(conversation_id, %User{id: id}), do: participant?(conversation_id, id)

  def participant?(conversation_id, user_id) do
    with {:ok, cid} <- UUID.cast(conversation_id),
         {:ok, uid} <- UUID.cast(user_id) do
      Repo.exists?(active_member_row(cid, uid))
    else
      {:error, :invalid_id} -> false
    end
  end

  @doc """
  Lists the user ids of every currently active member of `conversation`.

  ## Parameters

    * `conversation` — a `%Conversation{}` or a conversation id

  Feeds the per-message fan-out that pushes a summary to each participant's
  personal topic. Returns `[]` for a malformed or unknown id rather than
  raising, so a conversation deleted between a message's insert and its fan-out
  cannot crash a channel that has already replied.

  ## Examples

      iex> Api.Conversations.participant_ids(conversation.id)
      ["2b8c...", "7f1a..."]

      iex> Api.Conversations.participant_ids("not-a-uuid")
      []
  """
  @spec participant_ids(Conversation.t() | term()) :: [Ecto.UUID.t()]
  def participant_ids(%Conversation{id: id}), do: participant_ids(id)

  def participant_ids(conversation_id) do
    case UUID.cast(conversation_id) do
      {:ok, cid} ->
        Repo.all(
          from p in Participant,
            where: p.conversation_id == ^cid and is_nil(p.left_at),
            select: p.user_id
        )

      {:error, :invalid_id} ->
        []
    end
  end

  @doc """
  Reports how much of `conversation` a user may read.

  ## Parameters

    * `conversation` — a `%Conversation{}` or a conversation id
    * `user` — a `%User{}` or a user id

  Returns `{:ok, :active}` for a current member, `{:ok, {:until, left_at}}` for
  one who left a group, or `{:error, :not_found | :invalid_id}`. This is the
  read counterpart to `participant?/2` over the same participant row: the
  predicate answers a yes-or-no about the present, while reading has the third,
  timestamp-bounded answer. An outsider and an unknown conversation share one
  answer, so existence is never disclosed.

  ## Examples

      iex> Api.Conversations.read_access(conversation.id, member.id)
      {:ok, :active}

      iex> Api.Conversations.read_access(group.id, departed.id)
      {:ok, {:until, ~U[2026-07-20 10:00:00.000000Z]}}
  """
  @spec read_access(Conversation.t() | term(), User.t() | term()) ::
          {:ok, read_scope()} | {:error, :not_found | :invalid_id}
  def read_access(%Conversation{id: id}, user), do: read_access(id, user)
  def read_access(conversation_id, %User{id: id}), do: read_access(conversation_id, id)

  def read_access(conversation_id, user_id) do
    with {:ok, cid} <- UUID.cast(conversation_id),
         {:ok, uid} <- UUID.cast(user_id) do
      case Repo.one(member_row(cid, uid)) do
        nil -> {:error, :not_found}
        %{left_at: nil} -> {:ok, :active}
        %{left_at: left_at} -> {:ok, {:until, left_at}}
      end
    end
  end

  @doc """
  Lists the caller's inbox in one round trip: every conversation they actively
  participate in, ordered by last activity.

  ## Parameters

    * `caller` — the `%User{}` whose inbox is listed
    * `opts` — the options below (string or atom keys)

  ## Options

    * `:limit` — page size, defaulting to and capped at #{@list_limit}
    * `:cursor` — the opaque position from a previous page's `next_cursor`
    * `:query` (or `:q`) — narrows the list to conversations whose display title
      matches accent- and case-insensitively: a group by its name, a private
      conversation by its counterpart's display name or `@username`

  Returns `%{conversations: summaries, next_cursor: cursor | nil, has_more: bool}`,
  or `{:error, :invalid_cursor}` for a malformed cursor. One row is read beyond
  the page so `has_more` is exact.

  The driving scan is the caller's own active participant rows, so the plan is
  bounded by their membership before any join runs. Four correlated
  `LEFT JOIN LATERAL` sub-plans attach the last message, the capped unread
  count, the private counterpart and the active member count — each yielding at
  most one row, so no fact costs a query per conversation. The title filter is
  resolved as set membership over the trigram indexes rather than as a predicate
  over the joined counterpart, so a term is answered from the index instead of
  by enriching the whole inbox and discarding it.

  ## Examples

      iex> Api.Conversations.list_conversations(caller, %{limit: 20})
      %{conversations: [%{type: :group}], next_cursor: nil, has_more: false}

      iex> Api.Conversations.list_conversations(caller, %{query: "família"})
      %{conversations: [%{type: :group, title: "Família"}], next_cursor: nil, has_more: false}
  """
  @spec list_conversations(User.t(), map()) ::
          %{conversations: [summary()], next_cursor: String.t() | nil, has_more: boolean()}
          | {:error, :invalid_cursor}
  def list_conversations(%User{} = caller, opts \\ %{}) do
    parsed = parse_opts(opts)

    with {:ok, cursor} <- Api.Cursor.decode_or_nil(parsed.cursor, &Cursor.decode/1) do
      caller
      |> inbox_query()
      |> apply_title_filter(parsed.query, caller.id)
      |> apply_cursor(cursor)
      |> limit(^(parsed.limit + 1))
      |> Repo.all()
      |> assemble_page(parsed.limit)
    end
  end

  defp parse_opts(opts) when is_map(opts) do
    %{
      query: get_opt(opts, :query) || get_opt(opts, :q),
      cursor: get_opt(opts, :cursor),
      limit: Api.Cursor.normalize_limit(get_opt(opts, :limit), @list_limit, @list_limit)
    }
  end

  defp get_opt(opts, key) when is_atom(key) do
    Map.get(opts, key) || Map.get(opts, Atom.to_string(key))
  end

  defp assemble_page(rows, limit) do
    has_more = length(rows) > limit
    page = Enum.take(rows, limit)

    %{
      conversations: Enum.map(page, &to_summary/1),
      next_cursor: if(has_more, do: page |> List.last() |> row_cursor()),
      has_more: has_more
    }
  end

  defp row_cursor(row),
    do: Cursor.encode({row.last_message_inserted_at, row.inserted_at, row.id})

  @doc """
  Moves the caller's own read marker forward, or refuses.

  ## Parameters

    * `caller` — the `%User{}` marking the conversation read
    * `id` — the conversation id, as a UUID string

  Returns `{:ok, %{conversation_id: id, last_read_at: at}}`, or `:invalid_id`,
  `:not_found` or `:not_a_participant`. The write is `GREATEST(last_read_at,
  now)`, so two devices marking at once both succeed and a cleared badge can
  never reappear — the marker only ever grows. A departed member is answered
  `:not_a_participant` rather than the `:not_found` an outsider gets, since they
  already know the conversation exists.

  ## Examples

      iex> Api.Conversations.mark_read(caller, conversation.id)
      {:ok, %{conversation_id: "2b8c...", last_read_at: ~U[2026-07-24 12:00:00.000000Z]}}

      iex> Api.Conversations.mark_read(departed, group.id)
      {:error, :not_a_participant}
  """
  @spec mark_read(User.t(), term()) ::
          {:ok, %{conversation_id: Ecto.UUID.t(), last_read_at: DateTime.t()}}
          | {:error, :invalid_id | :not_found | :not_a_participant}
  def mark_read(%User{} = caller, id) do
    with {:ok, uuid} <- UUID.cast(id) do
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
    # `messages` is reached as a raw source, not through `Api.Messages.Message`:
    # that boundary already depends on this one, so the reverse edge would close
    # a compile cycle. Each column read from it is wrapped in `type/2` below to
    # recover the Ecto type a schema would carry.
    |> join(
      :left_lateral,
      [conversation: c],
      lm in fragment(
        "SELECT m.id AS id, m.body AS body, m.sender_id AS sender_id, m.inserted_at AS inserted_at FROM messages AS m WHERE m.conversation_id = ? ORDER BY m.inserted_at DESC, m.seq DESC LIMIT 1",
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
      desc: fragment("COALESCE(?.inserted_at, '-infinity')", lm),
      desc: c.inserted_at,
      desc: c.id
    )
    |> select(
      [
        participant: p,
        conversation: c,
        last_message: lm,
        unread: un,
        counterpart: cp,
        members: mc
      ],
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

  # The title a private conversation shows is the counterpart's, never a column
  # on the conversation itself, so a name and a `@username` both have to match.
  # `immutable_unaccent` on each side is what makes `familia` find `Família`,
  # and `ILIKE` what makes it case-blind. A blank term is dropped upstream of
  # the query — there is nothing to narrow.
  #
  # The match is expressed as membership in a set computed on its own rather
  # than as a predicate over the joined `:counterpart`, and that difference is
  # the whole performance story. Referencing the lateral join forces every
  # conversation in the inbox through all four enrichment sub-plans before the
  # first row can be discarded: a 10 000-conversation inbox measured 140 424
  # buffer hits and ~140 ms to return a single match. Naming the set first lets
  # the planner enter from the trigram indexes on the names, which are far more
  # selective, and enrich only the survivors — 73 buffer hits and ~12 ms for the
  # same answer. The `ILIKE` operands are spelled exactly as the indexed
  # expressions are, since an expression index is only used when the query
  # writes the expression the same way.
  defp apply_title_filter(query, term, caller_id) do
    case Accounts.search_term(term) do
      {:ok, trimmed} ->
        where(
          query,
          [conversation: c],
          c.id in subquery(matching_private_query(trimmed, caller_id)) or
            c.id in subquery(matching_group_query(trimmed))
        )

      :none ->
        query
    end
  end

  # Private conversations reached through a counterpart whose display name or
  # username matches. Restricted to `:private` so a group is never matched by a
  # member's name — a group answers to its own name and nothing else. The caller
  # is excluded from the match: a private conversation's title is the *other*
  # participant, so a term equal to the caller's own name or `@username` must not
  # pull in every private thread they are part of. The condition is
  # `Api.Accounts`', so this list and the contact list agree on what matching a
  # person means.
  defp matching_private_query(term, caller_id) do
    from(op in Participant,
      join: ou in User,
      as: :user,
      on: ou.id == op.user_id,
      join: oc in Conversation,
      on: oc.id == op.conversation_id,
      where: oc.type == :private and is_nil(op.left_at) and op.user_id != ^caller_id,
      select: op.conversation_id
    )
    |> where(^Accounts.matching_user(term))
  end

  defp matching_group_query(term) do
    like = "%" <> term <> "%"

    from(gc in Conversation,
      where:
        gc.type == :group and
          fragment("immutable_unaccent(?) ILIKE immutable_unaccent(?)", gc.name, ^like),
      select: gc.id
    )
  end

  defp apply_cursor(query, nil), do: query

  # Written as a row constructor rather than the equivalent chain of ORs, for
  # the reason `Api.Messages` gives: the row form is what the planner reads as a
  # single range bound, while the expanded form frequently plans as several
  # scans and a merge. Both sides coalesce the absent activity to `-infinity`,
  # so a never-used conversation compares as the ordering already places it and
  # never as a `NULL` that makes the whole comparison unknown.
  defp apply_cursor(query, {activity, inserted_at, id}) do
    where(
      query,
      [conversation: c, last_message: lm],
      fragment(
        "(COALESCE(?.inserted_at, '-infinity'), ?, ?) < (COALESCE(?, '-infinity'), ?, ?)",
        lm,
        c.inserted_at,
        c.id,
        type(^activity, :utc_datetime_usec),
        type(^inserted_at, :utc_datetime_usec),
        type(^id, Ecto.UUID)
      )
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

    Repo.transaction(fn ->
      case Repo.insert(Conversation.private_changeset(%Conversation{}, key)) do
        {:ok, conversation} ->
          Repo.insert!(member_changeset(conversation, caller, now))
          Repo.insert!(member_changeset(conversation, target, now))
          conversation

        {:error, %Ecto.Changeset{} = changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, conversation} ->
        {:ok, :created, load(conversation)}

      {:error, %Ecto.Changeset{}} ->
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
    conversation = Repo.get(Conversation, uuid)
    active = active_participants_locked(uuid)

    cond do
      is_nil(conversation) or not Enum.any?(active, &(&1.user_id == user.id)) ->
        Repo.rollback(:not_found)

      conversation.type == :private ->
        leave_private(active, uuid, user)

      true ->
        leave_group(conversation, active, uuid, user)
    end
  end

  # A private thread is never half-emptied: its last participant cannot leave.
  defp leave_private(active, uuid, user) do
    if match?([_], active),
      do: Repo.rollback(:last_member),
      else: deactivate!(uuid, user.id)
  end

  # The sole member leaving deletes the group (cascading participants and
  # messages); the creator may not leave while other members remain; any other
  # member simply leaves. Order matters — the lone member is always the creator,
  # so the delete branch must be checked before the creator guard.
  defp leave_group(conversation, active, uuid, user) do
    cond do
      match?([_], active) -> Repo.delete!(conversation)
      conversation.creator_id == user.id -> Repo.rollback(:creator_has_members)
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
end
