defmodule ApiWeb.Conversations.MessageController do
  @moduledoc """
  Reading a conversation's history, one page at a time.

  Read-only by design: messages are written over the channel, so there is no
  send action here and the history endpoint is the whole REST surface for them.

  The pagination parameters are validated by a schemaless changeset before any
  domain call, so an out-of-range `limit` is a 422 naming the accepted range
  rather than a query the database is asked to run. The caller is always
  `conn.assigns.current_user`, and access is decided before the cursor is even
  decoded — an outsider gets the same `not_found` a missing conversation gets,
  and can never use the difference between that and `invalid_cursor` to learn
  whether a conversation exists.
  """

  use ApiWeb, :controller

  alias Api.Messages
  alias Ecto.Changeset

  action_fallback ApiWeb.FallbackController

  plug :put_view, json: ApiWeb.Conversations.MessageJSON

  @page_types %{limit: :integer, before: :string}
  @default_limit 30
  @max_limit 100

  @search_types %{q: :string}
  @query_min 2
  @query_max 100

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def index(conn, %{"id" => id} = params) do
    with {:ok, page_params} <- validate_page(params),
         {:ok, page} <- Messages.list_messages(conn.assigns.current_user, id, page_params) do
      render(conn, :index, page)
    end
  end

  # `q` is validated before the domain call, so a too-short term is a 422 naming
  # the field rather than a query the database is asked to run — the "no scan on
  # a rejected query" guarantee. The check runs even for a non-participant, so a
  # bad term is 422 before access is ever consulted.
  @spec search(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def search(conn, %{"id" => id} = params) do
    with {:ok, %{q: q}} <- validate_query(params),
         {:ok, page_params} <- validate_page(params),
         {:ok, result} <- Messages.search_messages(conn.assigns.current_user, id, q, page_params) do
      render(conn, :search, result)
    end
  end

  defp validate_page(params),
    do:
      ApiWeb.Pagination.validate(params, @page_types,
        default_limit: @default_limit,
        max_limit: @max_limit
      )

  @query_message "must be between #{@query_min} and #{@query_max} characters"

  # `q` is trimmed before it is measured, so trailing spaces neither pad a short
  # term to length nor overflow a full one. A blank or absent `q` fails the
  # required check; both failures render under `fields.q`.
  @spec validate_query(map()) :: {:ok, %{q: String.t()}} | {:error, Changeset.t()}
  defp validate_query(params) do
    ApiWeb.Params.validate(params, @search_types,
      trim: [:q],
      required_message: @query_message,
      validate:
        &Changeset.validate_length(&1, :q,
          min: @query_min,
          max: @query_max,
          message: @query_message
        )
    )
  end
end
