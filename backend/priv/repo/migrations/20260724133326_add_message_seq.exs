defmodule Api.Repo.Migrations.AddMessageSeq do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :seq, :bigserial
    end

    create index(:messages, ["conversation_id", "inserted_at DESC", "seq DESC"],
             name: :messages_conversation_id_inserted_at_seq_index
           )

    drop index(:messages, ["conversation_id", "inserted_at DESC", "id DESC"],
           name: :messages_conversation_id_inserted_at_id_index
         )
  end
end
