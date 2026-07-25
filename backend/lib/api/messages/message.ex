defmodule Api.Messages.Message do
  @moduledoc """
  One message in a conversation. Write-once: nothing updates a row after insert.

  History is ordered by `(inserted_at, seq)` — `inserted_at` for chronology and
  the monotonic `seq` as the insertion-order tiebreak. `conversation_id`,
  `sender_id` and `inserted_at` are set on the struct by the context and never
  cast from a request body.
  """

  use Api.Schema

  alias Api.Accounts.User
  alias Api.Conversations.Conversation

  @body_max_length 4000

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          conversation_id: Ecto.UUID.t() | nil,
          conversation: Conversation.t() | Ecto.Association.NotLoaded.t() | nil,
          sender_id: Ecto.UUID.t() | nil,
          sender: User.t() | Ecto.Association.NotLoaded.t() | nil,
          body: String.t() | nil,
          seq: integer() | nil,
          headline: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "messages" do
    belongs_to :conversation, Conversation
    belongs_to :sender, User
    field :body, :string
    field :seq, :integer, read_after_writes: true
    # Populated only by search, from ts_headline, to compute match offsets.
    field :headline, :string, virtual: true

    timestamps()
  end

  @doc """
  Builds the changeset for a new message.

  ## Parameters

    * `message` — the struct to build on, with `conversation_id` and `sender_id`
      set
    * `attrs` — a map with `:body`

  Casts only `:body`, so `conversation_id`, `sender_id` and `inserted_at` stay
  under the context's control and cannot be set from a request body. Beyond
  trimming and the length bound it turns the database guarantees — the body
  length check constraint and the two foreign keys — into `{:error, changeset}`
  rather than a raised `Postgrex.Error`.

  ## Examples

      iex> Api.Messages.Message.changeset(%Api.Messages.Message{conversation_id: c.id, sender_id: u.id}, %{body: "Olá!"})
      #Ecto.Changeset<valid?: true>
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t(t())
  def changeset(message, attrs \\ %{}) do
    message
    |> cast(attrs, [:body])
    |> update_change(:body, &String.trim/1)
    |> validate_required([:body])
    |> validate_length(:body, min: 1, max: @body_max_length)
    |> check_constraint(:body,
      name: :messages_body_length,
      message: "must be between 1 and #{@body_max_length} characters"
    )
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:sender_id)
  end
end
