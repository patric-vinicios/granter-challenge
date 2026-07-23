defmodule Api.Repo.Migrations.AddConversationParticipantsUserIndex do
  use Ecto.Migration

  # The existing unique index leads on conversation_id, so the inbox's driving
  # scan — every conversation of one user — cannot use it and degrades to a
  # sequential scan of the whole participant table. The partial predicate keeps
  # departed rows out of the structure the scan reads.
  def change do
    create index(:conversation_participants, [:user_id],
             where: "left_at IS NULL",
             name: :conversation_participants_user_id_active_index
           )
  end
end
