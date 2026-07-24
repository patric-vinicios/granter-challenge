defmodule Api.Repo.Migrations.CreateNameSearchIndexes do
  use Ecto.Migration

  # Searching the conversation list means matching a substring anywhere inside a
  # display name — `mari` has to find `Mariana`. A btree index only answers
  # prefixes, so the leading wildcard leaves it unusable and every candidate row
  # has to be read. `pg_trgm` indexes the three-character shingles of a string
  # instead, which is the shape a GIN index can answer `%mari%` from.
  #
  # The expression indexed is `immutable_unaccent(...)` and not `unaccent(...)`,
  # because an index expression must be IMMUTABLE and `unaccent/1` is only
  # STABLE — it resolves its dictionary through search_path at call time.
  # Pinning the dictionary with the two-argument form makes the result depend on
  # nothing but the input, the same reasoning the message search vector used
  # when it pinned a named text-search configuration.
  #
  # up/down rather than change/0: `execute` is not reversible on its own, and a
  # rollback on a clean database has to succeed.
  def up do
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm"

    execute """
    CREATE FUNCTION immutable_unaccent(text) RETURNS text
      LANGUAGE sql IMMUTABLE PARALLEL SAFE STRICT AS
      $$ SELECT public.unaccent('public.unaccent'::regdictionary, $1) $$
    """

    execute """
    CREATE INDEX users_name_trgm_index
      ON users USING GIN (immutable_unaccent(name) gin_trgm_ops)
    """

    execute """
    CREATE INDEX users_username_trgm_index
      ON users USING GIN (immutable_unaccent(username::text) gin_trgm_ops)
    """

    execute """
    CREATE INDEX conversations_name_trgm_index
      ON conversations USING GIN (immutable_unaccent(name) gin_trgm_ops)
    """
  end

  def down do
    execute "DROP INDEX IF EXISTS conversations_name_trgm_index"
    execute "DROP INDEX IF EXISTS users_username_trgm_index"
    execute "DROP INDEX IF EXISTS users_name_trgm_index"
    execute "DROP FUNCTION IF EXISTS immutable_unaccent(text)"
  end
end
