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
  alias Api.Repo

  @doc """
  Creates an account from registration params.

  A duplicate username comes back as a changeset error on `:username` rather
  than a raised constraint error, so the client receives a 422 naming the field
  instead of a 500.
  """
  @spec register_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t(User.t())}
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
  @spec authenticate(term(), term()) :: {:ok, User.t()} | {:error, :invalid_credentials}
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
  @spec get_user(term()) :: User.t() | nil
  def get_user(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(User, uuid)
      :error -> nil
    end
  end

  def get_user(_id), do: nil

  @doc """
  Fetches a user by `@username`, case-insensitively and with the display `@`
  accepted. The `citext` column makes the comparison index-backed without a
  `lower()` wrapper.
  """
  @spec get_user_by_username(term()) :: User.t() | nil
  def get_user_by_username(username) when is_binary(username),
    do: Repo.get_by(User, username: User.normalize_username(username))

  def get_user_by_username(_username), do: nil

  @doc """
  Stamps a user's `last_seen_at`, the one write path for the column.

  Presence, not a request, owns this field, so the write bypasses every
  changeset: a scoped `update_all` sets exactly `last_seen_at` for one id and
  leaves `updated_at`'s "profile changed" meaning untouched. A malformed or
  unknown id is a silent no-op — a presence write for a since-deleted account
  must never raise or block the leave that triggered it — so the answer is
  always `:ok`.
  """
  @spec update_last_seen(term(), term()) :: :ok
  def update_last_seen(user_id, %DateTime{} = at) when is_binary(user_id) do
    case Ecto.UUID.cast(user_id) do
      {:ok, uuid} ->
        Repo.update_all(from(u in User, where: u.id == ^uuid), set: [last_seen_at: at])
        :ok

      :error ->
        :ok
    end
  end

  def update_last_seen(_user_id, _at), do: :ok
end
