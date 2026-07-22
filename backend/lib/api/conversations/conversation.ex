defmodule Api.Conversations.Conversation do
  @moduledoc """
  A conversation, private or group, held in one table.

  Modelling both kinds as rows discriminated by `type` is what lets every
  downstream feature carry a single `conversation_id`: messages, the inbox and
  the channel never fork into a private path and a group path that must be kept
  identical by hand. The price is a handful of columns meaningful to only one
  type — `name` and `creator_id` are null for a private conversation — which a
  database check keeps honest so a row can never mix the two shapes.

  `type` and `creator_id` are set when the struct is built and appear in no
  `cast/3` call: a request body must never be able to name a group's owner or
  turn a private conversation into a group.
  """

  use Api.Schema

  alias Api.Accounts.User
  alias Api.Conversations.ConversationParticipant

  @name_length [min: 1, max: 60]

  schema "conversations" do
    field :type, Ecto.Enum, values: [:private, :group]
    field :name, :string
    belongs_to :creator, User
    has_many :participants, ConversationParticipant

    timestamps()
  end

  @doc """
  Changeset for a new group.

  The name is the only value a caller supplies; `type` is fixed to `:group`
  here and `creator_id` is set on the struct the context builds, so neither can
  arrive from the request body. The name-matches-type check is applied as a
  changeset constraint so a slip past the length validation surfaces as
  `{:error, changeset}` rather than a raised `Postgrex.Error`.
  """
  def group_changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:name])
    |> update_change(:name, &String.trim/1)
    |> put_change(:type, :group)
    |> validate_required([:name])
    |> validate_length(:name, @name_length)
    |> check_constraint(:name,
      name: :conversations_name_matches_type,
      message: "is required for a group"
    )
  end
end
