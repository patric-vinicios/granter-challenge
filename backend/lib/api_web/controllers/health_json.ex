defmodule ApiWeb.HealthJSON do
  @moduledoc """
  Renders the health probe.

  The failure body carries both the probe fields and the standard error
  envelope: a container orchestrator reads `database` without knowing anything
  about this API's conventions, while the SPA's single error handler still
  finds `errors.code`.
  """

  def ok(_assigns), do: %{status: "ok", database: "up"}

  def error(_assigns) do
    {code, detail} = ApiWeb.ErrorJSON.error_for(503)

    %{status: "error", database: "down", errors: %{code: code, detail: detail}}
  end
end
