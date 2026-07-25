defmodule Api.TokenRevocation do
  @moduledoc """
  The set of logged-out token ids, held in ETS until each would have expired.

  A JWT is stateless, so logout cannot invalidate it at the source; instead the
  token's `jti` is recorded here until its `exp`, and both the HTTP pipeline and
  the socket reject any token whose `jti` is present. Entries are keyed by `jti`
  with the token's own expiry, so a revocation costs exactly the token's
  remaining lifetime and never outlives it.

  State is node-local and lost on restart, which is the safe direction to fail:
  a restart forgets revocations, but every forgotten token was already seconds
  from expiring on its own.
  """

  use GenServer

  @table __MODULE__
  @sweep_ms 60_000

  @doc """
  Records `jti` as revoked until `exp`.

  ## Parameters

    * `jti` — the token's `jti` claim
    * `exp` — the token's expiry, in unix seconds

  A non-binary `jti` or non-integer `exp` is ignored. Always returns `:ok`.

  ## Examples

      iex> Api.TokenRevocation.revoke("2b8c...", 1_800_000_000)
      :ok
  """
  @spec revoke(term(), term()) :: :ok
  def revoke(jti, exp) when is_binary(jti) and is_integer(exp) do
    :ets.insert(@table, {jti, exp})
    :ok
  end

  def revoke(_jti, _exp), do: :ok

  @doc """
  Whether `jti` names a revoked token that has not yet expired.

  ## Parameters

    * `jti` — the token's `jti` claim

  ## Examples

      iex> Api.TokenRevocation.revoked?("2b8c...")
      true

      iex> Api.TokenRevocation.revoked?("never-seen")
      false
  """
  @spec revoked?(term()) :: boolean()
  def revoked?(jti) when is_binary(jti) do
    case :ets.lookup(@table, jti) do
      [{^jti, exp}] -> exp > System.system_time(:second)
      [] -> false
    end
  end

  def revoked?(_jti), do: false

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl GenServer
  def init(_opts) do
    :ets.new(@table, [:set, :named_table, :public, read_concurrency: true])
    schedule_sweep()
    {:ok, %{}}
  end

  @impl GenServer
  def handle_info(:sweep, state) do
    now = System.system_time(:second)
    :ets.select_delete(@table, [{{:_, :"$1"}, [{:"=<", :"$1", now}], [true]}])
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_ms)
end
