defmodule ApiWeb.MessageController do
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

  action_fallback ApiWeb.FallbackController

  plug :put_view, json: ApiWeb.MessageJSON

  @page_types %{limit: :integer, before: :string}
  @default_limit 30
  @max_limit 100

  def index(conn, %{"id" => id} = params) do
    with {:ok, page_params} <- validate_page(params),
         {:ok, page} <- Messages.list_messages(conn.assigns.current_user, id, page_params) do
      render(conn, :index, page)
    end
  end

  @limit_message "must be between 1 and #{@max_limit}"

  # A non-numeric `limit` fails the cast and an out-of-range one the numeric
  # bound. Both answer with the same sentence under `fields.limit`, so a client
  # reads the accepted range off either failure rather than guessing the cap.
  defp validate_page(params) do
    {%{limit: @default_limit}, @page_types}
    |> Ecto.Changeset.cast(params, Map.keys(@page_types), message: &cast_message/2)
    |> Ecto.Changeset.validate_number(:limit,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: @max_limit,
      message: @limit_message
    )
    |> Ecto.Changeset.apply_action(:insert)
  end

  defp cast_message(:limit, _meta), do: @limit_message
  defp cast_message(_field, _meta), do: nil
end
