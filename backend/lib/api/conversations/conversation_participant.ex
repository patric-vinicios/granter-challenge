defmodule Api.Conversations.ConversationParticipant do
  @moduledoc """
  One user's membership in one conversation, modelled as a timeline rather than
  a set.

  A participant is a row with a `joined_at` and a nullable `left_at`; leaving
  sets `left_at` instead of deleting the row. That soft record is the boundary
  three later rules are written against — a departed member keeps read access to
  messages sent before they left, a re-added member reuses their row with a
  fresh `joined_at`, and unread counting can exclude messages sent after
  departure. A hard delete would discard exactly that timestamp.

  There is no default `timestamps()` pair: `joined_at` is the creation instant,
  and the columns that change afterwards (`left_at`, `last_read_at`) are domain
  state, not audit metadata. Both foreign keys are set when the struct is built
  and appear in no `cast/3` call.
  """

  use Api.Schema

  alias Api.Accounts.User
  alias Api.Conversations.Conversation

  schema "conversation_participants" do
    belongs_to :conversation, Conversation
    belongs_to :user, User
    field :last_read_at, :utc_datetime_usec
    field :joined_at, :utc_datetime_usec
    field :left_at, :utc_datetime_usec
  end

  @doc """
  Applies the database guarantees as changeset errors.

  There is nothing to validate — the ids and timestamps are set when the struct
  is built — so the changeset exists only to turn a duplicate seat or a dangling
  reference into `{:error, changeset}` rather than a raised `Postgrex.Error`.
  """
  def changeset(participant, attrs \\ %{}) do
    participant
    |> cast(attrs, [])
    |> unique_constraint([:conversation_id, :user_id])
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:user_id)
  end
end
