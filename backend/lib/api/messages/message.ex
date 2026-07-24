defmodule Api.Messages.Message do
  @moduledoc """
  One message in a conversation, private or group alike.

  A row is write-once by construction: nothing updates a message, so
  `updated_at` stays equal to `inserted_at` for its whole life, and the pair
  `(inserted_at, id)` is a stable total order — the anchor keyset pagination
  reads history by.

  `conversation_id`, `sender_id` and `inserted_at` are placed on the struct by
  the context and appear in no `cast/3` call. That is the security surface: a
  request body naming another sender, another conversation or another time is
  not rejected, it is never read. The body is the one field a caller supplies,
  and it is stored verbatim — escaping belongs to the client, and the persisted
  bytes stay identical to what was sent.
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
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "messages" do
    belongs_to :conversation, Conversation
    belongs_to :sender, User
    field :body, :string

    timestamps()
  end

  @doc """
  Casts and bounds the body, and turns every database guarantee into a
  changeset error.

  Trimming happens before the length check, so a whitespace-only body fails as
  an empty one rather than passing as a four-character message.
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
