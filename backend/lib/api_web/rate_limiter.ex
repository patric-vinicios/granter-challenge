defmodule ApiWeb.RateLimiter do
  @moduledoc """
  A per-user ceiling on message-send rate, across every conversation a socket
  holds at once.

  The count lives in a public ETS table, not in `socket.assigns`: assigns are
  per channel process, so a limit tracked there would grant a fresh allowance
  for each conversation a user opens — exactly what a spammer does. Keyed on the
  user, the ceiling holds no matter how many topics one socket has joined.

  `hit/1` runs in the calling channel process with a single
  `:ets.update_counter/4`, so the GenServer is never in the send path — it only
  owns the table and sweeps windows that have rolled past. A fixed window is
  used over a sliding log because its worst case, a burst straddling a boundary,
  is not a threat model for a chat.

  State is node-local and lost on restart, the safe direction for an abuse
  guard: a restart resets every window rather than locking anyone out.
  """

  use GenServer

  @table __MODULE__
  @limit 20
  @window_ms 10_000
  @sweep_ms 30_000

  @doc """
  Records one send for `user_id` and answers whether it is allowed.

  ## Parameters

    * `user_id` — the sending user's id, as a string

  Returns `:ok` for the twentieth send or earlier in the current window, and
  `{:error, retry_after_ms}` past it, where `retry_after_ms` is the time left
  before the window rolls, always in `1..#{@window_ms}`. The counter is created
  on first use in the same atomic operation that increments it.

  ## Examples

      iex> ApiWeb.RateLimiter.hit(user.id)
      :ok
  """
  @spec hit(String.t()) :: :ok | {:error, pos_integer()}
  def hit(user_id) do
    now = System.system_time(:millisecond)
    window = div(now, @window_ms)
    key = {user_id, window}
    count = :ets.update_counter(@table, key, {2, 1}, {key, 0})

    if count <= @limit do
      :ok
    else
      {:error, (window + 1) * @window_ms - now}
    end
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl GenServer
  def init(_opts) do
    :ets.new(@table, [
      :set,
      :named_table,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    schedule_sweep()
    {:ok, %{}}
  end

  @impl GenServer
  def handle_info(:sweep, state) do
    sweep()
    schedule_sweep()
    {:noreply, state}
  end

  # Deletes every bucket whose window has already rolled. A stale bucket is
  # unreachable by the current key anyway, so this only bounds the table at the
  # active-user count and correctness never depends on it running.
  defp sweep do
    current = div(System.system_time(:millisecond), @window_ms)
    :ets.select_delete(@table, [{{{:_, :"$1"}, :_}, [{:<, :"$1", current}], [true]}])
  end

  defp schedule_sweep do
    Process.send_after(self(), :sweep, @sweep_ms)
  end
end
