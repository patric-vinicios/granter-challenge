defmodule ApiWeb.ChannelCase do
  @moduledoc """
  Case template for socket and channel tests.

  Gives socket and channel tests the same sandbox checkout and factory
  imports the HTTP tests get, so real-time tests do not grow their own ad-hoc
  setup, plus `connect_socket/1` so none of them restates the handshake.
  """

  use ExUnit.CaseTemplate
  use Boundary, top_level?: true, check: [in: false, out: false]

  alias Api.Accounts.Guardian
  alias Phoenix.ChannelTest

  @endpoint ApiWeb.Endpoint

  using do
    quote do
      @endpoint ApiWeb.Endpoint

      import Api.Factory
      import Phoenix.ChannelTest
      import ApiWeb.ChannelCase, only: [connect_socket: 1]
    end
  end

  setup tags do
    Api.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  An authenticated socket for `user`, issued the same token the HTTP pipeline
  verifies and run through `UserSocket.connect/3`, so a channel test names the
  handshake once by the user it belongs to.
  """
  def connect_socket(user) do
    {:ok, token, _expires_at} = Guardian.issue_token(user)

    {:ok, socket} =
      ChannelTest.__connect__(@endpoint, ApiWeb.UserSocket, %{"token" => token}, [])

    socket
  end
end
