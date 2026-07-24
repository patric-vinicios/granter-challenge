defmodule Api.ContactsVolumeTest do
  @moduledoc """
  The contact list under the volumes the product actually has to survive.

  The list is capped at 500 by `add_contact/2`, but that guardrail is soft — it
  is a pre-check, not a constraint, and the context says so — and a list that
  drifts past it must still answer rather than degrade. These suites therefore
  seed well beyond the cap, for the same reason the inbox suites seed past its
  page cap: what is being measured is the query, and a query that only behaves
  at the size someone remembered to enforce is a query nobody can rely on.

  The assertions mirror `Api.ConversationsVolumeTest` deliberately. Both lists
  page the same way and search the same condition, so a divergence between them
  is a bug in whichever one drifted, and the parallel shape is what makes that
  visible.
  """

  use Api.DataCase, async: false

  alias Api.Contacts
  alias Api.Conversations.Cursor, as: InboxCursor
  alias Api.Volume

  @moduletag :volume
  @moduletag timeout: :infinity

  @volumes [100, 300, 700, 1000, 10_000]
  @cap 200

  setup do
    %{owner: insert(:user)}
  end

  describe "listing contacts at volume" do
    for volume <- @volumes do
      @volume volume

      test "lists a list of #{volume} contacts in one query, capped at #{@cap}", %{owner: owner} do
        Volume.seed_contacts(owner, @volume)

        assert count_queries(fn -> Contacts.list_contacts(owner) end) == 1

        {ms, page} = measure(fn -> Contacts.list_contacts(owner) end)
        report("list", @volume, ms, Enum.count(page.contacts))

        assert Enum.count(page.contacts) == min(@volume, @cap)
        assert page.has_more == @volume > @cap
        assert ascending?(page.contacts)
        assert ms < 2_000
      end
    end
  end

  describe "searching contacts at volume" do
    for volume <- @volumes do
      @volume volume

      test "finds one contact buried in #{volume} contacts", %{owner: owner} do
        # Deep in the tail by insertion order, and alphabetically last by name,
        # so a match can only be found by searching the whole list.
        Volume.seed_contacts(owner, @volume, needle_at: @volume - 50)

        assert count_queries(fn -> Contacts.list_contacts(owner, %{q: "zoraide"}) end) == 1

        {ms, page} = measure(fn -> Contacts.list_contacts(owner, %{q: "zoraide"}) end)
        report("search hit", @volume, ms, Enum.count(page.contacts))

        assert [contact] = page.contacts
        assert contact.user.name == Volume.needle_name()
        assert page.has_more == false
        assert ms < 2_000
      end

      test "answers a term matching nothing in #{volume} contacts with an empty page", %{
        owner: owner
      } do
        Volume.seed_contacts(owner, @volume)

        {ms, page} = measure(fn -> Contacts.list_contacts(owner, %{q: "xyzzynada"}) end)
        report("search miss", @volume, ms, Enum.count(page.contacts))

        assert page.contacts == []
        assert page.next_cursor == nil
        assert page.has_more == false
        assert ms < 2_000
      end
    end

    test "matches by @username as well as by display name", %{owner: owner} do
      Volume.seed_contacts(owner, 1000, needle_at: 950)

      assert %{contacts: [contact]} =
               Contacts.list_contacts(owner, %{q: Volume.needle_username()})

      assert contact.user.username == Volume.needle_username()
    end

    test "matches accent- and case-insensitively at volume", %{owner: owner} do
      Volume.seed_contacts(owner, 1000)
      insert(:contact, owner: owner, user: build(:user, name: "Álvaro Público"))

      assert %{contacts: [contact]} = Contacts.list_contacts(owner, %{q: "alvaro publico"})
      assert contact.user.name == "Álvaro Público"
    end

    test "never reaches another owner's list at volume", %{owner: owner} do
      Volume.seed_contacts(owner, 700)
      stranger = insert(:user)
      Volume.seed_contacts(stranger, 700, needle_at: 100)

      assert %{contacts: []} = Contacts.list_contacts(owner, %{q: "zoraide"})
      assert %{contacts: [_one]} = Contacts.list_contacts(stranger, %{q: "zoraide"})
    end
  end

  describe "walking the whole contact list by cursor" do
    for volume <- [300, 1000, 10_000] do
      @volume volume

      test "visits each of #{volume} contacts exactly once", %{owner: owner} do
        Volume.seed_contacts(owner, @volume)

        {ms, ids} = measure(fn -> walk(owner, %{limit: @cap}) end)
        report("walk", @volume, ms, Enum.count(ids))

        assert Enum.count(ids) == @volume,
               "expected #{@volume} entries, walked #{Enum.count(ids)}"

        assert Enum.count(Enum.uniq(ids)) == @volume, "the walk returned a contact twice"
        assert MapSet.new(ids) == MapSet.new(Volume.contact_ids(owner))
      end
    end

    test "walks a filtered list without losing a match", %{owner: owner} do
      # Every seeded contact shares the `silva` token, so the filter matches far
      # more than one page and the walk has to page through the matches too.
      Volume.seed_contacts(owner, 700)

      ids = walk(owner, %{limit: 50, q: "silva"})

      assert Enum.count(ids) == 700
      assert Enum.count(Enum.uniq(ids)) == 700
    end

    test "honours a limit smaller than the page cap", %{owner: owner} do
      Volume.seed_contacts(owner, 300)

      assert %{contacts: entries, has_more: true, next_cursor: cursor} =
               Contacts.list_contacts(owner, %{limit: 25})

      assert Enum.count(entries) == 25
      assert is_binary(cursor)
      assert Enum.count(walk(owner, %{limit: 25})) == 300
    end

    test "keeps the display-name ordering across page boundaries", %{owner: owner} do
      Volume.seed_contacts(owner, 700)

      names = walk_names(owner, %{limit: 40})

      assert names == Enum.sort_by(names, &fold/1)
    end
  end

  describe "keyset integrity" do
    test "does not skip contacts sharing a display name", %{owner: owner} do
      # Display names are not unique, so a cursor carrying only the name would
      # skip every contact tied with the page boundary.
      for _index <- 1..25 do
        insert(:contact, owner: owner, user: build(:user, name: "Ana Beatriz"))
      end

      ids = walk(owner, %{limit: 5})

      assert Enum.count(ids) == 25
      assert Enum.count(Enum.uniq(ids)) == 25
    end

    test "does not skip contacts whose names differ only by accent or case", %{owner: owner} do
      # These fold to the same sort key, so they tie with each other exactly as
      # identical names do — and the fold in the cursor has to agree with the
      # fold in the ORDER BY or the boundary lands in the wrong place.
      for name <- ~w(alvaro Alvaro ÁLVARO Álvaro álvaro ALVARO) do
        insert(:contact, owner: owner, user: build(:user, name: name))
      end

      ids = walk(owner, %{limit: 2})

      assert Enum.count(ids) == 6
      assert Enum.count(Enum.uniq(ids)) == 6
    end

    test "rejects a malformed cursor rather than answering the first page", %{owner: owner} do
      Volume.seed_contacts(owner, 300)

      assert {:error, :invalid_cursor} = Contacts.list_contacts(owner, %{cursor: "not-a-cursor"})
    end

    test "rejects a cursor minted for a different list", %{owner: owner} do
      Volume.seed_contacts(owner, 10)
      # An inbox cursor carries three components; a contact cursor carries two.
      inbox_cursor =
        InboxCursor.encode({nil, DateTime.utc_now(), Ecto.UUID.generate()})

      assert {:error, :invalid_cursor} = Contacts.list_contacts(owner, %{cursor: inbox_cursor})
    end
  end

  # --- Helpers ---------------------------------------------------------------

  defp walk(owner, opts), do: owner |> walk_pages(opts) |> Enum.map(& &1.id)

  defp walk_names(owner, opts), do: owner |> walk_pages(opts) |> Enum.map(& &1.user.name)

  # Bounded independently of the cursor logic so a cursor that fails to advance
  # is caught as a runaway loop rather than hanging the suite.
  defp walk_pages(owner, opts, cursor \\ nil, seen \\ [], guard \\ 0) do
    if guard > 5_000, do: flunk("the cursor walk did not terminate")

    opts = if cursor, do: Map.put(opts, :cursor, cursor), else: opts
    page = Contacts.list_contacts(owner, opts)
    seen = seen ++ page.contacts

    if page.has_more do
      walk_pages(owner, opts, page.next_cursor, seen, guard + 1)
    else
      seen
    end
  end

  defp ascending?(contacts) do
    keys = Enum.map(contacts, &{fold(&1.user.name), &1.user.id})
    keys == Enum.sort(keys)
  end

  defp fold(name) do
    name
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/[\x{0300}-\x{036F}]/u, "")
    |> String.downcase()
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
        " contatos  -> " <>
        String.pad_leading(:erlang.float_to_binary(ms, decimals: 1), 8) <>
        " ms, #{rows} linha(s)"
    )
  end
end
