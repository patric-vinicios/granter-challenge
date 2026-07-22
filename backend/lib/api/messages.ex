defmodule Api.Messages do
  @moduledoc """
  Everything written into a conversation, and every page read back out of it.

  `create_message/3` is the single write path. The REST layer never calls it —
  messages are sent over the channel — and the channel, the seed script and the
  tests all share it, so the participation gate and the body rules are enforced
  in exactly one place. It casts `:body` and nothing else: the sender comes from
  the authenticated caller, the conversation from the request path, and the
  insertion time from the caller's own attributes only because the seed script
  needs to backdate a demo conversation. A request body can set none of them.

  `list_messages/3` reads history by keyset rather than by offset, and the
  reason is correctness before it is speed. Messages arrive while a user
  scrolls; under `OFFSET` a single insert between two requests shifts every row
  down by one, so the second page re-serves a message the client already
  rendered, and a delete would skip one instead. A cursor anchored on the row's
  own `(inserted_at, id)` names a position in a total order rather than a count
  of rows preceding it, so neither can happen — and, as a dividend, the
  ten-thousandth page costs what the first one does.
  """

  use Boundary, deps: [Api, Api.Accounts, Api.Conversations], exports: [Message]

  import Ecto.Query, warn: false

  alias Api.Accounts.User
  alias Api.Conversations
  alias Api.Messages.Cursor
  alias Api.Messages.Message
  alias Api.Repo

  # What a page holds when the caller asks for no particular size, and the
  # ceiling the endpoint enforces before the query is ever built.
  @default_limit 30
  @max_limit 100

  @doc """
  Persists a message from `sender` into the conversation named by
  `conversation_id`.

  Gated on active participation, so a non-member and a departed group member are
  both answered `:not_found` — writing is a question about the present, and a
  conversation's existence is never disclosed by the difference between the two.

  `attrs` carries `:body`, and optionally an `:inserted_at` for backdated data.
  Only `:body` is cast; the timestamp is placed on the struct, which is why a
  caller that merely forwards a request body is structurally incapable of
  setting one.
  """
  def create_message(%User{} = sender, conversation_id, attrs \\ %{}) do
    attrs = Map.new(attrs)

    with {:ok, cid} <- cast_id(conversation_id),
         :ok <- refute_non_participant(cid, sender) do
      %Message{conversation_id: cid, sender_id: sender.id}
      |> Message.changeset(attrs)
      |> put_inserted_at(attrs)
      |> Repo.insert()
      |> preload_sender(sender)
    end
  end

  @doc """
  One page of `conversation_id`'s history for `caller`, newest first internally
  and ascending on the way out.

  `opts` takes `:limit` (defaulting to #{@default_limit}, capped at #{@max_limit})
  and `:before`, the opaque cursor of the oldest message the caller already
  holds. Returns `{:ok, %{messages: messages, next_cursor: cursor, has_more: bool}}`.

  A departed group member is bounded at their `left_at` inside the query rather
  than by filtering a fetched page, so `has_more` and `next_cursor` describe the
  history they are allowed to see and never leak, through a page count, that
  the conversation carried on without them.
  """
  def list_messages(%User{} = caller, conversation_id, opts \\ %{}) do
    opts = Map.new(opts)
    limit = opts |> Map.get(:limit) |> normalize_limit()

    with {:ok, cid} <- cast_id(conversation_id),
         {:ok, access} <- Conversations.read_access(cid, caller),
         {:ok, cursor} <- decode_cursor(Map.get(opts, :before)) do
      cid
      |> history_query(access, cursor, limit)
      |> Repo.all()
      |> assemble_page(limit)
      |> then(&{:ok, &1})
    end
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

  defp normalize_limit(nil), do: @default_limit
  defp normalize_limit(limit) when limit < 1, do: 1
  defp normalize_limit(limit) when limit > @max_limit, do: @max_limit
  defp normalize_limit(limit), do: limit

  defp decode_cursor(nil), do: {:ok, nil}
  defp decode_cursor(""), do: {:ok, nil}
  defp decode_cursor(cursor), do: Cursor.decode(cursor)

  # One row beyond the page is what makes `has_more` exact: a conversation
  # holding precisely `limit` messages must report false, which comparing the
  # returned count against the page size alone cannot tell from a full page
  # with more behind it.
  defp history_query(conversation_id, access, cursor, limit) do
    Message
    |> where([m], m.conversation_id == ^conversation_id)
    |> apply_bound(access)
    |> apply_cursor(cursor)
    |> order_by([m], desc: m.inserted_at, desc: m.id)
    |> limit(^(limit + 1))
    |> join(:inner, [m], u in assoc(m, :sender))
    |> preload([m, u], sender: u)
  end

  defp apply_bound(query, :active), do: query

  defp apply_bound(query, {:until, left_at}),
    do: where(query, [m], m.inserted_at <= ^left_at)

  defp apply_cursor(query, nil), do: query

  # Written as a row constructor rather than the equivalent
  # `inserted_at < ? OR (inserted_at = ? AND id < ?)`: the row form is what the
  # planner recognises as a single range bound over the composite index, while
  # the expanded form frequently plans as two scans and a merge.
  defp apply_cursor(query, {inserted_at, id}) do
    where(
      query,
      [m],
      fragment(
        "(?, ?) < (?, ?)",
        m.inserted_at,
        m.id,
        type(^inserted_at, :utc_datetime_usec),
        type(^id, Ecto.UUID)
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

  defp cast_id(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :invalid_id}
    end
  end
end
