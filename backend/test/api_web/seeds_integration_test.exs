defmodule ApiWeb.SeedsIntegrationTest do
  use ApiWeb.ConnCase, async: false

  import ExUnit.CaptureIO

  alias Api.Accounts
  alias Api.Accounts.Guardian
  alias Api.Conversations.Conversation
  alias Api.Repo
  alias Api.Seeds
  alias Api.Seeds.Dataset

  setup do
    capture_io(fn -> Seeds.run() end)
    :ok
  end

  defp authenticate(conn, user) do
    {:ok, token, _expires_at} = Guardian.issue_token(user)

    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  defp normalize(name) do
    name
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
  end

  defp private_between(a, b) do
    key = [a.id, b.id] |> Enum.sort() |> Enum.join(":")

    Repo.get_by!(Conversation, participant_key: key, type: :private)
  end

  test "seeded users log in through the auth endpoint and receive a working token" do
    for %{username: username} <- Dataset.all().users do
      login =
        json_conn()
        |> post(~p"/api/auth/login", %{username: username, password: "senha123"})
        |> json_response(200)

      assert %{"token" => token} = login

      me =
        json_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/auth/me")
        |> json_response(200)

      assert me["user"]["username"] == username
    end
  end

  test "seeded contact lists are returned by the contacts endpoint" do
    for %{username: username} <- Dataset.all().users do
      user = Accounts.get_user_by_username(username)

      contacts =
        json_conn()
        |> authenticate(user)
        |> get(~p"/api/contacts")
        |> json_response(200)
        |> Map.fetch!("contacts")

      assert Enum.count(contacts) == 6
      refute Enum.any?(contacts, &(&1["user"]["username"] == username))

      names = Enum.map(contacts, &normalize(&1["user"]["name"]))
      assert names == Enum.sort(names)
    end
  end

  test "seeded groups appear with the correct creator and member list" do
    demo = Accounts.get_user_by_username("demo")

    for group <- Enum.filter(Dataset.all().conversations, &(&1.kind == :group)) do
      conversation = Repo.get_by!(Conversation, name: group.name, type: :group)
      member = Accounts.get_user_by_username(hd(group.members))

      data =
        json_conn()
        |> authenticate(member)
        |> get(~p"/api/conversations/#{conversation.id}")
        |> json_response(200)
        |> Map.fetch!("conversation")

      assert data["name"] == group.name
      assert data["creator_id"] == demo.id
      assert data["member_count"] == length(group.members)

      member_usernames = data["members"] |> Enum.map(& &1["username"]) |> Enum.sort()
      assert member_usernames == Enum.sort(group.members)
    end
  end

  test "seeded messages are returned in chronological order with their backdated timestamps" do
    demo = Accounts.get_user_by_username("demo")
    ana = Accounts.get_user_by_username("anabeatriz")
    conversation = private_between(demo, ana)

    body =
      json_conn()
      |> authenticate(demo)
      |> get(~p"/api/conversations/#{conversation.id}/messages")
      |> json_response(200)

    messages = body["messages"]
    assert Enum.count(messages) == 14

    timestamps = Enum.map(messages, & &1["inserted_at"])
    assert timestamps == Enum.sort(timestamps)

    now = DateTime.utc_now()

    for timestamp <- timestamps do
      {:ok, inserted_at, _offset} = DateTime.from_iso8601(timestamp)
      assert DateTime.compare(inserted_at, now) == :lt
    end

    page1 =
      json_conn()
      |> authenticate(demo)
      |> get(~p"/api/conversations/#{conversation.id}/messages", %{limit: 10})
      |> json_response(200)

    assert Enum.count(page1["messages"]) == 10
    assert page1["has_more"]

    page2 =
      json_conn()
      |> authenticate(demo)
      |> get(~p"/api/conversations/#{conversation.id}/messages", %{
        limit: 10,
        before: page1["next_cursor"]
      })
      |> json_response(200)

    assert Enum.count(page2["messages"]) == 4
    refute page2["has_more"]
  end
end
