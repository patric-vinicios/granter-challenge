defmodule Api.Conversations do
  @moduledoc """
  Every conversation in the product, private or group.

  A private conversation is not a table of its own: it is a `conversations` row
  of `type: :private` with exactly two participant rows. Modelling both kinds on
  the same tables is what lets the later features write one message foreign key,
  join one channel topic and answer one inbox query rather than branching on a
  kind they would have to detect.

  `participant?/2` is the context's real deliverable to the rest of the system,
  the same way `contact?/2` is the contacts context's: the history read, the
  channel join and the send path are three code paths that must answer one
  question — may this user see this conversation? — and answering it here keeps
  the rule from diverging across them. It ships as an active-membership check
  and deliberately stops there; the departed-member visibility bound belongs to
  the feature that owns messages and group leaves, not to this one.

  The contact rule is enforced on create and nowhere else. Opening a thread
  needs the target as a contact; reading it needs only participation. That
  asymmetry is deliberate: the recipient reads a conversation they were opened
  into without adding the initiator back, and a later contact removal blocks a
  new create while leaving the existing thread readable, because removal changes
  what `contact?/2` answers on the next create and touches no participant row.
  """

  use Boundary, deps: [Api, Api.Accounts, Api.Contacts], exports: [Conversation, Participant]

  import Ecto.Query, warn: false

  alias Api.Accounts
  alias Api.Accounts.User
  alias Api.Contacts
  alias Api.Conversations.Conversation
  alias Api.Conversations.Participant
  alias Api.Repo
  alias Ecto.Multi

  @doc """
  Opens the private conversation between `caller` and the user named by
  `target_id`, or returns the existing one.

  The guards run in a fixed order — self, existence, contact — so the error a
  caller sees when more than one condition holds is the contract, not an
  accident: passing one's own id is `self_conversation`, not `not_a_contact`,
  and an unknown id is a 404, not a 403 that would confuse a typo for a
  permission problem.

  Idempotency has two layers. The pre-check returns the existing conversation
  for the ordinary double-click or reload; the `participant_key` unique index is
  the backstop that turns two genuinely concurrent creates into one winner and
  one caught error re-read as the existing row, never a duplicate or a 500.
  """
  def create_private_conversation(%User{} = caller, target_id) do
    with :ok <- refute_self(caller, target_id),
         {:ok, target} <- resolve_target(target_id),
         :ok <- refute_non_contact(caller, target) do
      key = participant_key(caller, target)

      case Repo.get_by(Conversation, participant_key: key, type: :private) do
        %Conversation{} = existing -> {:ok, :existing, load(existing)}
        nil -> insert_pair(caller, target, key)
      end
    end
  end

  @doc """
  Reads a conversation the caller participates in, with the counterpart loaded.

  The read is gated on participation, never on contact, which is what lets the
  recipient of a conversation read it without having added the initiator. A
  malformed id is rejected before any query; a well-formed id that names no
  conversation, or one the caller does not participate in, gets one
  indistinguishable `:not_found`, so a conversation's existence is never
  disclosed to an outsider.
  """
  def get_conversation(%User{} = caller, id) do
    with {:ok, uuid} <- cast_id(id) do
      case Repo.get(Conversation, uuid) do
        nil ->
          {:error, :not_found}

        %Conversation{} = conversation ->
          conversation = load(conversation)

          if Enum.any?(conversation.participants, &(&1.user_id == caller.id)) do
            {:ok, conversation}
          else
            {:error, :not_found}
          end
      end
    end
  end

  @doc """
  Whether `user` is an active member of `conversation`, taking a record or an id
  on either side.

  Active means a participant row with `left_at` null. Evaluated at request time
  by every caller, so a leave takes effect on the very next call. The
  departed-member bound the history read needs is added by the feature that owns
  it, not guessed here.
  """
  def participant?(%Conversation{id: id}, user), do: participant?(id, user)
  def participant?(conversation_id, %User{id: id}), do: participant?(conversation_id, id)

  def participant?(conversation_id, user_id) do
    Participant
    |> where(
      [p],
      p.conversation_id == ^conversation_id and p.user_id == ^user_id and is_nil(p.left_at)
    )
    |> Repo.exists?()
  end

  # Sorting the pair before joining is what makes the key symmetric, so
  # A-opens-B and B-opens-A collapse onto one conversation.
  defp participant_key(%User{id: a}, %User{id: b}), do: Enum.join(Enum.sort([a, b]), ":")

  defp refute_self(%User{id: id}, id), do: {:error, :self_conversation}
  defp refute_self(_caller, _target_id), do: :ok

  defp resolve_target(target_id) do
    case Accounts.get_user(target_id) do
      %User{} = target -> {:ok, target}
      nil -> {:error, :user_not_found}
    end
  end

  defp refute_non_contact(caller, target) do
    if Contacts.contact?(caller, target), do: :ok, else: {:error, :not_a_contact}
  end

  # The pre-check already answered the common repeat, so a unique violation here
  # means two requests raced past it. That is a 200 returning the winner's row,
  # never a 500 — the same constraint-as-backstop shape the contacts context
  # uses for a duplicate contact, now guarding a three-row transaction.
  defp insert_pair(caller, target, key) do
    now = DateTime.utc_now()

    multi =
      Multi.new()
      |> Multi.insert(:conversation, Conversation.private_changeset(%Conversation{}, key))
      |> Multi.insert(:caller, &member_changeset(&1.conversation, caller, now))
      |> Multi.insert(:target, &member_changeset(&1.conversation, target, now))

    case Repo.transaction(multi) do
      {:ok, %{conversation: conversation}} ->
        {:ok, :created, load(conversation)}

      {:error, :conversation, %Ecto.Changeset{}, _changes} ->
        existing = Repo.get_by!(Conversation, participant_key: key, type: :private)
        {:ok, :existing, load(existing)}
    end
  end

  defp member_changeset(conversation, %User{} = user, joined_at) do
    %Participant{conversation_id: conversation.id, user_id: user.id}
    |> Participant.changeset(%{joined_at: joined_at})
  end

  defp load(%Conversation{} = conversation), do: Repo.preload(conversation, participants: :user)

  defp cast_id(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :invalid_id}
    end
  end
end
