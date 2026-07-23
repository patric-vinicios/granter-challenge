defmodule Api.DataCase do
  @moduledoc """
  Case template for context tests.

  Every test runs inside an Ecto SQL sandbox transaction that is rolled back
  on exit, so a test never observes another test's writes and the suite can
  run with `async: true` against PostgreSQL.
  """

  use ExUnit.CaseTemplate
  use Boundary, top_level?: true, check: [in: false, out: false]

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      alias Api.Repo

      import Api.DataCase
      import Api.Factory
      import Ecto
      import Ecto.Changeset
      import Ecto.Query
    end
  end

  setup tags do
    {:ok, sandbox_owner: Api.DataCase.setup_sandbox(tags)}
  end

  @doc """
  Checks out a sandbox connection, shared with other processes unless the test
  is async. Shared by `ApiWeb.ConnCase` and `ApiWeb.ChannelCase` so all three
  case templates isolate the database the same way.

  Returns the owner pid, which a test can stop early to simulate losing the
  database.
  """
  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(Api.Repo, shared: not tags[:async])

    on_exit(fn ->
      # Tolerant of a test that stopped the owner to simulate a dead database.
      try do
        Sandbox.stop_owner(pid)
      catch
        :exit, _reason -> :ok
      end
    end)

    pid
  end

  @doc """
  Runs `fun` and returns how many database queries it issued.

  A telemetry handler on the repo's query event counts, and is detached in an
  `after` clause so an exception in `fun` never leaks it. Only queries emitted
  from the calling process are counted: `Phoenix.ConnTest` dispatches a request
  in the test process, so this is exact at both the context and the endpoint
  level and never counts a concurrent async test's queries.
  """
  def count_queries(fun) when is_function(fun, 0) do
    test_pid = self()
    counter = :counters.new(1, [])
    handler_id = {:count_queries, make_ref()}

    :telemetry.attach(
      handler_id,
      [:api, :repo, :query],
      fn _event, _measurements, _metadata, _config ->
        if self() == test_pid, do: :counters.add(counter, 1, 1)
      end,
      nil
    )

    try do
      fun.()
      :counters.get(counter, 1)
    after
      :telemetry.detach(handler_id)
    end
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
