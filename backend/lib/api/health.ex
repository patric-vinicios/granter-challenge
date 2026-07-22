defmodule Api.Health do
  @moduledoc """
  Database connectivity probe behind `GET /api/health`.

  The check is a real `SELECT 1` round trip rather than an inspection of the
  pool state, because a pool can hold connections the server has already
  closed.
  """

  alias Api.Repo
  alias Ecto.Adapters.SQL

  @timeout :timer.seconds(2)

  @doc """
  Returns `:ok` when the database answers, `{:error, reason}` when it does not.

  Takes the repo to probe so a test can point it at an unreachable database;
  callers use `check/0`.
  """
  def check(repo \\ Repo) do
    case SQL.query(repo, "SELECT 1", [], timeout: @timeout) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    # A probe that raises would turn an unavailable database into a bare 500.
    error -> {:error, error}
  catch
    :exit, reason -> {:error, reason}
  end
end
