defmodule Api.MessagesVolumeTest do
  @moduledoc """
  The message subsystem under the volumes and the concurrency a busy chat throws
  at it.

  Unit correctness — ordering, cursors, the search contract — is owned by
  `Api.MessagesTest`. What is asserted here is only what shows up in bulk and
  under contention: that in-conversation search stays one indexed query as a
  history grows from a thousand to a hundred thousand messages, that a needle can
  be found in the middle of that history, that walking the whole history by
  cursor visits every message exactly once and in order, and that a burst of
  simultaneous sends into one conversation neither loses nor duplicates a row.

  Timings are printed, not compared; the ceilings are deliberately loose. The
  point is to catch a plan that collapses into a sequential scan of the messages
  table, not to police milliseconds on shared hardware.
  """

  use Api.DataCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Api.Conversations
  alias Api.Messages
  alias Api.Messages.Message
  alias Api.Repo
  alias Api.Volume

  @moduletag :volume
  @moduletag timeout: :infinity

  # The middle of each history, so a hit can only come from searching the whole
  # conversation and never from happening to sit on the newest page.
  @search_scales [1_000, 10_000, 100_000]
  @walk_scales [10_000, 100_000]

  setup do
    %{caller: insert(:user)}
  end

  describe "searching a conversation at volume" do
    for scale <- @search_scales do
      @scale scale

      test "finds a needle in the middle of #{scale} messages", %{caller: caller} do
        conv = Volume.seed_history(caller, @scale, needle_at: div(@scale, 2))

        # One query authorizes the read (participation), one runs the GIN search;
        # the count is fixed, never a function of history size.
        assert count_queries(fn ->
                 Messages.search_messages(caller, conv, Volume.needle_word())
               end) ==
                 2

        {ms, {:ok, page}} =
          measure(fn -> Messages.search_messages(caller, conv, Volume.needle_word()) end)

        report("search hit", @scale, ms, length(page.messages))

        assert page.total_matches == 1
        assert [hit] = page.messages
        assert hit.message.body =~ Volume.needle_word()
        assert ms < 2_000
      end

      test "answers a missing term over #{scale} messages with an empty result", %{
        caller: caller
      } do
        conv = Volume.seed_history(caller, @scale)

        {ms, {:ok, page}} =
          measure(fn -> Messages.search_messages(caller, conv, "termoinexistentexyz") end)

        report("search miss", @scale, ms, length(page.messages))

        assert page.total_matches == 0
        assert page.messages == []
        assert ms < 2_000
      end
    end
  end

  describe "search result sizes" do
    for k <- [10, 100] do
      @k k

      test "returns exactly #{k} matches out of 10k messages, positions 1..#{k}", %{
        caller: caller
      } do
        conv = Volume.seed_history(caller, 10_000, matches: @k)

        {ms, {:ok, page}} =
          measure(fn -> Messages.search_messages(caller, conv, Volume.match_word()) end)

        report("result size", @k, ms, length(page.messages))

        assert page.total_matches == @k
        assert page.truncated == false
        assert length(page.messages) == @k
        assert Enum.map(page.messages, & &1.position) == Enum.to_list(1..@k)
      end
    end

    test "caps at 100 and flags truncated when more than 100 match", %{caller: caller} do
      conv = Volume.seed_history(caller, 10_000, matches: 250)

      {:ok, page} = Messages.search_messages(caller, conv, Volume.match_word())

      assert page.total_matches == 100
      assert page.truncated == true
      assert Enum.count(page.messages) == 100
    end
  end

  describe "walking the whole history by cursor" do
    for scale <- @walk_scales do
      @scale scale

      test "reads all #{scale} messages exactly once, in ascending order", %{caller: caller} do
        conv = Volume.seed_history(caller, @scale)

        {ms, messages} = measure(fn -> walk_history(caller, conv, 100) end)
        report("walk", @scale, ms, length(messages))

        ids = Enum.map(messages, & &1.id)
        assert length(ids) == @scale
        assert length(Enum.uniq(ids)) == @scale, "the walk returned a message twice"
        assert ascending?(messages)
      end
    end
  end

  describe "a burst of simultaneous sends into one conversation" do
    test "persists every message once with no loss or duplication", %{caller: caller} do
      # DataCase runs this module with a shared sandbox (async: false), so the
      # spawned tasks reach the database through the test's connection.
      other = insert(:user)
      insert(:contact, owner: caller, user: other)
      {:ok, _outcome, conv} = Conversations.create_private_conversation(caller, other.id)

      results =
        1..200
        |> Task.async_stream(
          fn i -> Messages.create_message(caller, conv.id, %{body: "rajada #{i}"}) end,
          max_concurrency: 25,
          timeout: :infinity,
          ordered: false
        )
        |> Enum.map(fn {:ok, result} -> result end)

      assert Enum.all?(results, &match?({:ok, %Message{}}, &1))

      persisted =
        Repo.aggregate(from(m in Message, where: m.conversation_id == ^conv.id), :count)

      assert persisted == 200

      walked = walk_history(caller, conv.id, 100)
      assert Enum.count(walked) == 200
      assert Enum.count(Enum.uniq(Enum.map(walked, & &1.id))) == 200
      assert ascending?(walked)
    end
  end

  # --- helpers ------------------------------------------------------------

  defp measure(fun) do
    {us, result} = :timer.tc(fun)
    {us / 1000, result}
  end

  defp report(label, scale, ms, rows) do
    IO.puts(
      "  [volume] #{String.pad_trailing(label, 12)} #{String.pad_leading(Integer.to_string(scale), 8)} -> #{:erlang.float_to_binary(ms, decimals: 1)} ms, #{rows} linha(s)"
    )

    :ok
  end

  # Pages from the newest backwards via the `before` cursor; each page is
  # ascending, and older pages are prepended so the flattened result is the whole
  # history in ascending order.
  defp walk_history(caller, conv_id, limit), do: walk_history(caller, conv_id, limit, nil, [])

  defp walk_history(caller, conv_id, limit, cursor, acc) do
    {:ok, page} = Messages.list_messages(caller, conv_id, %{limit: limit, before: cursor})
    acc = [page.messages | acc]

    if page.has_more and page.next_cursor do
      walk_history(caller, conv_id, limit, page.next_cursor, acc)
    else
      List.flatten(acc)
    end
  end

  defp ascending?(messages) do
    times = Enum.map(messages, & &1.inserted_at)
    times == Enum.sort(times, {:asc, DateTime})
  end
end
