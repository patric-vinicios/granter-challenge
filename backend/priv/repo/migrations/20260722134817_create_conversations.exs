defmodule Api.Repo.Migrations.CreateConversations do
  use Ecto.Migration

  def change do
    create table(:conversations) do
      add :type, :string, null: false
      add :name, :string
      add :creator_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :participant_key, :string

      timestamps(type: :utc_datetime_usec)
    end

    # One private conversation per pair. The partial predicate keeps the index
    # off group rows, whose participant_key is null, and lets it back the
    # unique_constraint that turns a concurrent duplicate into a caught error.
    create unique_index(:conversations, [:participant_key],
             where: "type = 'private'",
             name: :conversations_participant_key_index
           )

    create table(:conversation_participants) do
      add :conversation_id,
          references(:conversations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :last_read_at, :utc_datetime_usec
      add :joined_at, :utc_datetime_usec, null: false
      add :left_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    # One membership row per user per conversation; also serves participant?/2
    # (exact) and the show query's counterpart lookup (leftmost prefix).
    create unique_index(:conversation_participants, [:conversation_id, :user_id])
  end
end
