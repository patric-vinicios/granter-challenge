defmodule Api.Conversations.Conversation do
  @moduledoc """
  A conversation thread, private or group.

  Both kinds live in one table so the features that read them — history, the
  channel topic, the inbox — write one foreign key, join one topic and answer
  one query instead of branching on a kind they would otherwise have to detect.
  The cost is a handful of columns (`name`, `creator_id`, `participant_key`)
  that stay null for the kind they do not belong to and are filled only when the
  matching kind is created.

  A private pair cannot be made unique through the two child participant rows,
  so the invariant is moved onto the parent: `participant_key` is the two user
  ids sorted and joined, and a partial unique index over it (private rows only)
  holds "one conversation per pair". A group carries `name` and `creator_id`
  instead, and a database check keeps the two shapes from mixing.

  `type`, `participant_key` and `creator_id` are set programmatically and never
  cast from a request body.
  """

  use Api.Schema

  alias Api.Accounts.User
  alias Api.Conversations.Participant

  @name_length [min: 1, max: 60]

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
  fills them is below.
  """
  def private_changeset(conversation, participant_key) do
    conversation
    |> cast(%{}, [])
    |> put_change(:type, :private)
    |> put_change(:participant_key, participant_key)
    |> unique_constraint(:participant_key, name: :conversations_participant_key_index)
  end

  @doc """
  Changeset for a new group.

  The name is the only value a caller supplies; `type` is fixed to `:group`
  here and `creator_id` is set on the struct the context builds, so neither can
  arrive from the request body. `participant_key` stays null — it is the private
  pair's uniqueness key and meaningless for a group.
  """
  def group_changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:name])
    |> update_change(:name, &String.trim/1)
    |> put_change(:type, :group)
    |> validate_required([:name])
    |> validate_length(:name, @name_length)
  end
end
