defmodule ApiWeb.MessageSearchControllerTest do
  use ApiWeb.ConnCase, async: true

  alias Api.Accounts.Guardian
  alias Api.Messages
  alias Api.Messages.Message
  alias Api.Repo

  setup do
    ana = insert(:user, name: "Ana Beatriz")
    carlos = insert(:user, name: "Carlos Eduardo")
    outsider = insert(:user, name: "João Pedro")
    thread = private_conversation(ana, carlos)

    {:ok,
     conn: authenticate(json_conn(), ana),
     ana: ana,
     carlos: carlos,
     outsider: outsider,
     thread: thread}
  end

  defp authenticate(conn, user) do
    {:ok, token, _expires_at} = Guardian.issue_token(user)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  defp write(conversation, sender, body, inserted_at) do
    {:ok, message} =
      Messages.create_message(sender, conversation.id, %{body: body, inserted_at: inserted_at})

    message
  end

  defp bulk(conversation, sender, term, count) do
    base = DateTime.utc_now() |> DateTime.add(-count - 1, :second)

    entries =
      for i <- 1..count do
        at = DateTime.add(base, i, :second)

        %{
          id: Ecto.UUID.generate(),
          conversation_id: conversation.id,
          sender_id: sender.id,
          body: "#{term} #{i}",
          inserted_at: at,
          updated_at: at
        }
      end

    Repo.insert_all(Message, entries)
  end

  defp search(conn, conversation_id, q) do
    get(conn, ~p"/api/conversations/#{conversation_id}/messages/search", %{"q" => q})
  end

  defp ago(seconds), do: DateTime.add(DateTime.utc_now(), -seconds, :second)

  describe "GET /api/conversations/:id/messages/search" do
    test "returns hits with position, match_offsets, id and body", %{
      conn: conn,
      ana: ana,
      thread: thread
    } do
      write(thread, ana, "O cronograma novo", ago(30))
      write(thread, ana, "assunto qualquer", ago(20))
      newest = write(thread, ana, "cronograma final", ago(10))

      body = conn |> search(thread.id, "cronograma") |> json_response(200)

      assert body["total_matches"] == 2
      assert body["truncated"] == false

      [first | _] = body["messages"]
      assert first["id"] == newest.id
      assert first["body"] == "cronograma final"
      assert first["position"] == 1
      assert first["match_offsets"] == [%{"start" => 0, "length" => 10}]
    end

    test "returns 100 with truncated for a broad term", %{conn: conn, ana: ana, thread: thread} do
      bulk(thread, ana, "cronograma", 101)

      body = conn |> search(thread.id, "cronograma") |> json_response(200)

      assert body["truncated"] == true
      assert length(body["messages"]) == 100
      assert body["total_matches"] == 100
    end

    test "matches familia against Família", %{conn: conn, ana: ana, thread: thread} do
      write(thread, ana, "Reunião da Família", ago(10))

      body = conn |> search(thread.id, "familia") |> json_response(200)

      assert [hit] = body["messages"]
      assert hit["body"] == "Reunião da Família"
    end

    test "rejects a query shorter than 2 characters with 422 and no scan", %{
      conn: conn,
      thread: thread
    } do
      body = conn |> search(thread.id, "a") |> json_response(422)

      assert body["errors"]["code"] == "validation_error"
      assert Map.has_key?(body["errors"]["fields"], "q")
      refute Map.has_key?(body, "messages")
    end

    test "returns 404 to a non-participant with no message content", %{
      ana: ana,
      outsider: outsider,
      thread: thread
    } do
      write(thread, ana, "cronograma secreto", ago(10))

      body =
        authenticate(json_conn(), outsider)
        |> search(thread.id, "cronograma")
        |> json_response(404)

      assert body["errors"]["code"] == "not_found"
      refute Map.has_key?(body, "messages")
    end

    test "returns 200 with an empty array for no matches", %{conn: conn, ana: ana, thread: thread} do
      write(thread, ana, "nada relevante", ago(10))

      body = conn |> search(thread.id, "cronograma") |> json_response(200)

      assert body["messages"] == []
      assert body["total_matches"] == 0
    end

    test "returns 400 for a malformed conversation id", %{conn: conn} do
      body = conn |> search("nope", "cronograma") |> json_response(400)
      assert body["errors"]["code"] == "invalid_id"
    end

    test "requires authentication", %{thread: thread} do
      body = json_conn() |> search(thread.id, "cronograma") |> json_response(401)
      assert body["errors"]["code"] == "unauthenticated"
    end
  end

  describe "cross-feature integration" do
    test "a persisted message is findable by its body and its id loads a history page containing it",
         %{conn: conn, ana: ana, thread: thread} do
      {:ok, persisted} =
        Messages.create_message(ana, thread.id, %{body: "revisão do cronograma trimestral"})

      hit =
        conn
        |> search(thread.id, "cronograma")
        |> json_response(200)
        |> Map.fetch!("messages")
        |> hd()

      assert hit["id"] == persisted.id

      history =
        conn
        |> get(~p"/api/conversations/#{thread.id}/messages")
        |> json_response(200)
        |> Map.fetch!("messages")

      assert Enum.any?(history, &(&1["id"] == persisted.id))
    end
  end
end
