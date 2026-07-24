defmodule ApiWeb.Contacts.ContactController do
  @moduledoc """
  The three endpoints that maintain a user's contact list.

  The owner is always `conn.assigns.current_user` and is never read from the
  request, so no body or path can name a list other than the caller's.
  """

  use ApiWeb, :controller

  alias Api.Contacts
  alias Ecto.Changeset

  action_fallback ApiWeb.FallbackController

  plug :put_view, json: ApiWeb.Contacts.ContactJSON

  @add_types %{username: :string}

  @page_types %{limit: :integer, cursor: :string, q: :string}
  @max_limit 200

  @spec create(Plug.Conn.t(), map()) ::
          Plug.Conn.t() | {:error, term()} | {:error, atom(), String.t()}
  def create(conn, params) do
    with {:ok, %{username: username}} <- validate_add(params),
         {:ok, contact} <- Contacts.add_contact(conn.assigns.current_user, username) do
      conn
      |> put_status(:created)
      |> render(:show, contact: contact)
    end
  end

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def index(conn, params) do
    with {:ok, page_params} <- validate_page(params),
         page <- Contacts.list_contacts(conn.assigns.current_user, page_params),
         {:ok, page} <- page_or_error(page) do
      render(conn, :index, page)
    end
  end

  defp page_or_error({:error, reason}), do: {:error, reason}
  defp page_or_error(page), do: {:ok, page}

  defp validate_page(params),
    do:
      ApiWeb.Pagination.validate(params, @page_types,
        default_limit: @max_limit,
        max_limit: @max_limit
      )

  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, :not_found | :invalid_id}
  def delete(conn, %{"id" => id}) do
    with :ok <- Contacts.delete_contact(conn.assigns.current_user, id) do
      send_resp(conn, :no_content, "")
    end
  end

  # A missing username is a malformed request, not an unknown user: answering
  # user_not_found there would tell a client its own bug looks like a typo.
  @spec validate_add(map()) :: {:ok, %{username: String.t()}} | {:error, Changeset.t()}
  defp validate_add(params), do: ApiWeb.Params.validate(params, @add_types)
end
