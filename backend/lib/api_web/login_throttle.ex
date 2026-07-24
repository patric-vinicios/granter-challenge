defmodule ApiWeb.LoginThrottle do
  @moduledoc """
  A ceiling on failed login attempts, per client IP and per username, over a
  fixed window.

  Only failures count, so a legitimate user is never throttled by their own
  successful logins, while a password-guessing burst against one account or from
  one address is stopped. Counts live in a public ETS table keyed by the window,
  so `check/2` is a lock-free read and the GenServer only owns the table and
  sweeps stale windows.

  Limits and window are read from config at call time, so the suite can raise
  them out of the way and a single test can lower them.
  """

  use GenServer

  @table __MODULE__

  @doc """
  Whether a login attempt from `ip` for `username` is currently allowed.

  Returns `:ok`, or `{:error, retry_after_seconds}` once either the IP or the
  username has failed too many times in the window.
  """
  @spec check(term(), term()) :: :ok | {:error, pos_integer()}
  def check(ip, username) do
    now = System.system_time(:millisecond)
    window = div(now, window_ms())

    cond do
      peek({:ip, ip, window}) >= ip_limit() -> {:error, retry_after(window, now)}
      peek({:user, username, window}) >= user_limit() -> {:error, retry_after(window, now)}
      true -> :ok
    end
  end

  @doc "Records one failed attempt against both `ip` and `username`."
  @spec fail(term(), term()) :: :ok
  def fail(ip, username) do
    window = div(System.system_time(:millisecond), window_ms())
    bump({:ip, ip, window})
    bump({:user, username, window})
    :ok
  end

  defp peek(key) do
    case :ets.lookup(@table, key) do
      [{^key, count}] -> count
      [] -> 0
    end
  end

  defp bump(key), do: :ets.update_counter(@table, key, {2, 1}, {key, 0})

  defp retry_after(window, now), do: div((window + 1) * window_ms() - now, 1000) + 1

  defp config(key, default), do: Keyword.get(env(), key, default)
  defp env, do: Application.get_env(:api, __MODULE__, [])
  defp ip_limit, do: config(:ip_limit, 10)
  defp user_limit, do: config(:user_limit, 5)
  defp window_ms, do: config(:window_ms, 60_000)

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
      write_concurrency: true,
      read_concurrency: true
    ])

    schedule_sweep()
    {:ok, %{}}
  end

  @impl GenServer
  def handle_info(:sweep, state) do
    current = div(System.system_time(:millisecond), window_ms())
    :ets.select_delete(@table, [{{{:_, :_, :"$1"}, :_}, [{:<, :"$1", current}], [true]}])
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, 60_000)
end
