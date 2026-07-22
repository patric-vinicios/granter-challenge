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

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Api.DataCase
    end
  end

  setup tags do
    Api.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Checks out a sandbox connection, shared with other processes unless the test
  is async. Shared by `ApiWeb.ConnCase` and `ApiWeb.ChannelCase` so all three
  case templates isolate the database the same way.
  """
  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(Api.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
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
