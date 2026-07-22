defmodule ApiWeb.ChannelCase do
  @moduledoc """
  Case template for socket and channel tests.

  Gives socket and channel tests the same sandbox checkout and factory
  imports the HTTP tests get, so real-time tests do not grow their own ad-hoc
  setup.
  """

  use ExUnit.CaseTemplate
  use Boundary, top_level?: true, check: [in: false, out: false]

  using do
    quote do
      @endpoint ApiWeb.Endpoint

      import Api.Factory
      import Phoenix.ChannelTest
    end
  end

  setup tags do
    Api.DataCase.setup_sandbox(tags)
    :ok
  end
end
