defmodule Api.Release do
  @moduledoc """
  Migration entry points for a built release, where Mix is unavailable.

  `mix ecto.migrate` cannot run inside a release: Mix and the tasks it provides
  are not part of the image. These functions load the application without
  starting its supervision tree, start each repo on its own, and drive
  `Ecto.Migrator` directly — which is what `bin/migrate` calls before the
  endpoint comes up.

  Seeding has no counterpart here on purpose. `Api.Seeds` refuses to run when
  the compiled environment is `:prod`, so a deployed database is only ever
  populated through the API itself.
  """

  @app :api

  @doc """
  Runs every pending migration for each configured repo.

  Returns `:ok`, and raises when a migration fails so the caller — a release
  phase or `bin/server` — exits non-zero before the endpoint starts.

  ## Examples

      iex> Api.Release.migrate()
      :ok
  """
  @spec migrate() :: :ok
  def migrate do
    load_app()

    Enum.each(repos(), fn repo ->
      {:ok, _result, _apps} =
        Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end)
  end

  @doc """
  Reverts a repo's migrations down to the given version, inclusive.

  ## Parameters

    * `repo` — the repo to roll back
    * `version` — the timestamp to stop at, which is itself reverted along with
      every migration applied after it

  Returns `:ok`.

  ## Examples

      iex> Api.Release.rollback(Api.Repo, 20_260_724_133_326)
      :ok
  """
  @spec rollback(Ecto.Repo.t(), non_neg_integer()) :: :ok
  def rollback(repo, version) do
    load_app()

    {:ok, _result, _apps} =
      Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))

    :ok
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
