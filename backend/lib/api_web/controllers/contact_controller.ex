defmodule ApiWeb.ContactController do
  @moduledoc """
  The three endpoints that maintain a user's contact list.

  The owner is always `conn.assigns.current_user` and is never read from the
  request, so no body or path can name a list other than the caller's.
  """

  use ApiWeb, :controller

  alias Api.Contacts

  action_fallback ApiWeb.FallbackController

  plug :put_view, json: ApiWeb.ContactJSON

  @add_types %{username: :string}

  def create(conn, params) do
    with {:ok, %{username: username}} <- validate_add(params),
         {:ok, contact} <- Contacts.add_contact(conn.assigns.current_user, username) do
      conn
      |> put_status(:created)
      |> render(:show, contact: contact)
    end
  end

  def index(conn, _params) do
    render(conn, :index, contacts: Contacts.list_contacts(conn.assigns.current_user))
  end

  def delete(conn, %{"id" => id}) do
    with :ok <- Contacts.delete_contact(conn.assigns.current_user, id) do
      send_resp(conn, :no_content, "")
    end
  end

  # A missing username is a malformed request, not an unknown user: answering
  # user_not_found there would tell a client its own bug looks like a typo.
  defp validate_add(params) do
    {%{}, @add_types}
    |> Ecto.Changeset.cast(params, Map.keys(@add_types))
    |> Ecto.Changeset.validate_required([:username])
    |> Ecto.Changeset.apply_action(:insert)
  end
end
