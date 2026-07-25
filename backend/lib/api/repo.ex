defmodule Api.Repo do
  @moduledoc """
  The Ecto repository — the single gateway to PostgreSQL for the application.

  Every context runs its queries through this module; nothing else opens a
  database connection.
  """

  use Ecto.Repo,
    otp_app: :api,
    adapter: Ecto.Adapters.Postgres
end
