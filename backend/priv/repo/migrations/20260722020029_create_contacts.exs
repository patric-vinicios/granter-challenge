defmodule Api.Repo.Migrations.CreateContacts do
  use Ecto.Migration

  def change do
    create table(:contacts) do
      add :owner_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :contact_user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:contacts, [:owner_id, :contact_user_id])
    create index(:contacts, [:contact_user_id])
    create constraint(:contacts, :contacts_not_self, check: "owner_id <> contact_user_id")
  end
end
