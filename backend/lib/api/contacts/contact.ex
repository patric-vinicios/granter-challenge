defmodule Api.Contacts.Contact do
  @moduledoc """
  One entry in a user's personal contact list.

  The pair is unidirectional: adding someone writes the owner's row and nothing
  else, so the target is neither notified nor modified and gains no row of their
  own. That independence is what later lets a recipient hold a conversation with
  someone they never added.

  Both ids are set when the struct is built and appear in no `cast/3` call — a
  request body must never be able to name the owner of a row.
  """

  use Api.Schema

  alias Api.Accounts.User

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          owner_id: Ecto.UUID.t() | nil,
          owner: User.t() | Ecto.Association.NotLoaded.t() | nil,
          contact_user_id: Ecto.UUID.t() | nil,
          user: User.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "contacts" do
    belongs_to :owner, User
    belongs_to :user, User, foreign_key: :contact_user_id

    timestamps(updated_at: false)
  end

  @doc """
  Applies the database guarantees as changeset errors.

  There is nothing to validate — a pair is either representable or it is not —
  so the changeset exists to turn a unique violation, a self-pair or a dangling
  reference into `{:error, changeset}` rather than a raised `Postgrex.Error`.
  The duplicate case matters most: two devices adding the same contact at once
  race past the context's pre-check and must still answer 409, not 500.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t(t())
  def changeset(contact, attrs \\ %{}) do
    contact
    |> cast(attrs, [])
    |> unique_constraint([:owner_id, :contact_user_id])
    |> check_constraint(:contact_user_id,
      name: :contacts_not_self,
      message: "cannot be the owner"
    )
    |> foreign_key_constraint(:owner_id)
    |> foreign_key_constraint(:contact_user_id)
  end
end
