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
      @endpoint ApiWeb.Endpoint

      use ApiWeb, :verified_routes

      import Api.DataCase, only: [count_queries: 1]
      import Api.Factory
      import ApiWeb.ConnCase
      import Phoenix.ConnTest
      import Plug.Conn
    end
  end

  setup tags do
    owner = Api.DataCase.setup_sandbox(tags)

    {:ok, conn: Phoenix.ConnTest.build_conn(), sandbox_owner: owner}
  end

  @doc """
  A connection that negotiates JSON both ways.

  `build_conn/0` sends no `accept` header, which is enough for the router's
  `:accepts` step but leaves a request body unparsed. Controller tests that
  post a payload need this one.
  """
  def json_conn do
    Phoenix.ConnTest.build_conn()
    |> Plug.Conn.put_req_header("accept", "application/json")
    |> Plug.Conn.put_req_header("content-type", "application/json")
  end
end
