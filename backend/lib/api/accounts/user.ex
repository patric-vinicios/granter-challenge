defmodule Api.Accounts.User do
  @moduledoc """
  A person with an identity in the system.

  The `@` in `@anabeatriz` is a display convention: it is accepted on input,
  stripped before validation, and never stored, so the column holds exactly
  what a URL, a token subject or a contact lookup compares against.

  The plaintext password is virtual and is dropped from the changeset the
  moment it is hashed, and the hash itself is redacted from both `inspect/1`
  and Ecto's own struct inspection, so a logged changeset cannot leak a
  credential.
  """

  use Api.Schema

  alias Api.Providers.Hash.Client, as: HashClient

  @derive {Inspect, except: [:hashed_password, :password]}

  @username_format ~r/^[a-z0-9_]+$/
  @username_length [min: 3, max: 20]
  @name_length [min: 2, max: 60]
  @password_length [min: 8, max: 72]

  schema "users" do
    field :username, :string
    field :name, :string
    field :hashed_password, :string, redact: true
    field :password, :string, virtual: true, redact: true
    field :last_seen_at, :utc_datetime_usec

    timestamps()
  end

  @doc """
  Changeset for a new account.

  `last_seen_at` is deliberately absent from the cast: it is presence state,
  written programmatically, never accepted from a request body.
  """
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
  Normalises a username for *lookup*: strips the display `@` and downcases, so
  logging in as `"@AnaBeatriz"` finds `anabeatriz`.

  Registration deliberately does not downcase — an uppercase letter there is a
  rejected format, not a value to be silently rewritten — but every later
  resolution has to accept whatever decoration the user typed.
  """
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
    |> put_change(:hashed_password, HashClient.hash_password(password))
    |> delete_change(:password)
  end

  defp hash_password(changeset), do: changeset
end
