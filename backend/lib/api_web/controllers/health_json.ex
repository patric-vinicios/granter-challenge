defmodule ApiWeb.HealthJSON do
  @moduledoc """
  Renders the health probe.

  The failure body carries both the probe fields and the standard error
  envelope: an orchestrator reads `database` without knowing this API's
  conventions, while a client's single error handler still finds `errors.code`.
  """

  @spec ok(map()) :: map()
  def ok(_assigns), do: %{status: "ok", database: "up"}

  @spec error(map()) :: map()
  def error(_assigns) do
    {code, detail} = ApiWeb.ErrorJSON.error_for(503)

    %{status: "error", database: "down", errors: %{code: code, detail: detail}}
  end
end
