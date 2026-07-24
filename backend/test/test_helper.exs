# The volume suite seeds tens of thousands of rows and takes about forty
# seconds, which is the wrong price for the gate that runs on every change. It
# is excluded by default and run deliberately: `mix test --include volume`.
ExUnit.start(exclude: [:volume])
Ecto.Adapters.SQL.Sandbox.mode(Api.Repo, :manual)
