defmodule Api.Repo.Migrations.CreateConversations do
  use Ecto.Migration

  def change do
    create table(:conversations) do
      add :type, :string, null: false
      add :name, :string, size: 60
      add :creator_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    # The Ecto.Enum domain, enforced at the database so no path can write a
    # third type, and the private/group split kept honest: a group always
    # carries a name and a private conversation never does, whichever feature
    # writes the row.
    create constraint(:conversations, :conversations_type_check,
             check: "type IN ('private', 'group')"
           )

    create constraint(:conversations, :conversations_name_matches_type,
             check: "(type = 'group' AND name IS NOT NULL) OR (type = 'private' AND name IS NULL)"
           )

    create table(:conversation_participants) do
      add :conversation_id,
          references(:conversations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :last_read_at, :utc_datetime_usec
      add :joined_at, :utc_datetime_usec, null: false
      add :left_at, :utc_datetime_usec
    end

    # One row per user per conversation, ever: a re-added member reuses their
    # row rather than racing this index, and its leftmost prefix serves the
    # member-list scans and the active-participant check.
    create unique_index(:conversation_participants, [:conversation_id, :user_id])

    # Serves "the conversations of a user" and keeps the users cascade off a
    # sequential scan.
    create index(:conversation_participants, [:user_id])
  end
end
