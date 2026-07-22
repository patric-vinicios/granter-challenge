defmodule Api.Conversations.Participant do
  @moduledoc """
  One member of a conversation.

  Membership is the sole authorization fact the later features read: a private
  thread is exactly two active rows, and `participant?/2` asks only whether a
  row exists with `left_at` null. `joined_at` and `left_at` are the timestamps
  a group re-join and a leave move; a private row keeps `left_at` null for its
  whole life.

  `conversation_id` and `user_id` are set when the struct is built and appear
  in no `cast/3` call — a request body must never be able to name the member or
  the conversation of a row.
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

    timestamps()
  end

  @doc """
  Applies the database guarantees as changeset errors.

  A membership is either representable or it is not, so the changeset only turns
  a duplicate `(conversation_id, user_id)` pair or a dangling reference into
  `{:error, changeset}` rather than a raised exception.
  """
  def changeset(participant, attrs \\ %{}) do
    participant
    |> cast(attrs, [:last_read_at, :joined_at, :left_at])
    |> unique_constraint([:conversation_id, :user_id])
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:user_id)
  end
end
