defmodule ApiWeb.Presence do
  @moduledoc """
  Tracks who is connected, keyed by the user rather than the conversation.

  A user is tracked under key `<user_id>` on their own `user:<user_id>` topic,
  whose join rule already proves the socket is that user, so presence inherits
  the authorization and can forge no entry for anyone else. Online is one global
  truth every conversation reads: `≥ 1` tracked meta is online, `0` is offline,
  and every browser tab is one more meta under the key.

  `handle_metas/4` turns a disconnect into a durable `last_seen_at`. It sees the
  surviving presences, so it writes only on the *final* leave — a tab closing
  while another stays open writes nothing. A crashed node never runs a leave, so
  the tracking channel also refreshes the value periodically; between the two the
  stored timestamp is at worst a minute stale, the acceptable direction to be
  wrong for a "last seen" label.
  """

  use Phoenix.Presence, otp_app: :api, pubsub_server: Api.PubSub

  alias Api.Accounts

  @doc """
  Whether `user_id` currently holds any tracked socket.

  ## Parameters

    * `user_id` — the user's id, as a string

  An O(1) ETS read over the user's presence topic — no database — so the
  conversation detail can ask it per member on the render path.

  ## Examples

      iex> ApiWeb.Presence.online?(user.id)
      true
  """
  @spec online?(String.t()) :: boolean()
  def online?(user_id) when is_binary(user_id),
    do: map_size(list("user:#{user_id}")) > 0

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def handle_metas("user:" <> user_id, %{leaves: leaves}, presences, state) do
    if map_size(leaves) > 0 and not Map.has_key?(presences, user_id) do
      stamp_last_seen(user_id)
    end

    {:ok, state}
  end

  def handle_metas(_topic, _diff, _presences, state), do: {:ok, state}

  # A best-effort stamp must never take the tracker down with it: losing every
  # user's presence because one `last_seen_at` write hit a transient database
  # error is a far worse outcome than a slightly stale timestamp, which the next
  # refresh or clean leave gets another chance to correct.
  defp stamp_last_seen(user_id) do
    Accounts.update_last_seen(user_id, DateTime.utc_now())
  rescue
    _error -> :ok
  catch
    :exit, _reason -> :ok
  end
end
