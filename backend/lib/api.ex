defmodule Api do
  @moduledoc """
  Api keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.

  This module is also the root of the `Api` boundary. It declares no
  dependencies, which is what makes the dependency rule one-way: `ApiWeb`
  may call into `Api`, and `mix compile` fails on the reverse. Each context
  added by a later feature exports its public interface here.
  """

  use Boundary, deps: [], exports: [Health, Repo]
end
