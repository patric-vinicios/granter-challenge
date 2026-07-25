defmodule ApiWeb.Plugs.AssignCurrentUser do
  @moduledoc """
  Copies the resource Guardian loaded into `conn.assigns.current_user`.

  Every authenticated controller reads that one assign and never mentions
  Guardian, so replacing the token library later touches this pipeline instead
  of every action in the API.

  It is also where `user_id` enters `Logger.metadata/1`. Every line the request
  logs from here on carries it next to the `request_id`, which is what turns a
  report of "my messages stopped arriving" into a single log filter.
  """

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    user = Guardian.Plug.current_resource(conn)

    if user, do: Logger.metadata(user_id: user.id)

    Plug.Conn.assign(conn, :current_user, user)
  end
end
