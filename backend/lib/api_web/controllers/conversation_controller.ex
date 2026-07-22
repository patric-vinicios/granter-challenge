defmodule ApiWeb.ConversationController do
  @moduledoc """
  The endpoints that open and read a private conversation.

  The caller is always `conn.assigns.current_user` and is never read from the
  request, so no body or path can act as another user. A repeat open of the same
  pair is not an error: a first creation answers 201 and every later call 200,
  with the identical conversation id, so a client treats the two alike.
  """

  use ApiWeb, :controller

  alias Api.Conversations

  action_fallback ApiWeb.FallbackController

  plug :put_view, json: ApiWeb.ConversationJSON

  @create_types %{user_id: :string}

  def create_private(conn, params) do
    caller = conn.assigns.current_user

    with {:ok, %{user_id: user_id}} <- validate_create(params),
         {:ok, outcome, conversation} <-
           Conversations.create_private_conversation(caller, user_id) do
      conn
      |> put_status(status_for(outcome))
      |> render(:show, conversation: conversation, caller: caller)
    end
  end

  def show(conn, %{"id" => id}) do
    caller = conn.assigns.current_user

    with {:ok, conversation} <- Conversations.get_conversation(caller, id) do
      render(conn, :show, conversation: conversation, caller: caller)
    end
  end

  defp status_for(:created), do: :created
  defp status_for(:existing), do: :ok

  # A missing user_id is a malformed request, not an unknown user: answering
  # user_not_found there would tell a client its own bug looks like a typo.
  defp validate_create(params) do
    {%{}, @create_types}
    |> Ecto.Changeset.cast(params, Map.keys(@create_types))
    |> Ecto.Changeset.validate_required([:user_id])
    |> Ecto.Changeset.apply_action(:insert)
  end
end
