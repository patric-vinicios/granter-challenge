defmodule ApiWeb.RateLimiterTest do
  # No database and a table keyed on unique per-test ids, so the suite runs
  # concurrently against the one limiter the application already started.
  use ExUnit.Case, async: true

  alias ApiWeb.RateLimiter

  @limit 20

  # A fresh id per test, so two tests never share a window bucket.
  defp fresh_id, do: Ecto.UUID.generate()

  test "allows the configured number of hits in one window" do
    id = fresh_id()
    assert Enum.all?(1..@limit, fn _ -> RateLimiter.hit(id) == :ok end)
  end

  test "rejects the hit past the limit" do
    id = fresh_id()
    for _ <- 1..@limit, do: :ok = RateLimiter.hit(id)

    assert {:error, ms} = RateLimiter.hit(id)
    assert ms in 1..10_000
  end

  test "keeps rejecting for the rest of the window" do
    id = fresh_id()
    for _ <- 1..@limit, do: :ok = RateLimiter.hit(id)
    assert {:error, _} = RateLimiter.hit(id)

    assert {:error, _} = RateLimiter.hit(id)
    assert {:error, _} = RateLimiter.hit(id)
  end

  test "tracks users independently" do
    a = fresh_id()
    b = fresh_id()
    for _ <- 1..@limit, do: :ok = RateLimiter.hit(a)

    assert {:error, _} = RateLimiter.hit(a)
    assert :ok = RateLimiter.hit(b)
  end

  test "creates the bucket on first use" do
    assert :ok = RateLimiter.hit(fresh_id())
  end

  test "counts across conversations for one user" do
    id = fresh_id()
    # The caller's origin is irrelevant: every hit is attributed to the id, so
    # the ceiling is 20 total rather than 20 per conversation.
    assert Enum.all?(1..@limit, fn _ -> RateLimiter.hit(id) == :ok end)
    assert {:error, _} = RateLimiter.hit(id)
  end

  test "sweeps stale buckets while leaving the current one" do
    id = fresh_id()
    :ok = RateLimiter.hit(id)
    current = div(System.system_time(:millisecond), 10_000)
    stale_key = {id, current - 5}
    :ets.insert(RateLimiter, {stale_key, 3})

    pid = Process.whereis(RateLimiter)
    send(pid, :sweep)
    # Force the sweep to be handled before we inspect the table.
    _ = :sys.get_state(pid)

    assert :ets.lookup(RateLimiter, stale_key) == []
    assert [{{^id, ^current}, 1}] = :ets.lookup(RateLimiter, {id, current})
  end
end
