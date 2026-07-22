defmodule Api.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create table(:messages) do
      add :conversation_id,
          references(:conversations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :sender_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :body, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    # The history read: leading equality on the conversation, then a range bound
    # over the (inserted_at, id) pair. The newest page and every cursor-bounded
    # page are the same range scan, so the cost does not grow with the
    # conversation. The descending annotations are written as the read orders
    # the rows; with the leading equality they are interchangeable in practice.
    create index(:messages, ["conversation_id", "inserted_at DESC", "id DESC"],
             name: :messages_conversation_id_inserted_at_id_index
           )

    # Without it, deleting a user degrades foreign-key maintenance to a
    # sequential scan of the largest table in the schema.
    create index(:messages, [:sender_id])

    # Storage-layer backstop for the changeset rule, so a writer that bypasses
    # the changeset still cannot store an empty or oversized body. Named, so a
    # violation surfaces as a changeset error rather than a raised exception.
    create constraint(:messages, :messages_body_length,
             check: "char_length(btrim(body)) BETWEEN 1 AND 4000"
           )
  end
end
