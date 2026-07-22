defmodule Api.Accounts do
  @moduledoc """
  User accounts and credential verification.

  The single write path for users: registration here and seeding both go
  through `register_user/1`, so a seeded account is hashed and validated
  exactly like one created through the API.
  """

  use Boundary, deps: [Api], exports: [User, Guardian]

  import Ecto.Query, warn: false

  alias Api.Accounts.User
  alias Api.Helpers.Validators
  alias Api.Repo

  @doc """
  Creates an account from registration params.

  A duplicate username comes back as a changeset error on `:username` rather
  than a raised constraint error, so the client receives a 422 naming the field
  instead of a 500.
  """
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Resolves a username and password to a user.

  Both failure branches return the same term and pay the same Argon2 cost: the
  unknown-username branch runs `no_user_verify/0` so response time does not
  disclose whether an account exists.
  """
  def authenticate(username, password) when is_binary(username) and is_binary(password) do
    case get_user_by_username(username) do
      %User{} = user ->
        if Argon2.verify_pass(password, user.hashed_password) do
          {:ok, user}
        else
          {:error, :invalid_credentials}
        end

      nil ->
        Argon2.no_user_verify()
        {:error, :invalid_credentials}
    end
  end

  def authenticate(_username, _password), do: {:error, :invalid_credentials}

  @doc """
  Fetches a user by id, returning `nil` for an unknown or non-UUID id.

  Token subjects and path params both arrive as untrusted strings, so a
  malformed id has to be an absent user rather than a cast exception.
  """
  def get_user(id) when is_binary(id) do
    case Validators.cast_uuid(id) do
      {:ok, uuid} -> Repo.get(User, uuid)
      {:error, _} -> nil
    end
  end

  def get_user(_id), do: nil

  @doc """
  Fetches a user by `@username`, case-insensitively and with the display `@`
  accepted. The `citext` column makes the comparison index-backed without a
  `lower()` wrapper.
  """
  def get_user_by_username(username) when is_binary(username),
    do: Repo.get_by(User, username: User.normalize_username(username))

  def get_user_by_username(_username), do: nil
end
