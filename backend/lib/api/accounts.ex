defmodule Api.Accounts do
  @moduledoc """
  User accounts and credential verification.

  Registration and seeding share `register_user/1`, so every account is hashed
  and validated the same way regardless of where it is created.
  """

  use Boundary, deps: [Api], exports: [User, Guardian]

  import Ecto.Query, warn: false

  alias Api.Accounts.User
  alias Api.Repo
  alias Api.UUID

  @doc """
  Registers an account from the given attributes.

  ## Parameters

    * `attrs` — a map with `:username`, `:name` and `:password`

  Returns `{:ok, user}` on success and `{:error, changeset}` on invalid input. A
  duplicate username surfaces as a changeset error on `:username` rather than a
  raised constraint error, so the client receives a 422 naming the field instead
  of a 500.

  ## Examples

      iex> Api.Accounts.register_user(%{username: "anabeatriz", name: "Ana Beatriz", password: "senha123"})
      {:ok, %Api.Accounts.User{username: "anabeatriz"}}

      iex> Api.Accounts.register_user(%{username: "ab", name: "Ana", password: "short"})
      {:error, %Ecto.Changeset{valid?: false}}
  """
  @spec register_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t(User.t())}
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Verifies a username and password.

  ## Parameters

    * `username` — the `@username`, with or without a leading `@`
    * `password` — the plaintext password to check

  Returns `{:ok, user}` on a match and `{:error, :invalid_credentials}`
  otherwise. Both failure paths pay the same Argon2 cost — the unknown-username
  path runs `Argon2.no_user_verify/0` — so timing never reveals whether an
  account exists.

  ## Examples

      iex> Api.Accounts.authenticate("anabeatriz", "senha123")
      {:ok, %Api.Accounts.User{username: "anabeatriz"}}

      iex> Api.Accounts.authenticate("anabeatriz", "wrong")
      {:error, :invalid_credentials}
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
  Fetches a user by `id`.

  ## Parameters

    * `id` — a user id, as a UUID string

  Returns the user, or `nil` for an unknown or non-UUID id. Token subjects and
  path params arrive as untrusted strings, so a malformed id yields an absent
  user rather than a cast exception.

  ## Examples

      iex> Api.Accounts.get_user(user.id)
      %Api.Accounts.User{}

      iex> Api.Accounts.get_user("not-a-uuid")
      nil
  """
  @spec get_user(term()) :: User.t() | nil
  def get_user(id) when is_binary(id) do
    case UUID.cast(id) do
      {:ok, uuid} -> Repo.get(User, uuid)
      {:error, :invalid_id} -> nil
    end
  end

  def get_user(_id), do: nil

  @doc """
  Fetches a user by `@username`, case-insensitively and accepting a leading `@`.

  ## Parameters

    * `username` — the `@username`, with or without a leading `@`

  Returns the user or `nil`. The `citext` column keeps the comparison
  index-backed without a `lower()` wrapper.

  ## Examples

      iex> Api.Accounts.get_user_by_username("@AnaBeatriz")
      %Api.Accounts.User{username: "anabeatriz"}

      iex> Api.Accounts.get_user_by_username("ghost")
      nil
  """
  @spec get_user_by_username(term()) :: User.t() | nil
  def get_user_by_username(username) when is_binary(username),
    do: Repo.get_by(User, username: User.normalize_username(username))

  def get_user_by_username(_username), do: nil

  @doc """
  Sets a user's `last_seen_at`. Always returns `:ok`.

  ## Parameters

    * `user_id` — the user's id, as a UUID string
    * `at` — the `DateTime` to record

  Presence, not a request, owns this field, so the write bypasses the changeset:
  a scoped `update_all` sets only `last_seen_at` and leaves `updated_at`'s
  "profile changed" meaning untouched. A malformed or unknown id is a no-op — a
  presence write for a since-deleted account must never raise or block the leave
  that triggered it.

  ## Examples

      iex> Api.Accounts.update_last_seen(user.id, DateTime.utc_now())
      :ok
  """
  @spec update_last_seen(term(), term()) :: :ok
  def update_last_seen(user_id, %DateTime{} = at) when is_binary(user_id) do
    case UUID.cast(user_id) do
      {:ok, uuid} ->
        Repo.update_all(from(u in User, where: u.id == ^uuid), set: [last_seen_at: at])
        :ok

      {:error, :invalid_id} ->
        :ok
    end
  end

  def update_last_seen(_user_id, _at), do: :ok

  @doc """
  A dynamic `where` condition matching users whose display name or `@username`
  contains `term`, for a query that names its `users` binding `:user`.

  ## Parameters

    * `term` — a non-blank substring to match against name and `@username`

  The contact list and the conversation inbox both search people and must agree
  on what a match is, so the rule lives here on the context that owns the
  columns. `immutable_unaccent` makes `familia` match `Família` and `ILIKE`
  makes it case-insensitive; the operands are spelled exactly as
  `users_name_trgm_index` and `users_username_trgm_index` spell them, since an
  expression index is only used when the query writes the expression the same
  way. A blank term matches everyone, so callers drop it beforehand.

  ## Examples

      iex> from(u in User, as: :user) |> where(^Api.Accounts.matching_user("ana"))
      #Ecto.Query<...>
  """
  @spec matching_user(String.t()) :: Ecto.Query.dynamic_expr()
  def matching_user(term) when is_binary(term) do
    like = "%" <> String.trim(term) <> "%"

    dynamic(
      [user: u],
      fragment("immutable_unaccent(?) ILIKE immutable_unaccent(?)", u.name, ^like) or
        fragment("immutable_unaccent(?::text) ILIKE immutable_unaccent(?)", u.username, ^like)
    )
  end

  @doc """
  Normalizes a search term.

  ## Parameters

    * `term` — the raw search string from the request

  Returns `{:ok, trimmed}` for a term that narrows the result, or `:none` for a
  blank or absent one. Both list endpoints drop `:none` before querying.

  ## Examples

      iex> Api.Accounts.search_term("  ana  ")
      {:ok, "ana"}

      iex> Api.Accounts.search_term("   ")
      :none
  """
  @spec search_term(term()) :: {:ok, String.t()} | :none
  def search_term(term) when is_binary(term) do
    case String.trim(term) do
      "" -> :none
      trimmed -> {:ok, trimmed}
    end
  end

  def search_term(_term), do: :none
end
