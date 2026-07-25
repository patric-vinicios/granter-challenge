defmodule Api.Messages do
  @moduledoc """
  Message writes and history reads for conversations.

  `create_message/3` is the single write path. The REST layer never calls it —
  messages are sent over the channel — while the channel, the seed script and
  the tests all share it, so the participation gate and the body rules live in
  one place. It casts `:body` only: the sender comes from the authenticated
  caller, the conversation from the request path, and the insertion time from
  the caller's attributes solely so the seed script can backdate a demo
  conversation. A request body can set none of them.

  History is read by keyset, not offset, for correctness before speed. Messages
  arrive while a user scrolls; under `OFFSET` a single insert between two
  requests shifts every row down by one, re-serving a message the client already
  holds (or a delete skipping one). A cursor anchored on the row's own
  `(inserted_at, seq)` names a position in a total order, so neither happens —
  and the ten-thousandth page costs what the first one does.
  """

  use Boundary, deps: [Api, Api.Accounts, Api.Conversations], exports: [Message]

  import Ecto.Query, warn: false

  alias Api.Accounts.User
  alias Api.Conversations
  alias Api.Messages.Cursor
  alias Api.Messages.Highlight
  alias Api.Messages.Message
  alias Api.Repo
  alias Api.UUID

  # What a page holds when the caller asks for no particular size, and the
  # ceiling the endpoint enforces before the query is ever built.
  @default_limit 30
  @max_limit 100

  # Search pages the same way history does, so a query matching thousands of
  # messages is reachable in full rather than truncated at a cap.
  @default_search_limit 30
  @max_search_limit 100

  @typedoc "One page of history: the messages ascending, the cursor before them, and whether more exist."
  @type page :: %{
          messages: [Message.t()],
          next_cursor: String.t() | nil,
          has_more: boolean()
        }

  @typedoc "One search hit: the message, its 1-based position and the spans of the term in its body."
  @type hit :: %{
          message: Message.t(),
          position: pos_integer(),
          match_offsets: [Highlight.span()]
        }

  @typedoc "One page of search hits with the total-match count and the cursor to the next page."
  @type search_page :: %{
          messages: [hit()],
          total_matches: non_neg_integer(),
          next_cursor: String.t() | nil,
          has_more: boolean()
        }

  @doc """
  Persists a message from `sender` into the conversation named by
  `conversation_id`.

  ## Parameters

    * `sender` — the `%User{}` sending the message
    * `conversation_id` — the conversation id, as a UUID string
    * `attrs` — a map or keyword with `:body`, and optionally `:inserted_at` for
      backdated (seed) data

  Returns `{:ok, message}` with its sender preloaded. Failures are a changeset
  for an invalid body, `:invalid_id`, or `:not_found`. Gated on active
  participation, so a non-member and a departed group member are both answered
  `:not_found` — writing is a question about the present, and existence is never
  disclosed by the difference. Only `:body` is cast; `:inserted_at` is placed on
  the struct, so a caller forwarding a request body cannot set it.

  ## Examples

      iex> Api.Messages.create_message(sender, conversation.id, %{body: "Olá!"})
      {:ok, %Api.Messages.Message{body: "Olá!"}}

      iex> Api.Messages.create_message(outsider, conversation.id, %{body: "Olá!"})
      {:error, :not_found}
  """
  @spec create_message(User.t(), term(), map() | keyword()) ::
          {:ok, Message.t()}
          | {:error, Ecto.Changeset.t(Message.t())}
          | {:error, :invalid_id | :not_found}
  def create_message(%User{} = sender, conversation_id, attrs \\ %{}) do
    attrs = Map.new(attrs)

    with {:ok, cid} <- UUID.cast(conversation_id),
         :ok <- refute_non_participant(cid, sender) do
      %Message{conversation_id: cid, sender_id: sender.id}
      |> Message.changeset(attrs)
      |> put_inserted_at(attrs)
      |> Repo.insert()
      |> preload_sender(sender)
    end
  end

  @doc """
  Lists one page of `conversation_id`'s history for `caller`, ascending.

  ## Parameters

    * `caller` — the `%User{}` reading the history
    * `conversation_id` — the conversation id, as a UUID string
    * `opts` — the options below

  ## Options

    * `:limit` — page size, defaulting to #{@default_limit}, capped at #{@max_limit}
    * `:before` — the opaque cursor of the oldest message the caller already holds

  Returns `{:ok, %{messages: messages, next_cursor: cursor | nil, has_more: bool}}`,
  or `{:error, :invalid_id | :not_found | :invalid_cursor}`. A departed group
  member is bounded at their `left_at` inside the query rather than by filtering
  a fetched page, so `has_more` and `next_cursor` never leak, through a page
  count, that the conversation carried on without them.

  ## Examples

      iex> Api.Messages.list_messages(caller, conversation.id, %{limit: 30})
      {:ok, %{messages: [%Api.Messages.Message{}], next_cursor: nil, has_more: false}}
  """
  @spec list_messages(User.t(), term(), map() | keyword()) ::
          {:ok, page()} | {:error, :invalid_id | :not_found | :invalid_cursor}
  def list_messages(%User{} = caller, conversation_id, opts \\ %{}) do
    opts = Map.new(opts)
    limit = Api.Cursor.normalize_limit(Map.get(opts, :limit), @default_limit, @max_limit)

    with {:ok, cid} <- UUID.cast(conversation_id),
         {:ok, access} <- Conversations.read_access(cid, caller),
         {:ok, cursor} <- Api.Cursor.decode_or_nil(Map.get(opts, :before), &Cursor.decode/1) do
      cid
      |> history_query(access, cursor, limit)
      |> Repo.all()
      |> assemble_page(limit)
      |> then(&{:ok, &1})
    end
  end

  @doc """
  Full-text search inside one conversation for `query`, newest match first.

  ## Parameters

    * `caller` — the `%User{}` running the search
    * `conversation_id` — the conversation id, as a UUID string
    * `query` — the search text, in `websearch_to_tsquery` syntax
    * `opts` — the options below

  ## Options

    * `:limit` — page size, defaulting to #{@default_search_limit}, capped at #{@max_search_limit}
    * `:before` — the opaque cursor from a previous page

  Returns `{:ok, %{messages: hits, total_matches: count, next_cursor: cursor | nil,
  has_more: bool}}`, or `{:error, :invalid_id | :not_found | :invalid_cursor}`.
  Each hit is `%{message: %Message{}, position: pos, match_offsets: spans}`,
  where `position` is the global 1-based rank (1 = newest) and `total_matches`
  the true count across all pages, so a client can render "position / total".
  Paginated by the same `(inserted_at, seq)` keyset history uses and gated on
  the same read access, so a departed member searches only up to their `left_at`.

  ## Examples

      iex> Api.Messages.search_messages(caller, conversation.id, "cronograma")
      {:ok, %{messages: [%{position: 1}], total_matches: 1, next_cursor: nil, has_more: false}}
  """
  @spec search_messages(User.t(), term(), String.t(), map() | keyword()) ::
          {:ok, search_page()} | {:error, :invalid_id | :not_found | :invalid_cursor}
  def search_messages(%User{} = caller, conversation_id, query, opts \\ %{})
      when is_binary(query) do
    opts = Map.new(opts)

    limit =
      Api.Cursor.normalize_limit(Map.get(opts, :limit), @default_search_limit, @max_search_limit)

    with {:ok, cid} <- UUID.cast(conversation_id),
         {:ok, access} <- Conversations.read_access(cid, caller),
         {:ok, cursor} <- Api.Cursor.decode_or_nil(Map.get(opts, :before), &Cursor.decode/1) do
      base = search_base(cid, access, query)
      total = Repo.aggregate(base, :count)

      rows =
        base
        |> apply_cursor(cursor)
        |> order_by([m], desc: m.inserted_at, desc: m.seq)
        |> limit(^(limit + 1))
        |> join(:inner, [m], u in assoc(m, :sender))
        |> preload([m, u], sender: u)
        |> select_merge([m], %{
          headline:
            fragment(
              "ts_headline('portuguese_unaccent', ?, websearch_to_tsquery('portuguese_unaccent', ?), ?)",
              m.body,
              ^query,
              ^Highlight.headline_opts()
            )
        })
        |> Repo.all()

      has_more = length(rows) > limit
      page = Enum.take(rows, limit)
      offset = if cursor, do: rank_of_first(base, page), else: 0

      hits =
        page
        |> Enum.with_index(offset + 1)
        |> Enum.map(fn {message, position} ->
          %{
            message: message,
            position: position,
            match_offsets: Highlight.offsets_from_headline(message.headline)
          }
        end)

      {:ok,
       %{
         messages: hits,
         total_matches: total,
         next_cursor: if(has_more, do: page |> List.last() |> Cursor.encode()),
         has_more: has_more
       }}
    end
  end

  # --- Search internals ---------------------------------------------------

  # The filtered set without order or paging: one conversation, bounded at a
  # departed member's left_at, matched through the GIN index.
  defp search_base(conversation_id, access, query) do
    Message
    |> where([m], m.conversation_id == ^conversation_id)
    |> apply_bound(access)
    |> where(
      [m],
      fragment("search_vector @@ websearch_to_tsquery('portuguese_unaccent', ?)", ^query)
    )
  end

  # The 0-based rank of the page's first hit — how many matches are newer than it
  # — so `position` is the global index across pages rather than within the page.
  defp rank_of_first(_base, []), do: 0

  defp rank_of_first(base, [%Message{inserted_at: inserted_at, seq: seq} | _]) do
    base
    |> where(
      [m],
      fragment(
        "(?, ?) > (?, ?)",
        m.inserted_at,
        m.seq,
        type(^inserted_at, :utc_datetime_usec),
        ^seq
      )
    )
    |> Repo.aggregate(:count)
  end

  # --- Write internals ----------------------------------------------------

  defp refute_non_participant(conversation_id, sender) do
    if Conversations.participant?(conversation_id, sender), do: :ok, else: {:error, :not_found}
  end

  # Ecto autogenerates the timestamps only for fields the changeset does not
  # already change, so a supplied `inserted_at` is honoured by putting it there.
  # `updated_at` follows it: nothing ever updates a message, and the two staying
  # equal is the schema's own promise.
  defp put_inserted_at(changeset, %{inserted_at: %DateTime{} = inserted_at}) do
    changeset
    |> Ecto.Changeset.put_change(:inserted_at, inserted_at)
    |> Ecto.Changeset.put_change(:updated_at, inserted_at)
  end

  defp put_inserted_at(changeset, _attrs), do: changeset

  # The sender is the caller's own record, already loaded, so the insert answers
  # with the shape the renderer expects without a round trip to fetch it back.
  defp preload_sender({:ok, %Message{} = message}, sender),
    do: {:ok, %{message | sender: sender}}

  defp preload_sender(other, _sender), do: other

  # --- Read internals -----------------------------------------------------

  # One row beyond the page is what makes `has_more` exact: a conversation
  # holding precisely `limit` messages must report false, which comparing the
  # returned count against the page size alone cannot tell from a full page
  # with more behind it.
  defp history_query(conversation_id, access, cursor, limit) do
    Message
    |> where([m], m.conversation_id == ^conversation_id)
    |> apply_bound(access)
    |> apply_cursor(cursor)
    |> order_by([m], desc: m.inserted_at, desc: m.seq)
    |> limit(^(limit + 1))
    |> join(:inner, [m], u in assoc(m, :sender))
    |> preload([m, u], sender: u)
  end

  defp apply_bound(query, :active), do: query

  defp apply_bound(query, {:until, left_at}),
    do: where(query, [m], m.inserted_at <= ^left_at)

  defp apply_cursor(query, nil), do: query

  # A row constructor, so the planner reads it as a single range bound over the
  # (inserted_at, seq) index rather than an OR that plans as two scans.
  defp apply_cursor(query, {inserted_at, seq}) do
    where(
      query,
      [m],
      fragment(
        "(?, ?) < (?, ?)",
        m.inserted_at,
        m.seq,
        type(^inserted_at, :utc_datetime_usec),
        ^seq
      )
    )
  end

  defp assemble_page(rows, limit) do
    has_more = length(rows) > limit
    page = Enum.take(rows, limit)

    %{
      messages: Enum.reverse(page),
      next_cursor: if(has_more, do: page |> List.last() |> Cursor.encode()),
      has_more: has_more
    }
  end
end
