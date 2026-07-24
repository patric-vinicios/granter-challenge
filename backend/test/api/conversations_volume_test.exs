defmodule Api.ConversationsVolumeTest do
  @moduledoc """
  The inbox under the volumes the product actually has to survive.

  These are not unit tests of the entry shape — `Api.ConversationsTest` owns
  that. What is asserted here is what only shows up in bulk: that listing and
  searching stay one indexed query as an inbox grows two orders of magnitude,
  that walking the whole list by cursor visits every conversation exactly once,
  and that neither promise depends on the seed data being conveniently spread
  out. The keyset cases at the bottom are the ones that matter most, because a
  cursor that skips rows fails silently — the client is handed a shorter list
  and has no way to know a conversation is missing.

  Timings are printed rather than compared against each other, and the ceilings
  asserted are deliberately loose: the point is to catch a plan that collapses
  into scanning the whole inbox, not to police milliseconds on shared hardware.
  """

  use Api.DataCase, async: false

  alias Api.Conversations
  alias Api.Volume

  @moduletag :volume
  @moduletag timeout: :infinity

  @volumes [100, 300, 700, 1000, 10_000]
  @cap 200

  setup do
    %{caller: insert(:user)}
  end

  describe "listing the inbox at volume" do
    for volume <- @volumes do
      @volume volume

      test "lists an inbox of #{volume} conversations in one query, capped at #{@cap}", %{
        caller: caller
      } do
        Volume.seed_inbox(caller, @volume)

        assert count_queries(fn -> Conversations.list_conversations(caller) end) == 1

        {ms, page} = measure(fn -> Conversations.list_conversations(caller) end)
        report("list", @volume, ms, Enum.count(page.conversations))

        assert Enum.count(page.conversations) == min(@volume, @cap)
        assert page.has_more == @volume > @cap
        assert descending?(page.conversations)
        assert ms < 2_000
      end
    end
  end

  describe "searching the inbox at volume" do
    for volume <- @volumes do
      @volume volume

      test "finds one counterpart buried in #{volume} conversations", %{caller: caller} do
        # Deep in the tail, so a match can only be found by searching the whole
        # inbox and never by happening to sit inside the first page.
        Volume.seed_inbox(caller, @volume, needle_at: @volume - 50)

        assert count_queries(fn -> Conversations.list_conversations(caller, %{q: "zoraide"}) end) ==
                 1

        {ms, page} = measure(fn -> Conversations.list_conversations(caller, %{q: "zoraide"}) end)
        report("search hit", @volume, ms, Enum.count(page.conversations))

        assert [entry] = page.conversations
        assert entry.title == Volume.needle_name()
        assert page.has_more == false
        assert ms < 2_000
      end

      test "answers a term matching nothing in #{volume} conversations with an empty page", %{
        caller: caller
      } do
        Volume.seed_inbox(caller, @volume)

        {ms, page} =
          measure(fn -> Conversations.list_conversations(caller, %{q: "xyzzynada"}) end)

        report("search miss", @volume, ms, Enum.count(page.conversations))

        assert page.conversations == []
        assert page.next_cursor == nil
        assert page.has_more == false
        assert ms < 2_000
      end
    end

    test "matches a counterpart by @username and not only by display name", %{caller: caller} do
      Volume.seed_inbox(caller, 1000, needle_at: 950)

      assert %{conversations: [entry]} =
               Conversations.list_conversations(caller, %{q: Volume.needle_username()})

      assert entry.counterpart.username == Volume.needle_username()
    end

    test "matches accent- and case-insensitively at volume", %{caller: caller} do
      Volume.seed_inbox(caller, 1000)
      other = insert(:user, name: "Família Álvaro")
      messaged_pair(caller, other, ago(5))

      assert %{conversations: [entry]} =
               Conversations.list_conversations(caller, %{q: "familia alvaro"})

      assert entry.title == "Família Álvaro"
    end

    test "never matches a group by a member's name", %{caller: caller} do
      Volume.seed_inbox(caller, 300)
      member = insert(:user, name: Volume.needle_name())
      group = insert(:group, creator: caller, name: "Projeto Alfa")
      # `insert(:group, creator: ...)` seats the factory's own creator, not the
      # override, so the caller has to be seated for the group to be their own.
      insert(:participant, conversation: group, user: caller)
      insert(:participant, conversation: group, user: member)
      insert(:message, conversation: group, sender: member, inserted_at: ago(5))

      assert %{conversations: []} = Conversations.list_conversations(caller, %{q: "Zoraide"})

      assert %{conversations: [entry]} =
               Conversations.list_conversations(caller, %{q: "Projeto Alfa"})

      assert entry.title == "Projeto Alfa"
    end
  end

  describe "walking the whole inbox by cursor" do
    for volume <- [300, 1000, 10_000] do
      @volume volume

      test "visits each of #{volume} conversations exactly once", %{caller: caller} do
        Volume.seed_inbox(caller, @volume)

        {ms, ids} = measure(fn -> walk(caller, %{limit: @cap}) end)
        report("walk", @volume, ms, Enum.count(ids))

        assert Enum.count(ids) == @volume,
               "expected #{@volume} entries, walked #{Enum.count(ids)}"

        assert Enum.count(Enum.uniq(ids)) == @volume, "the walk returned a conversation twice"
        assert MapSet.new(ids) == MapSet.new(Volume.inbox_ids(caller))
      end
    end

    test "walks a filtered list without losing a match", %{caller: caller} do
      # Every counterpart shares the `silva` token, so the filter matches far
      # more than one page and the walk has to page through the matches too.
      Volume.seed_inbox(caller, 700)

      ids = walk(caller, %{limit: 50, q: "silva"})

      assert Enum.count(ids) == 700
      assert Enum.count(Enum.uniq(ids)) == 700
    end

    test "honours a limit smaller than the page cap", %{caller: caller} do
      Volume.seed_inbox(caller, 300)

      assert %{conversations: entries, has_more: true, next_cursor: cursor} =
               Conversations.list_conversations(caller, %{limit: 25})

      assert Enum.count(entries) == 25
      assert is_binary(cursor)
      assert Enum.count(walk(caller, %{limit: 25})) == 300
    end
  end

  describe "keyset integrity" do
    test "does not skip conversations whose last messages share a timestamp", %{caller: caller} do
      # The case the previous timestamp-only cursor lost: one bulk import, one
      # busy second, and every row tied with the page boundary disappears.
      at = ~U[2026-01-01 12:00:00.000000Z]

      for i <- 1..25 do
        other = insert(:user, name: "Empatado #{i}")
        conv = private_pair(caller, other)
        insert(:message, conversation: conv, sender: other, inserted_at: at)
      end

      ids = walk(caller, %{limit: 5})

      assert Enum.count(ids) == 25
      assert Enum.count(Enum.uniq(ids)) == 25
    end

    test "does not skip conversations that have never been used", %{caller: caller} do
      # Message-less conversations sort last as a block, all sharing the same
      # absent activity, so they tie with each other and with the page boundary.
      for i <- 1..15 do
        other = insert(:user, name: "Silencioso #{i}")
        private_pair(caller, other)
      end

      for i <- 1..5 do
        other = insert(:user, name: "Falante #{i}")
        conv = private_pair(caller, other)
        insert(:message, conversation: conv, sender: other, inserted_at: ago(i * 10))
      end

      ids = walk(caller, %{limit: 4})

      assert Enum.count(ids) == 20
      assert Enum.count(Enum.uniq(ids)) == 20
    end

    test "walks a mix of tied, untied and never-used conversations", %{caller: caller} do
      tied_at = ago(100)

      for i <- 1..10 do
        other = insert(:user, name: "Empatado #{i}")
        conv = private_pair(caller, other)
        insert(:message, conversation: conv, sender: other, inserted_at: tied_at)
      end

      for i <- 1..10 do
        other = insert(:user, name: "Distinto #{i}")
        conv = private_pair(caller, other)
        insert(:message, conversation: conv, sender: other, inserted_at: ago(i))
      end

      for i <- 1..10 do
        other = insert(:user, name: "Vazio #{i}")
        private_pair(caller, other)
      end

      ids = walk(caller, %{limit: 7})

      assert Enum.count(ids) == 30
      assert Enum.count(Enum.uniq(ids)) == 30
      assert MapSet.new(ids) == MapSet.new(Volume.inbox_ids(caller))
    end

    test "rejects a malformed cursor rather than answering the first page", %{caller: caller} do
      Volume.seed_inbox(caller, 300)

      assert {:error, :invalid_cursor} =
               Conversations.list_conversations(caller, %{cursor: "not-a-cursor"})
    end
  end

  # --- Helpers ---------------------------------------------------------------

  # Pages through the whole list, collecting ids. Bounded independently of the
  # cursor logic so a cursor that fails to advance is caught as a runaway loop
  # rather than hanging the suite.
  defp walk(caller, opts, cursor \\ nil, seen \\ [], guard \\ 0) do
    if guard > 5_000, do: flunk("the cursor walk did not terminate")

    opts = if cursor, do: Map.put(opts, :cursor, cursor), else: opts
    page = Conversations.list_conversations(caller, opts)
    seen = seen ++ Enum.map(page.conversations, & &1.id)

    if page.has_more do
      walk(caller, opts, page.next_cursor, seen, guard + 1)
    else
      seen
    end
  end

  defp descending?(entries) do
    keys = Enum.map(entries, &{&1.last_message && &1.last_message.inserted_at, &1.id})

    keys ==
      Enum.sort_by(keys, fn {at, id} -> {at || ~U[0001-01-01 00:00:00.000000Z], id} end, :desc)
  end

  # One warm-up call answers with the result, three timed calls with the median.
  # Splitting them keeps the timing clear of the first call's cold caches, and
  # the median of three discards a single scheduling hiccup without pretending
  # three samples support anything finer.
  defp measure(fun) do
    result = fun.()

    times =
      for _ <- 1..3 do
        {us, _} = :timer.tc(fun)
        us / 1000
      end

    [_fastest, median, _slowest] = Enum.sort(times)
    {median, result}
  end

  defp report(label, volume, ms, rows) do
    IO.puts(
      "  [volume] " <>
        String.pad_trailing(label, 13) <>
        String.pad_leading("#{volume}", 6) <>
        " conversas -> " <>
        String.pad_leading(:erlang.float_to_binary(ms, decimals: 1), 8) <>
        " ms, #{rows} linha(s)"
    )
  end

  defp ago(seconds), do: DateTime.add(DateTime.utc_now(), -seconds, :second)

  defp private_pair(caller, other) do
    insert(:conversation, participant_key: Enum.join(Enum.sort([caller.id, other.id]), ":"))
    |> tap(&insert(:participant, conversation: &1, user: caller, joined_at: ago(3600)))
    |> tap(&insert(:participant, conversation: &1, user: other, joined_at: ago(3600)))
  end

  defp messaged_pair(caller, other, at) do
    conv = private_pair(caller, other)
    insert(:message, conversation: conv, sender: other, inserted_at: at)
    conv
  end
end
