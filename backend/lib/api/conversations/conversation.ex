defmodule Api.Conversations.Conversation do
  @moduledoc """
  A conversation thread, private or group.

  Both kinds live in one table so the features that read them — history, the
  channel topic, the inbox — write one foreign key, join one topic and answer
  one query instead of branching on a kind they would otherwise have to detect.
  The cost is a handful of columns (`name`, `creator_id`) that stay null for a
  private row and are filled only when a group is created.

  A private pair cannot be made unique through the two child participant rows,
  so the invariant is moved onto the parent: `participant_key` is the two user
  ids sorted and joined, and a partial unique index over it (private rows only)
  holds "one conversation per pair". The changeset applies that constraint so a
  genuine race surfaces as `{:error, changeset}` for the context to turn into a
  200, never a raised `Postgrex.Error`.

  `type` and `participant_key` are set programmatically and never cast from a
  request body.
  """

  use Api.Schema

  alias Api.Accounts.User
  alias Api.Conversations.Participant

  schema "conversations" do
    field :type, Ecto.Enum, values: [:private, :group]
    field :name, :string
    field :participant_key, :string

    belongs_to :creator, User
    has_many :participants, Participant

    timestamps()
  end

  @doc """
  Builds a private conversation from its computed pair key.

  There is nothing castable: `type` and `participant_key` are fixed by the
  context, so the changeset exists only to attach the participant-key unique
  constraint. `name` and `creator_id` stay null here; the group changeset that
  fills them belongs to the group feature.
  """
  def private_changeset(conversation, participant_key) do
    conversation
    |> cast(%{}, [])
    |> put_change(:type, :private)
    |> put_change(:participant_key, participant_key)
    |> unique_constraint(:participant_key, name: :conversations_participant_key_index)
  end
end
