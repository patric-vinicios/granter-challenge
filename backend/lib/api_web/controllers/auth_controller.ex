defmodule ApiWeb.AuthController do
  @moduledoc """
  Registration, login and the current-user read.

  Registration and login both answer with the account, a token and the moment
  it expires, so a client is authenticated after one round trip and stores a
  single credential for both HTTP and, later, the socket.
  """

  use ApiWeb, :controller

  alias Api.Accounts
  alias Api.Accounts.Guardian

  action_fallback ApiWeb.FallbackController

  # The user shape is shared API-wide rather than owned by this controller.
  plug :put_view, json: ApiWeb.UserJSON

  @login_types %{username: :string, password: :string}

  @spec register(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def register(conn, params) do
    with {:ok, user} <- Accounts.register_user(params),
         {:ok, token, expires_at} <- Guardian.issue_token(user) do
      conn
      |> put_status(:created)
      |> render(:token, user: user, token: token, expires_at: expires_at)
    end
  end

  @spec login(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def login(conn, params) do
    with {:ok, %{username: username, password: password}} <- validate_login(params),
         {:ok, user} <- Accounts.authenticate(username, password),
         {:ok, token, expires_at} <- Guardian.issue_token(user) do
      render(conn, :token, user: user, token: token, expires_at: expires_at)
    end
  end

  @spec me(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def me(conn, _params), do: render(conn, :show, user: conn.assigns.current_user)

  # A missing field is a malformed request, not a failed login: answering
  # invalid_credentials there would tell a client its own bug looks like a
  # wrong password.
  @spec validate_login(map()) ::
          {:ok, %{username: String.t(), password: String.t()}} | {:error, Ecto.Changeset.t()}
  defp validate_login(params) do
    {%{}, @login_types}
    |> Ecto.Changeset.cast(params, Map.keys(@login_types))
    |> Ecto.Changeset.validate_required([:username, :password])
    |> Ecto.Changeset.apply_action(:insert)
  end
end
