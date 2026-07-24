defmodule ApiWeb.ConversationController do
  @moduledoc """
  Opening a private conversation, creating a group, and changing a group's
  membership over time.

  The caller is always `conn.assigns.current_user` and is never read from the
  request, so no body or path can act as another user. A repeat open of the same
  private pair is not an error: a first creation answers 201 and every later call
  200 with the identical id. Every failure is a tagged tuple the context returns,
  translated to its status by the fallback controller.
  """

  use ApiWeb, :controller

  alias Api.Conversations

  action_fallback ApiWeb.FallbackController

  plug :put_view, json: ApiWeb.ConversationJSON

  @private_types %{user_id: :string}

  def create_private(conn, params) do
    caller = conn.assigns.current_user

    with {:ok, %{user_id: user_id}} <- validate_private(params),
         {:ok, outcome, conversation} <-
           Conversations.create_private_conversation(caller, user_id) do
      conn
      |> put_status(status_for(outcome))
      |> render(:show, conversation: conversation, caller: caller)
    end
  end

  def create_group(conn, params) do
    caller = conn.assigns.current_user

    with {:ok, conversation} <-
           Conversations.create_group(caller, params["name"], params["member_ids"]) do
      conn
      |> put_status(:created)
      |> render(:show, conversation: conversation, caller: caller)
    end
  end

  def index(conn, params) do
    conversations =
      Conversations.list_conversations(conn.assigns.current_user, %{query: params["q"]})

    render(conn, :index, conversations: conversations)
  end

  def mark_read(conn, %{"id" => id}) do
    with {:ok, result} <- Conversations.mark_read(conn.assigns.current_user, id) do
      render(conn, :read, result: result)
    end
  end

  def show(conn, %{"id" => id}) do
    caller = conn.assigns.current_user

    with {:ok, conversation} <- Conversations.get_conversation(caller, id) do
      render(conn, :show, conversation: conversation, caller: caller)
    end
  end

  def add_members(conn, %{"id" => id} = params) do
    caller = conn.assigns.current_user

    with {:ok, conversation} <- Conversations.add_members(caller, id, params["member_ids"]) do
      # The context is never told channels exist; the controller relays the
      # membership it already observed. Announced only after `:ok`, so every id
      # named was actually seated. Each new member learns of the group on their
      # own personal topic — the one place their session listens before they
      # participate — and fetches the conversation over REST to fill the inbox.
      for user_id <- Enum.uniq(List.wrap(params["member_ids"])) do
        ApiWeb.Endpoint.broadcast("user:#{user_id}", "conversation:added", %{conversation_id: id})
      end

      render(conn, :show, conversation: conversation, caller: caller)
    end
  end

  def remove_member(conn, %{"id" => id, "user_id" => user_id}) do
    with :ok <- Conversations.remove_member(conn.assigns.current_user, id, user_id) do
      # The context is never told channels exist; the controller relays the
      # removal it already observed, and the conversation channel filters it
      # down to the one live socket that must stop. Announced only after `:ok`,
      # so it fires on a removal that actually took effect and never on a
      # voluntary leave, which routes elsewhere.
      ApiWeb.Endpoint.broadcast("conversation:#{id}", "membership_revoked", %{user_id: user_id})
      send_resp(conn, :no_content, "")
    end
  end

  def leave(conn, %{"id" => id}) do
    with :ok <- Conversations.leave(conn.assigns.current_user, id) do
      send_resp(conn, :no_content, "")
    end
  end

  defp status_for(:created), do: :created
  defp status_for(:existing), do: :ok

  # A missing user_id is a malformed request, not an unknown user: answering
  # user_not_found there would tell a client its own bug looks like a typo.
  defp validate_private(params) do
    {%{}, @private_types}
    |> Ecto.Changeset.cast(params, Map.keys(@private_types))
    |> Ecto.Changeset.validate_required([:user_id])
    |> Ecto.Changeset.apply_action(:insert)
  end
end
