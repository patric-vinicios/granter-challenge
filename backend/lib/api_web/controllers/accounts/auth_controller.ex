defmodule ApiWeb.Accounts.AuthController do
  @moduledoc """
  Registration, login, logout and the current-user read.

  Login and registration answer with the account, a token and its expiry, so a
  client authenticates in one round trip. Login is throttled per IP and per
  username after repeated failures; logout revokes the presented token until it
  would have expired.
  """

  use ApiWeb, :controller

  alias Api.Accounts
  alias Api.Accounts.User
  alias Api.TokenRevocation
  alias ApiWeb.LoginThrottle

  action_fallback ApiWeb.FallbackController

  plug :put_view, json: ApiWeb.Accounts.UserJSON

  @login_types %{username: :string, password: :string}

  @doc "`POST /api/auth/register` — creates an account and returns it with a token and expiry (201)."
  @spec register(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def register(conn, params) do
    with {:ok, user} <- Accounts.register_user(params),
         {:ok, token, expires_at} <- Accounts.Guardian.issue_token(user) do
      conn
      |> put_status(:created)
      |> render(:token, user: user, token: token, expires_at: expires_at)
    end
  end

  @doc "`POST /api/auth/login` — authenticates and returns the user, a token and expiry, or 429 when throttled."
  @spec login(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def login(conn, params) do
    with {:ok, credentials} <- validate_login(params) do
      attempt_login(conn, credentials)
    end
  end

  @doc "`DELETE /api/auth/session` — revokes the presented token until it expires (204)."
  @spec logout(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def logout(conn, _params) do
    claims = Guardian.Plug.current_claims(conn)
    TokenRevocation.revoke(claims["jti"], claims["exp"])
    send_resp(conn, :no_content, "")
  end

  @doc "`GET /api/auth/me` — returns the authenticated user."
  @spec me(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def me(conn, _params), do: render(conn, :show, user: conn.assigns.current_user)

  defp attempt_login(conn, %{username: username, password: password}) do
    uname = User.normalize_username(username)

    case LoginThrottle.check(conn.remote_ip, uname) do
      {:error, retry_after} ->
        rate_limited(conn, retry_after)

      :ok ->
        case Accounts.authenticate(username, password) do
          {:ok, user} ->
            issue(conn, user)

          {:error, :invalid_credentials} = error ->
            LoginThrottle.fail(conn.remote_ip, uname)
            error
        end
    end
  end

  defp issue(conn, user) do
    with {:ok, token, expires_at} <- Accounts.Guardian.issue_token(user) do
      render(conn, :token, user: user, token: token, expires_at: expires_at)
    end
  end

  defp rate_limited(conn, retry_after) do
    conn
    |> put_resp_header("retry-after", Integer.to_string(retry_after))
    |> put_status(:too_many_requests)
    |> json(%{
      errors: %{code: "rate_limited", detail: "Too many login attempts, retry in #{retry_after}s"}
    })
  end

  defp validate_login(params), do: ApiWeb.Params.validate(params, @login_types)
end
