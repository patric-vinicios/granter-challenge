defmodule ApiWeb.FallbackController do
  @moduledoc """
  Translates the error tuples contexts return into HTTP responses.

  A controller that declares `action_fallback ApiWeb.FallbackController` can
  end an action with `{:error, :not_found}` and carry no rendering logic of
  its own. Statuses render back through `ApiWeb.ErrorJSON`, which keeps one
  status-to-code table for the whole API.

  Domain reasons that need their own machine code at a status that already has
  a generic one are registered in the reason table below, which is where every
  such code in the API is declared.
  """

  use ApiWeb, :controller

  alias Plug.Conn.Status

  # :unauthorized is 403, not 401: "you may not see this" is a different answer
  # from "you sent no identity", which only the authentication plug decides.
  @statuses %{
    unauthorized: :forbidden,
    forbidden: :forbidden,
    not_found: :not_found,
    conflict: :conflict,
    rate_limited: :too_many_requests,
    unauthenticated: :unauthorized,
    token_expired: :unauthorized
  }

  # Reasons that need a code of their own at a status that already has a
  # generic one. An expired token and a missing header are both 401, yet the
  # client prompts for re-login on the first and treats the second as a bug.
  # Consulted before @statuses; anything absent still renders by status.
  #
  # The 422 entries carry no `fields` key on purpose: they are not field
  # validation failures, and a client branches on `code`, never on the shape of
  # the body. `invalid_id` is the API-wide answer to a path segment that fails a
  # UUID cast — a value that cannot name a row, so 400 reports a malformed
  # request and discloses nothing a 404 would have hidden.
  @reasons %{
    invalid_credentials: {:unauthorized, "invalid_credentials", "Invalid username or password"},
    unauthenticated:
      {:unauthorized, "unauthenticated", "Missing or invalid authentication token"},
    token_expired:
      {:unauthorized, "token_expired", "Your session has expired, please log in again"},
    invalid_id: {:bad_request, "invalid_id", "The provided id is not a valid identifier"},
    user_not_found:
      {:not_found, "user_not_found", "No user with that @username exists in the system"},
    contact_already_exists:
      {:conflict, "contact_already_exists", "This user is already in your contacts"},
    self_contact: {:unprocessable_entity, "self_contact", "You cannot add yourself as a contact"},
    contact_limit_reached:
      {:unprocessable_entity, "contact_limit_reached",
       "You have reached the maximum of 500 contacts"},
    not_a_contact:
      {:forbidden, "not_a_contact", "You can only start conversations with your contacts"},
    self_conversation:
      {:unprocessable_entity, "self_conversation",
       "You cannot start a conversation with yourself"},
    not_group_creator:
      {:forbidden, "not_group_creator", "Only the group creator can manage members"},
    already_member: {:conflict, "already_member", "This user is already a member of the group"},
    last_member: {:unprocessable_entity, "last_member", "A group must keep at least one member"},
    cannot_remove_self:
      {:unprocessable_entity, "cannot_remove_self",
       "The creator cannot remove themselves; leave the group instead"}
  }

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: ApiWeb.ChangesetJSON)
    |> render(:error, changeset: changeset)
  end

  @doc """
  Renders `{:error, reason}` and `{:error, reason, detail}`, where `detail`
  overrides the default message for a failure that needs to say something
  specific.
  """
  def call(conn, {:error, reason}) when is_atom(reason), do: render_error(conn, reason, nil)

  def call(conn, {:error, reason, detail}) when is_atom(reason) and is_binary(detail),
    do: render_error(conn, reason, detail)

  defp render_error(conn, reason, detail) do
    {status, code, default_detail} = error_for(reason)

    conn
    |> put_status(status)
    |> json(%{errors: %{code: code, detail: detail || default_detail}})
  end

  defp error_for(reason) do
    case Map.fetch(@reasons, reason) do
      {:ok, entry} ->
        entry

      :error ->
        status = Map.get(@statuses, reason, :internal_server_error)
        {code, detail} = status |> Status.code() |> ApiWeb.ErrorJSON.error_for()
        {status, code, detail}
    end
  end
end
