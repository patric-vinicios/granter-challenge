defmodule Api.Health do
  @moduledoc """
  Database connectivity probe behind `GET /api/health`.

  The check is a real `SELECT 1` round trip rather than an inspection of the
  pool state, because a pool can hold connections that the server has already
  closed. A short timeout keeps the probe itself from hanging when the
  database is unreachable but the TCP connection is not refused outright.
  """

  alias Api.Repo
  alias Ecto.Adapters.SQL

  @timeout :timer.seconds(2)

  @doc """
  Returns `:ok` when the database answers, `{:error, reason}` when it does not.

  An unreachable database is an expected operating condition for a health
  endpoint, so every failure mode -- a connection error, a Postgres error, or
  the repo process not running at all -- is returned as a value instead of
  being raised at the controller.
  """
  def check do
    case SQL.query(Repo, "SELECT 1", [], timeout: @timeout) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    error in [DBConnection.ConnectionError, Postgrex.Error, ArgumentError] -> {:error, error}
  catch
    :exit, reason -> {:error, reason}
  end
end
