defmodule Api.Seeds do
  @moduledoc """
  Turns an empty database into the application the reference screens show.

  Every row is written through the same context functions a request goes
  through — `Accounts.register_user/1`, `Contacts.add_contact/2`,
  `Conversations.create_private_conversation/2` and `create_group/3`, and
  `Messages.create_message/3` — so no seeded row can violate a rule a real row
  must satisfy. That is why the write order is the dependency chain the domain
  enforces: users, then the contact mesh, then conversations, then messages.

  Two guards run before the transaction is opened, and their order is the
  contract. The production refusal comes first and issues no query, so a
  production database is never even connected to on behalf of this script. The
  already-seeded check comes second and is a success, not an error, so
  `mix ecto.setup` exits 0 on a populated database.

  The whole run is one transaction, so the database is only ever untouched or
  fully seeded — never the half-written state that would make the skip check
  fire over a broken dataset. `run/1` takes the dataset so the rollback contract
  can be asserted with a deliberately invalid one; `run/0` is the single entry
  point the script uses.
  """

  use Boundary, deps: [Api, Api.Accounts, Api.Contacts, Api.Conversations, Api.Messages]

  import Ecto.Query, warn: false

  alias Api.Accounts
  alias Api.Contacts
  alias Api.Conversations
  alias Api.Conversations.Participant
  alias Api.Messages
  alias Api.Repo
  alias Api.Seeds.Dataset

  @spec run() :: {:ok, map()} | {:ok, :skipped} | {:error, term()}
  @spec run(map()) :: {:ok, map()} | {:ok, :skipped} | {:error, term()}
  def run(dataset \\ Dataset.all()) do
    cond do
      prod?() -> refuse()
      already_seeded?(dataset) -> skip()
      true -> seed(dataset)
    end
  rescue
    error in Postgrex.Error ->
      if error.postgres[:code] == :undefined_table do
        raise_not_ready(error)
      else
        reraise(error, __STACKTRACE__)
      end

    error in DBConnection.ConnectionError ->
      raise_not_ready(error)
  end

  defp prod?, do: Application.fetch_env!(:api, :env) == :prod

  defp refuse do
    IO.puts(
      "Refusing to seed demo data in the #{Application.fetch_env!(:api, :env)} environment."
    )

    {:error, :prod_refused}
  end

  defp already_seeded?(%{primary: primary}),
    do: not is_nil(Accounts.get_user_by_username(primary))

  defp skip do
    IO.puts("Seeds already applied, skipping")
    {:ok, :skipped}
  end

  defp seed(dataset) do
    anchor = DateTime.utc_now()

    Repo.transaction(
      fn ->
        users = seed_users(dataset)
        seed_contacts(users)
        conversations = seed_conversations(dataset, users, anchor)
        seed_unread(conversations, users[dataset.primary], anchor)
        summary(users, conversations)
      end,
      timeout: :infinity
    )
    |> case do
      {:ok, summary} ->
        report(summary)
        {:ok, summary}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp seed_users(%{users: users, password: password}) do
    Map.new(users, fn %{username: username, name: name} ->
      user =
        case Accounts.get_user_by_username(username) do
          nil ->
            take(
              {:user, username},
              Accounts.register_user(%{username: username, name: name, password: password})
            )

          existing ->
            existing
        end

      {username, user}
    end)
  end

  defp seed_contacts(users) do
    usernames = Map.keys(users)

    for owner_username <- usernames,
        target_username <- usernames,
        owner_username != target_username do
      take(
        {:contact, owner_username, target_username},
        Contacts.add_contact(users[owner_username], target_username)
      )
    end
  end

  defp seed_conversations(%{conversations: conversations, primary: primary}, users, anchor) do
    Enum.map(conversations, &seed_conversation(&1, users[primary], users, anchor))
  end

  defp seed_conversation(%{kind: :private, with: counterpart} = spec, primary, users, anchor) do
    conversation =
      take(
        {:conversation, :private, counterpart},
        Conversations.create_private_conversation(primary, users[counterpart].id)
      )

    {spec, conversation, seed_messages(spec, conversation, users, anchor)}
  end

  defp seed_conversation(%{kind: :group, name: name} = spec, _primary, users, anchor) do
    creator = users[spec.creator]

    member_ids =
      spec.members
      |> Enum.reject(&(&1 == spec.creator))
      |> Enum.map(&users[&1].id)

    conversation = take({:group, name}, Conversations.create_group(creator, name, member_ids))

    {spec, conversation, seed_messages(spec, conversation, users, anchor)}
  end

  defp seed_messages(%{messages: messages}, conversation, users, anchor) do
    Enum.map(messages, fn {sender, body, offset} ->
      take(
        {:message, sender},
        Messages.create_message(users[sender], conversation.id, %{
          body: body,
          inserted_at: resolve(anchor, offset)
        })
      )
    end)
  end

  defp resolve(anchor, {days_ago, minutes_back}) do
    anchor
    |> DateTime.add(-days_ago, :day)
    |> DateTime.add(-minutes_back, :minute)
  end

  defp seed_unread(conversations, primary, anchor) do
    Enum.each(conversations, fn {spec, conversation, messages} ->
      set_last_read(conversation.id, primary.id, read_at(spec, messages, anchor))

      for participant <- conversation.participants, participant.user_id != primary.id do
        set_last_read(conversation.id, participant.user_id, anchor)
      end
    end)
  end

  defp read_at(%{unread: 0}, _messages, anchor), do: anchor

  defp read_at(%{unread: unread}, messages, _anchor) do
    Enum.at(messages, length(messages) - unread - 1).inserted_at
  end

  defp set_last_read(conversation_id, user_id, last_read_at) do
    Participant
    |> where([p], p.conversation_id == ^conversation_id and p.user_id == ^user_id)
    |> Repo.update_all(set: [last_read_at: last_read_at, updated_at: DateTime.utc_now()])
  end

  defp summary(users, conversations) do
    %{
      users: map_size(users),
      conversations: length(conversations),
      messages:
        conversations
        |> Enum.map(fn {_spec, _conv, messages} -> length(messages) end)
        |> Enum.sum()
    }
  end

  defp report(%{users: users, conversations: conversations, messages: messages}) do
    IO.puts("Seeded #{users} users, #{conversations} conversations and #{messages} messages.")
  end

  defp take(_label, {:ok, record}), do: record
  defp take(_label, {:ok, _tag, record}), do: record
  defp take(label, {:error, reason}), do: abort(label, reason)
  defp take(label, {:error, reason, detail}), do: abort(label, {reason, detail})

  defp abort(label, %Ecto.Changeset{} = changeset) do
    IO.puts("Failed to seed #{inspect(label)}: #{inspect(changeset_errors(changeset))}")
    Repo.rollback({label, changeset})
  end

  defp abort(label, reason) do
    IO.puts("Failed to seed #{inspect(label)}: #{inspect(reason)}")
    Repo.rollback({label, reason})
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp raise_not_ready(error) do
    raise """
    The database is not ready for seeding: #{Exception.message(error)}
    Run `mix ecto.migrate` (or `mix ecto.setup`) and try again.
    """
  end
end
