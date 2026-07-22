defmodule Api.Repo.Migrations.EnableExtensions do
  use Ecto.Migration

  # Enabling an extension is a privileged operation. Doing it once at the base
  # of the migration chain means no later feature needs superuser rights
  # mid-stream: case-insensitive unique columns (citext) and accent-insensitive
  # search (unaccent) simply use them.
  #
  # Written as up/down rather than change/0 because `execute` is not
  # reversible on its own, and a rollback on a clean database has to succeed.
  def up do
    execute "CREATE EXTENSION IF NOT EXISTS citext"
    execute "CREATE EXTENSION IF NOT EXISTS unaccent"
  end

  def down do
    execute "DROP EXTENSION IF EXISTS unaccent"
    execute "DROP EXTENSION IF EXISTS citext"
  end
end
