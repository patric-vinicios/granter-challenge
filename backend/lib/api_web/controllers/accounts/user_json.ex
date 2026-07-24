defmodule ApiWeb.Accounts.UserJSON do
  @moduledoc """
  The one user shape the API returns.

  Every later view that embeds a user — contacts, message senders, group
  members — renders it through `data/1`, so the client writes a single type for
  it and `hashed_password` has one allowlist to escape rather than one per
  feature.
  """

  alias Api.Accounts.User

  @doc """
  Response for an authenticated read of the caller's own account.
  """
  @spec show(%{user: User.t()}) :: map()
  def show(%{user: user}), do: %{user: data(user)}

  @doc """
  Response for registration and login: the account plus the credential the
  client needs for its next request, so neither needs a second round trip.
  """
  @spec token(%{user: User.t(), token: String.t(), expires_at: DateTime.t()}) :: map()
  def token(%{user: user, token: token, expires_at: expires_at}) do
    %{user: data(user), token: token, expires_at: expires_at}
  end

  @doc """
  The canonical user object. `last_seen_at` is null until presence tracking
  writes it.
  """
  @spec data(User.t()) :: map()
  def data(%User{} = user) do
    %{
      id: user.id,
      username: user.username,
      name: user.name,
      last_seen_at: user.last_seen_at
    }
  end
end
