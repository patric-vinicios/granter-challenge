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
  Probes database connectivity with a `SELECT 1`.

  ## Parameters

    * `repo` — the repo to probe, defaulting to `Api.Repo`; a test can pass an
      unreachable one

  Returns `:ok` when the database answers and `{:error, reason}` when it does
  not, including on timeout or a dropped connection.

  ## Examples

      iex> Api.Health.check()
      :ok
  """
  @spec check(Ecto.Repo.t()) :: :ok | {:error, term()}
  def check(repo \\ Repo) do
    case SQL.query(repo, "SELECT 1", [], timeout: @timeout) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, reason}
  end
end
