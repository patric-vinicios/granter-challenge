defmodule ApiWeb.UserChannel do
  @moduledoc """
  A user's private notification topic, `user:<id>`.

  The only join rule is that the topic id must be the connected user's own, so a
  socket can never subscribe to another user's notifications. The channel takes
  no inbound event: it exists to receive `conversation:updated` and, because
  reaching it already proves the socket is the user it names, to be the one place
  presence tracks that user.

  On join it tracks the connection under the user's id and schedules a periodic
  `last_seen_at` refresh. The refresh covers the disconnect a leave callback
  never sees — a crashed node — bounding how stale the stored timestamp can be
  to one interval. While the socket lives presence reports the user as online,
  so the refreshed value only surfaces after an unclean drop.
  """

  use ApiWeb, :channel

  alias Api.Accounts
  alias ApiWeb.Presence

  @impl true
  def join("user:" <> user_id, _payload, socket) do
    if user_id == socket.assigns.current_user_id do
      send(self(), :after_join)
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_in(_event, _payload, socket) do
    {:reply, {:error, %{reason: "unknown_event"}}, socket}
  end

  @impl true
  def handle_info(:after_join, socket) do
    {:ok, _ref} =
      Presence.track(socket, socket.assigns.current_user_id, %{online_at: DateTime.utc_now()})

    schedule_refresh()
    {:noreply, socket}
  end

  def handle_info(:refresh_last_seen, socket) do
    Accounts.update_last_seen(socket.assigns.current_user_id, DateTime.utc_now())
    schedule_refresh()
    {:noreply, socket}
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh_last_seen, refresh_interval())
  end

  defp refresh_interval do
    Application.get_env(:api, :last_seen_refresh_ms, 60_000)
  end
end
