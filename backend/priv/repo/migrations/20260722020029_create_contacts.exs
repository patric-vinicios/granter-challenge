defmodule Api.Repo.Migrations.CreateContacts do
  use Ecto.Migration

  # A contact is a unidirectional pair: only the owner's row is written, so
  # "A lists B" and "B lists A" stay independent facts. The row is inserted and
  # deleted, never modified, which is why it carries no `updated_at`.
  def change do
    create table(:contacts, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")

      add :owner_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :contact_user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Serves the duplicate pre-check and the membership predicate as exact
    # matches, and its leftmost prefix serves the owner-scoped list.
    create unique_index(:contacts, [:owner_id, :contact_user_id])

    # Keeps the cascade from a deleted account off a sequential scan.
    create index(:contacts, [:contact_user_id])

    # The context guard is what produces the typed 422; this makes a self-pair
    # unrepresentable whichever path writes the row.
    create constraint(:contacts, :contacts_not_self, check: "owner_id <> contact_user_id")
  end
end
