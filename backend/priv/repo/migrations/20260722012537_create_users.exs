defmodule Api.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  # `citext` gives case-insensitive uniqueness and case-insensitive lookup from
  # the same column, so no later query needs a `lower()` wrapper that would
  # bypass the index. The extension is already enabled by the base migration.
  def change do
    create table(:users, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :username, :citext, null: false
      add :name, :string, size: 60, null: false
      add :hashed_password, :string, null: false
      add :last_seen_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:username])
  end
end
