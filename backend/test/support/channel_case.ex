defmodule ApiWeb.ChannelCase do
  @moduledoc """
  Case template for socket and channel tests.

  Gives socket and channel tests the same sandbox checkout and factory
  imports the HTTP tests get, so real-time tests do not grow their own ad-hoc
  setup, plus `connect_socket/1` so none of them restates the handshake.
  """

  use ExUnit.CaseTemplate
  use Boundary, top_level?: true, check: [in: false, out: false]

  import ExUnit.Assertions

  alias Api.Accounts.Guardian
  alias ApiWeb.Presence
  alias ApiWeb.UserChannel
  alias Phoenix.ChannelTest
  alias Phoenix.Socket.Broadcast
  alias Phoenix.Tracker.Shard

  @endpoint ApiWeb.Endpoint

  using do
    quote do
      @endpoint ApiWeb.Endpoint

      import Api.Factory
      import Phoenix.ChannelTest

      import ApiWeb.ChannelCase,
        only: [connect_socket: 1, track_user: 1, close_and_await_leave: 2, sync_presence: 1]
    end
  end

  setup tags do
    Api.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  An authenticated socket for `user`, issued the same token the HTTP pipeline
  verifies and run through `UserSocket.connect/3`, so a channel test names the
  handshake once by the user it belongs to.
  """
  def connect_socket(user) do
    {:ok, token, _expires_at} = Guardian.issue_token(user)

    {:ok, socket} =
      ChannelTest.__connect__(@endpoint, ApiWeb.UserSocket, %{"token" => token}, [])

    socket
  end

  @doc """
  Joins `user`'s personal topic and returns the tracked socket.

  `:sys.get_state/1` flushes the channel's mailbox so its `after_join` — where
  the tracking happens — has run before the caller reads presence, so a test
  never sleeps to observe the track.
  """
  def track_user(user) do
    {:ok, _reply, socket} =
      ChannelTest.subscribe_and_join(connect_socket(user), UserChannel, "user:#{user.id}")

    _ = :sys.get_state(socket.channel_pid)
    socket
  end

  @doc """
  Closes a tracked `socket` and blocks until its leave has been fully processed.

  Subscribes to the user's presence topic first, closes the socket, awaits the
  channel's exit and the `presence_diff` its leave broadcasts, then
  `sync_presence/1` waits out the tracker shard so the leave-driven
  `last_seen_at` write — which runs after the broadcast — is committed and
  visible before the caller asserts on it.
  """
  def close_and_await_leave(socket, user_id) do
    :ok = Phoenix.PubSub.subscribe(Api.PubSub, "user:#{user_id}")
    Process.unlink(socket.channel_pid)
    ref = Process.monitor(socket.channel_pid)
    ChannelTest.close(socket)

    assert_receive {:DOWN, ^ref, :process, _pid, _reason}
    assert_receive %Broadcast{event: "presence_diff", topic: "user:" <> _}

    sync_presence("user:#{user_id}")
    :ok
  end

  @doc """
  Blocks until the presence tracker shard for `topic` has drained its mailbox.

  The leave-driven `last_seen_at` write runs inside the shard's diff handling
  after the diff is broadcast, so a synchronous call to the shard guarantees
  that handling — the write included — has finished.
  """
  def sync_presence(topic) do
    [{:pool_size, size}] = :ets.lookup(Presence, :pool_size)
    _ = :sys.get_state(Shard.name_for_topic(Presence, topic, size))
    :ok
  end
end
