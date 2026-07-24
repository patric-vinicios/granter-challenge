defmodule Api.Volume do
  @moduledoc """
  Bulk fixtures for the volume suites.

  The factory writes one row per call, which is the right trade for a test that
  needs three rows and the wrong one for a test that needs forty thousand: ten
  thousand conversations is four `insert_all` calls here and forty thousand
  round trips through the factory. Both volume suites seed people, so the people
  live here and each suite adds only the shape it is measuring.

  Ids are generated from a per-call offset rather than read back, so a seeded id
  is reproducible and the tables never collide with each other or with a second
  call in the same test.
  """

  use Boundary, top_level?: true, check: [in: false, out: false]

  import Ecto.Query, only: [from: 2]

  alias Api.Accounts.User
  alias Api.Contacts.Contact
  alias Api.Conversations.Conversation
  alias Api.Conversations.Participant
  alias Api.Messages.Message
  alias Api.Repo

  @needle_name "Zoraide Buscada"
  @needle_username "zoraide_needle"
  @needle_word "xyzznoticiaunica"
  @match_word "achadocomum"
  @first_names ~w(Ana Bruno Carla Diego Elena Fabio Gabriela Hugo Isabela Joao)

  @doc "The display name every seeded needle carries."
  @spec needle_name() :: String.t()
  def needle_name, do: @needle_name

  @doc "The username every seeded needle carries."
  @spec needle_username() :: String.t()
  def needle_username, do: @needle_username

  @doc """
  `count` users sharing the `Silva` surname, with the one at `needle_at`
  replaced by a uniquely named needle. Returns the attribute maps, which carry
  the generated ids.
  """
  @spec users(non_neg_integer(), non_neg_integer(), keyword()) :: [map()]
  def users(count, offset, opts \\ []) do
    now = now()
    needle_at = Keyword.get(opts, :needle_at)

    rows =
      Enum.map(0..(count - 1), fn i ->
        base = Enum.at(@first_names, rem(i, 10))

        %{
          id: uuid(offset + i),
          name: "#{base} Silva #{i}",
          username: "#{String.downcase(base)}_#{offset + i}",
          hashed_password: "x",
          inserted_at: now,
          updated_at: now
        }
      end)

    rows =
      if needle_at do
        List.replace_at(rows, needle_at, %{
          Enum.at(rows, needle_at)
          | name: @needle_name,
            username: @needle_username
        })
      else
        rows
      end

    insert_chunked(User, rows)
    rows
  end

  @doc """
  `count` private conversations between `caller` and one fresh user each, every
  one carrying a single message, ten seconds apart so the ordering is total.
  """
  @spec seed_inbox(User.t(), non_neg_integer(), keyword()) :: :ok
  def seed_inbox(caller, count, opts \\ []) do
    now = now()
    offset = offset()
    users = users(count, offset, opts)

    conversations =
      Enum.map(Enum.with_index(users), fn {user, i} ->
        at = DateTime.add(now, -i * 10, :second) |> DateTime.truncate(:microsecond)

        %{
          id: uuid(offset + count + i),
          type: :private,
          participant_key: Enum.join(Enum.sort([caller.id, user.id]), ":"),
          inserted_at: at,
          updated_at: at
        }
      end)

    insert_chunked(Conversation, conversations)

    participants =
      Enum.flat_map(Enum.with_index(Enum.zip(conversations, users)), fn {{conv, user}, i} ->
        [
          seat(uuid(offset + count * 2 + i * 2), conv, caller.id),
          seat(uuid(offset + count * 2 + i * 2 + 1), conv, user.id)
        ]
      end)

    insert_chunked(Participant, participants)

    messages =
      Enum.map(Enum.with_index(Enum.zip(conversations, users)), fn {{conv, user}, i} ->
        %{
          id: uuid(offset + count * 4 + i),
          conversation_id: conv.id,
          sender_id: user.id,
          body: "mensagem numero #{i}",
          inserted_at: conv.inserted_at,
          updated_at: conv.inserted_at
        }
      end)

    insert_chunked(Message, messages)
    analyze()
  end

  @doc """
  `count` contacts in `owner`'s list, one fresh user each.
  """
  @spec seed_contacts(User.t(), non_neg_integer(), keyword()) :: :ok
  def seed_contacts(owner, count, opts \\ []) do
    now = now()
    offset = offset()
    users = users(count, offset, opts)

    contacts =
      Enum.map(Enum.with_index(users), fn {user, i} ->
        # `contacts` carries no `updated_at` — a contact row is never edited.
        %{
          id: uuid(offset + count + i),
          owner_id: owner.id,
          contact_user_id: user.id,
          inserted_at: now
        }
      end)

    insert_chunked(Contact, contacts)
    analyze()
  end

  @doc "The unique word placed at `:needle_at` by `seed_history/3`."
  @spec needle_word() :: String.t()
  def needle_word, do: @needle_word

  @doc "The common word sprinkled by `:matches` in `seed_history/3`."
  @spec match_word() :: String.t()
  def match_word, do: @match_word

  @doc """
  One private conversation between `caller` and a fresh user, carrying `count`
  messages one second apart in ascending time, so `(inserted_at)` is a total
  order over the history.

  Options:

    * `:needle_at` — the index whose body carries the unique `needle_word/0`, so
      a single message can be found by search in the middle of a large history
    * `:matches` — how many messages carry the common `match_word/0`, spread
      evenly, so search result sizes can be measured

  Returns the conversation id.
  """
  @spec seed_history(User.t(), non_neg_integer(), keyword()) :: Ecto.UUID.t()
  def seed_history(caller, count, opts \\ []) do
    now = now()
    offset = offset()
    [other] = users(1, offset)
    conv_id = uuid(offset + 1)
    conv = %{id: conv_id, inserted_at: now}

    insert_chunked(Conversation, [
      %{
        id: conv_id,
        type: :private,
        participant_key: Enum.join(Enum.sort([caller.id, other.id]), ":"),
        inserted_at: now,
        updated_at: now
      }
    ])

    insert_chunked(Participant, [
      seat(uuid(offset + 2), conv, caller.id),
      seat(uuid(offset + 3), conv, other.id)
    ])

    needle_at = Keyword.get(opts, :needle_at)
    match_at = matches_set(Keyword.get(opts, :matches, 0), count)

    messages =
      Enum.map(0..(count - 1), fn i ->
        at = now |> DateTime.add(i - count, :second) |> DateTime.truncate(:microsecond)

        %{
          id: uuid(offset + 100 + i),
          conversation_id: conv_id,
          sender_id: other.id,
          body: body_for(i, needle_at, match_at),
          inserted_at: at,
          updated_at: at
        }
      end)

    insert_chunked(Message, messages)
    analyze()
    conv_id
  end

  defp body_for(i, i, _match_at), do: "mensagem #{@needle_word} de teste #{i}"

  defp body_for(i, _needle_at, match_at) do
    if MapSet.member?(match_at, i),
      do: "mensagem com #{@match_word} aqui #{i}",
      else: "mensagem numero #{i}"
  end

  defp matches_set(0, _count), do: MapSet.new()

  defp matches_set(k, count) do
    step = max(div(count, k), 1)
    0..(k - 1) |> Enum.map(&rem(&1 * step, count)) |> MapSet.new()
  end

  @doc "The conversation ids `caller` actively participates in."
  @spec inbox_ids(User.t()) :: [Ecto.UUID.t()]
  def inbox_ids(caller) do
    Repo.all(
      from(p in Participant,
        where: p.user_id == ^caller.id and is_nil(p.left_at),
        select: p.conversation_id
      )
    )
  end

  @doc "The contact row ids in `owner`'s list."
  @spec contact_ids(User.t()) :: [Ecto.UUID.t()]
  def contact_ids(owner) do
    Repo.all(from(c in Contact, where: c.owner_id == ^owner.id, select: c.id))
  end

  # Bulk inserts leave the planner working from stale statistics, which is not
  # the state a running system is in and produces plans it would never pick.
  defp analyze do
    for table <- ~w(users conversations conversation_participants contacts messages) do
      Repo.query!("ANALYZE #{table}", [], timeout: :infinity)
    end

    :ok
  end

  defp seat(id, conv, user_id) do
    %{
      id: id,
      conversation_id: conv.id,
      user_id: user_id,
      joined_at: conv.inserted_at,
      inserted_at: conv.inserted_at,
      updated_at: conv.inserted_at
    }
  end

  defp insert_chunked(schema, rows) do
    rows
    |> Enum.chunk_every(5_000)
    |> Enum.each(&Repo.insert_all(schema, &1, timeout: :infinity))
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)

  defp offset, do: System.unique_integer([:positive]) * 100_000

  defp uuid(n) do
    digits =
      n |> abs() |> rem(10_000_000_000_000) |> Integer.to_string() |> String.pad_leading(12, "0")

    "00000000-0000-0000-0000-#{digits}"
  end
end
