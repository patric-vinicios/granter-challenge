defmodule ApiWeb.ConversationController do
  @moduledoc """
  Creating a group and changing its membership over time.

  The caller is always `conn.assigns.current_user` and is never read from the
  request, so no body or path can act on a conversation as somebody else. Every
  failure is a tagged tuple the context returns, translated to its status by the
  fallback controller. The private-conversation feature adds its own
  `create_private/2` action to this same module.
  """

  use ApiWeb, :controller

  alias Api.Conversations

  action_fallback ApiWeb.FallbackController

  plug :put_view, json: ApiWeb.ConversationJSON

  def create_group(conn, params) do
    with {:ok, conversation} <-
           Conversations.create_group(
             conn.assigns.current_user,
             params["name"],
             params["member_ids"]
           ) do
      conn
      |> put_status(:created)
      |> render(:create, conversation: conversation)
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, conversation} <- Conversations.get_for_user(conn.assigns.current_user, id) do
      render(conn, :show, conversation: conversation)
    end
  end

  def add_members(conn, %{"id" => id} = params) do
    with {:ok, conversation} <-
           Conversations.add_members(conn.assigns.current_user, id, params["member_ids"]) do
      render(conn, :show, conversation: conversation)
    end
  end

  def remove_member(conn, %{"id" => id, "user_id" => user_id}) do
    with :ok <- Conversations.remove_member(conn.assigns.current_user, id, user_id) do
      send_resp(conn, :no_content, "")
    end
  end

  def leave(conn, %{"id" => id}) do
    with :ok <- Conversations.leave(conn.assigns.current_user, id) do
      send_resp(conn, :no_content, "")
    end
  end
end
