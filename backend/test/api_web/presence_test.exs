defmodule ApiWeb.PresenceTest do
  # The tracker and its leave-driven write run in their own processes, so the
  # shared sandbox connection that non-async setup provides is required for the
  # write to land where the test can read it.
  use ApiWeb.ChannelCase, async: false

  alias Api.Accounts
  alias Api.Repo
  alias ApiWeb.Presence
  alias Phoenix.Socket.Broadcast

  # A bare tracked meta on a user's topic, standing in for one open socket
  # without the channel lifecycle a later stage adds. The process lives until
  # told to stop, so a test controls exactly when the final leave fires.
  defp open_socket(user_id) do
    test = self()

    pid =
      spawn(fn ->
        {:ok, _ref} =
          Presence.track(self(), "user:#{user_id}", user_id, %{online_at: DateTime.utc_now()})

        send(test, :tracked)

        receive do
          :stop -> :ok
        end
      end)

    assert_receive :tracked
    sync_presence("user:#{user_id}")
    pid
  end

  defp close_socket(pid, user_id) do
    :ok = Phoenix.PubSub.subscribe(Api.PubSub, "user:#{user_id}")
    ref = Process.monitor(pid)
    send(pid, :stop)

    assert_receive {:DOWN, ^ref, :process, _pid, _reason}

    assert_receive %Broadcast{event: "presence_diff", payload: %{leaves: leaves}}
                   when map_size(leaves) > 0

    sync_presence("user:#{user_id}")
    :ok
  end

  test "tracks a user as online while a socket is open" do
    user = insert(:user)
    pid = open_socket(user.id)

    assert Presence.online?(user.id)
    assert %{metas: [%{online_at: %DateTime{}}]} = Presence.list("user:#{user.id}")[user.id]

    :ok = close_socket(pid, user.id)
  end

  test "a never-connected user is offline and has no last_seen_at" do
    user = insert(:user)

    refute Presence.online?(user.id)
    assert Repo.reload(user).last_seen_at == nil
  end

  test "closing one of two sockets keeps the user online and writes nothing" do
    user = insert(:user)
    first = open_socket(user.id)
    second = open_socket(user.id)

    :ok = close_socket(first, user.id)

    assert Presence.online?(user.id)
    assert Repo.reload(user).last_seen_at == nil

    :ok = close_socket(second, user.id)
  end

  test "closing the last socket marks the user offline and writes last_seen_at" do
    user = insert(:user)
    first = open_socket(user.id)
    second = open_socket(user.id)

    :ok = close_socket(first, user.id)
    :ok = close_socket(second, user.id)

    refute Presence.online?(user.id)
    assert %DateTime{} = Repo.reload(user).last_seen_at
  end

  test "last_seen_at is written within a second of the disconnect" do
    user = insert(:user)
    pid = open_socket(user.id)

    before = DateTime.utc_now()
    :ok = close_socket(pid, user.id)
    written = Repo.reload(user).last_seen_at

    assert DateTime.compare(written, before) in [:gt, :eq]
    assert DateTime.diff(DateTime.utc_now(), written) <= 1
  end

  describe "cross-feature: last_seen_at is the value presence writes and reads" do
    test "the leave-written value is exactly what Accounts reads back" do
      user = insert(:user)
      pid = open_socket(user.id)
      :ok = close_socket(pid, user.id)

      written = Repo.reload(user).last_seen_at
      assert Accounts.get_user(user.id).last_seen_at == written
    end
  end

  describe "cross-feature: a real socket connection drives presence" do
    test "a joined socket is online; closing it goes offline and writes last_seen_at" do
      user = insert(:user)
      socket = track_user(user)

      assert Presence.online?(user.id)
      assert Repo.reload(user).last_seen_at == nil

      :ok = close_and_await_leave(socket, user.id)

      refute Presence.online?(user.id)
      assert %DateTime{} = Repo.reload(user).last_seen_at
    end
  end
end
