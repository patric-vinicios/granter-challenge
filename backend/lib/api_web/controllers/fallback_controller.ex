defmodule ApiWeb.FallbackController do
  @moduledoc """
  Translates the error tuples contexts return into HTTP responses.

  Every controller from F02 onwards declares `action_fallback
  ApiWeb.FallbackController`, so an action can end with `{:error, :not_found}`
  and contain no rendering logic of its own. Statuses render back through
  `ApiWeb.ErrorJSON`, which keeps one status-to-code table for the API.
  """

  use ApiWeb, :controller

  alias Plug.Conn.Status

  # Contexts signal "the caller may not see this" with :unauthorized, which is
  # a 403: a 401 means the request carried no valid identity at all, and that
  # is decided by the authentication plug, not by a context.
  @statuses %{
    unauthorized: :forbidden,
    forbidden: :forbidden,
    not_found: :not_found,
    conflict: :conflict,
    rate_limited: :too_many_requests,
    unauthenticated: :unauthorized,
    token_expired: :unauthorized
  }

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: ApiWeb.ChangesetJSON)
    |> render(:error, changeset: changeset)
  end

  @doc """
  Renders `{:error, reason}` and `{:error, reason, detail}`, where `detail`
  overrides the table's default message for cases that need to say something
  specific about this particular failure.
  """
  def call(conn, {:error, reason}) when is_atom(reason) do
    render_error(conn, status_for(reason), nil)
  end

  def call(conn, {:error, reason, detail}) when is_atom(reason) and is_binary(detail) do
    render_error(conn, status_for(reason), detail)
  end

  defp status_for(reason), do: Map.get(@statuses, reason, :internal_server_error)

  defp render_error(conn, status, detail) do
    code = Status.code(status)
    {error_code, default_detail} = ApiWeb.ErrorJSON.error_for(code)

    conn
    |> put_status(status)
    |> json(%{errors: %{code: error_code, detail: detail || default_detail}})
  end
end
