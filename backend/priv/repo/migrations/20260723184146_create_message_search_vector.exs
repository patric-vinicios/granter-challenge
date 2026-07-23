defmodule Api.Repo.Migrations.CreateMessageSearchVector do
  use Ecto.Migration

  # A named text-search configuration rather than the stock `portuguese` one,
  # because the stock config keeps diacritics and `familia` must match
  # `Família`. Copying `portuguese` and prepending `unaccent` to its word
  # mappings strips the accents while keeping the stemmer, and the result stays
  # IMMUTABLE under a constant regconfig — which the generated column requires,
  # and which `unaccent(body)` inlined into the column could not offer, since
  # `unaccent/1` is only STABLE.
  #
  # up/down rather than change/0: `execute` on the configuration is not
  # reversible on its own, and a rollback on a clean database has to succeed.
  def up do
    execute "CREATE TEXT SEARCH CONFIGURATION portuguese_unaccent (COPY = portuguese)"

    execute """
    ALTER TEXT SEARCH CONFIGURATION portuguese_unaccent
      ALTER MAPPING FOR hword, hword_part, word
      WITH unaccent, portuguese_stem
    """

    execute """
    ALTER TABLE messages
      ADD COLUMN search_vector tsvector
      GENERATED ALWAYS AS (to_tsvector('portuguese_unaccent', body)) STORED
    """

    execute """
    CREATE INDEX messages_search_vector_index
      ON messages USING GIN (search_vector)
    """
  end

  def down do
    execute "DROP INDEX IF EXISTS messages_search_vector_index"
    execute "ALTER TABLE messages DROP COLUMN IF EXISTS search_vector"
    execute "DROP TEXT SEARCH CONFIGURATION IF EXISTS portuguese_unaccent"
  end
end
