defmodule Api.Accounts.User do
  @moduledoc """
  A person with an identity in the system.

  The `@` in `@anabeatriz` is a display convention: accepted on input, stripped
  before validation and never stored, so the column holds exactly what a URL, a
  token subject or a contact lookup compares against.

  The plaintext password is virtual and dropped from the changeset as soon as it
  is hashed. Both it and `hashed_password` are redacted from `inspect/1` and
  Ecto's struct inspection, so a logged changeset cannot leak a credential.
  """

  use Api.Schema

  @derive {Inspect, except: [:hashed_password, :password]}

  @username_format ~r/^[a-z0-9_]+$/
  @username_length [min: 3, max: 20]
  @name_length [min: 2, max: 60]
  @password_length [min: 8, max: 72]

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          username: String.t() | nil,
          name: String.t() | nil,
          hashed_password: String.t() | nil,
          password: String.t() | nil,
          last_seen_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "users" do
    field :username, :string
    field :name, :string
    field :hashed_password, :string, redact: true
    field :password, :string, virtual: true, redact: true
    field :last_seen_at, :utc_datetime_usec

    timestamps()
  end

  @doc """
  Builds the changeset for a new account.

  ## Parameters

    * `user` — the struct to build on, usually `%User{}`
    * `attrs` — a map with `:username`, `:name` and `:password`

  `last_seen_at` is deliberately absent from the cast — it is presence state,
  written programmatically and never accepted from a request body.

  ## Examples

      iex> Api.Accounts.User.registration_changeset(%Api.Accounts.User{}, %{username: "ana", name: "Ana", password: "senha123"})
      #Ecto.Changeset<valid?: true>
  """
  @spec registration_changeset(t(), map()) :: Ecto.Changeset.t(t())
  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :name, :password])
    |> update_change(:username, &strip_display_prefix/1)
    |> update_change(:name, &String.trim/1)
    |> validate_required([:username, :name, :password])
    |> validate_length(:username, @username_length)
    |> validate_format(:username, @username_format,
      message: "must contain only lowercase letters, digits and underscores"
    )
    |> validate_length(:name, @name_length)
    |> validate_length(:password, @password_length)
    |> hash_password()
    |> unique_constraint(:username)
  end

  @doc """
  Normalizes a username for lookup: strips the display `@` and downcases, so
  logging in as `"@AnaBeatriz"` finds `anabeatriz`.

  ## Parameters

    * `username` — the raw username, possibly decorated with `@` and mixed case

  Registration does not downcase — an uppercase letter there is a rejected
  format, not a value to silently rewrite — but every later resolution accepts
  whatever decoration the user typed. A non-binary argument is returned
  unchanged.

  ## Examples

      iex> Api.Accounts.User.normalize_username("@AnaBeatriz")
      "anabeatriz"

      iex> Api.Accounts.User.normalize_username("  demo ")
      "demo"
  """
  @spec normalize_username(term()) :: term()
  def normalize_username(username) when is_binary(username) do
    username
    |> strip_display_prefix()
    |> String.downcase()
  end

  def normalize_username(username), do: username

  defp strip_display_prefix(username) when is_binary(username) do
    username
    |> String.trim()
    |> String.trim_leading("@")
  end

  defp strip_display_prefix(username), do: username

  defp hash_password(%Ecto.Changeset{valid?: true, changes: %{password: password}} = changeset) do
    changeset
    |> put_change(:hashed_password, Argon2.hash_pwd_salt(password))
    |> delete_change(:password)
  end

  defp hash_password(changeset), do: changeset
end
