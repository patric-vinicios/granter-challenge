defmodule Api do
  @moduledoc """
  Root of the `Api` boundary — the domain contexts and the data they own.

  It declares no dependencies, which is what makes the rule one-way: `ApiWeb`
  may call into `Api`, and `mix compile` fails on the reverse. Each context
  exports its public interface through the `exports` list below.
  """

  use Boundary,
    deps: [],
    exports: [
      {Accounts, []},
      {Contacts, []},
      {Conversations, []},
      {Messages, []},
      {Seeds, []},
      Changeset,
      Cursor,
      Health,
      Repo,
      Schema,
      TokenRevocation,
      UUID
    ]
end
