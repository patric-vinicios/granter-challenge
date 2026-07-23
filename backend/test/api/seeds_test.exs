defmodule Api.SeedsTest do
  use Api.DataCase, async: false

  import ExUnit.CaptureIO

  alias Api.Accounts
  alias Api.Accounts.User
  alias Api.Contacts
  alias Api.Contacts.Contact
  alias Api.Conversations.Conversation
  alias Api.Conversations.Participant
  alias Api.Messages.Message
  alias Api.Seeds
  alias Api.Seeds.Dataset

  alias Ecto.Adapters.SQL.Sandbox

  defp seed, do: with_io(fn -> Seeds.run() end) |> elem(0)
  defp seed(dataset), do: with_io(fn -> Seeds.run(dataset) end) |> elem(0)

  defp count(schema), do: Repo.aggregate(schema, :count)

  defp unread_for(%User{} = user) do
    from(p in Participant,
      where: p.user_id == ^user.id,
      left_join: m in Message,
      on:
        m.conversation_id == p.conversation_id and m.sender_id != ^user.id and
          m.inserted_at > p.last_read_at,
      group_by: p.id,
      select: count(m.id)
    )
    |> Repo.all()
  end

  test "seeds the full dataset into an empty database" do
    assert {:ok, %{users: 7, conversations: 6, messages: 62}} = seed()

    assert count(User) == 7
    assert count(Conversation) == 6
    assert count(Message) == 62
    assert Repo.aggregate(from(c in Conversation, where: c.type == :private), :count) == 4
    assert Repo.aggregate(from(c in Conversation, where: c.type == :group), :count) == 2
  end

  test "every seeded user authenticates with the documented password" do
    seed()

    for %{username: username} <- Dataset.all().users do
      assert {:ok, %User{}} = Accounts.authenticate(username, "senha123")
    end
  end

  test "seeds the full contact mesh" do
    seed()

    assert count(Contact) == 42

    users = Enum.map(Dataset.all().users, &Accounts.get_user_by_username(&1.username))

    for owner <- users, target <- users, owner.id != target.id do
      assert Contacts.contact?(owner, target)
    end
  end

  test "backdates messages across today, yesterday and the previous week" do
    seed()

    now = DateTime.utc_now()
    today = Date.utc_today()
    inserted_ats = Repo.all(from(m in Message, select: m.inserted_at))

    assert Enum.all?(inserted_ats, &(DateTime.compare(&1, now) == :lt))

    day_diffs =
      inserted_ats
      |> Enum.map(&Date.diff(today, DateTime.to_date(&1)))
      |> Enum.uniq()

    assert Enum.min(day_diffs) <= 1
    assert Enum.any?(day_diffs, &(&1 in [1, 2]))
    assert Enum.max(day_diffs) >= 7
    assert Enum.count(day_diffs) >= 3
  end

  test "leaves exactly two conversations unread for the demo account" do
    seed()

    demo = Accounts.get_user_by_username("demo")

    assert Enum.sort(unread_for(demo)) == [0, 0, 0, 0, 2, 3]
  end

  test "marks every other participant fully read" do
    seed()

    demo = Accounts.get_user_by_username("demo")

    others =
      from(p in Participant, where: p.user_id != ^demo.id, select: p.user_id, distinct: true)
      |> Repo.all()
      |> Enum.map(&Accounts.get_user/1)

    for user <- others do
      assert Enum.all?(unread_for(user), &(&1 == 0))
    end
  end

  test "is idempotent" do
    assert {:ok, %{users: 7}} = seed()

    before = {count(User), count(Conversation), count(Message), count(Contact)}

    assert {:ok, :skipped} = seed()

    assert {count(User), count(Conversation), count(Message), count(Contact)} == before
  end

  test "reuses a pre-existing seeded username instead of failing" do
    {:ok, ana} =
      Accounts.register_user(%{username: "anabeatriz", name: "Ana Beatriz", password: "senha123"})

    assert {:ok, %{users: 7}} = seed()

    assert count(User) == 7
    assert Accounts.get_user_by_username("anabeatriz").id == ana.id
    assert Repo.exists?(from(p in Participant, where: p.user_id == ^ana.id))
  end

  test "seeded bodies satisfy the runtime message validations" do
    seed()

    bodies = Repo.all(from(m in Message, select: m.body))

    assert Enum.count(bodies) == 62

    for body <- bodies do
      assert String.trim(body) != ""
      assert String.length(body) <= 4000
    end
  end

  test "refuses to run in the prod environment" do
    original = Application.fetch_env!(:api, :env)
    Application.put_env(:api, :env, :prod)
    on_exit(fn -> Application.put_env(:api, :env, original) end)

    assert {:error, :prod_refused} = seed()
    assert count(User) == 0
  end

  test "rolls back the whole run when a record fails validation" do
    on_exit(&truncate_all/0)

    Sandbox.unboxed_run(Repo, fn ->
      assert {:error, {_label, _reason}} = seed(invalid_dataset())

      assert count(User) == 0
      assert count(Conversation) == 0
      assert count(Message) == 0
    end)
  end

  test "raises an instruction when the schema is missing" do
    Sandbox.unboxed_run(Repo, fn ->
      Repo.query!("ALTER TABLE users RENAME TO users_renamed")

      try do
        assert_raise RuntimeError, ~r/mix ecto\.migrate/, fn ->
          with_io(fn -> Seeds.run() end)
        end
      after
        Repo.query!("ALTER TABLE users_renamed RENAME TO users")
      end
    end)
  end

  defp invalid_dataset do
    %{
      password: "senha123",
      primary: "demo",
      users: [
        %{username: "demo", name: "Usuário Demo"},
        %{username: "anabeatriz", name: "Ana Beatriz"}
      ],
      conversations: [
        %{kind: :private, with: "anabeatriz", unread: 0, messages: [{"demo", "   ", {0, 5}}]}
      ]
    }
  end

  defp truncate_all do
    Sandbox.unboxed_run(Repo, fn ->
      Repo.delete_all(Message)
      Repo.delete_all(Participant)
      Repo.delete_all(Contact)
      Repo.delete_all(Conversation)
      Repo.delete_all(User)
    end)
  end
end
