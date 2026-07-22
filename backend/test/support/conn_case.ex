defmodule ApiWeb.ConnCase do
  @moduledoc """
  Case template for controller tests.

  Builds a `Plug.Conn` and checks out the same SQL sandbox connection as
  `Api.DataCase`, so a request handled by the endpoint sees the data the test
  inserted and rolls it back on exit.
  """

  use ExUnit.CaseTemplate
  use Boundary, top_level?: true, check: [in: false, out: false]

  using do
    quote do
      # The default endpoint for testing
      @endpoint ApiWeb.Endpoint

      use ApiWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import ApiWeb.ConnCase
    end
  end

  setup tags do
    Api.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
