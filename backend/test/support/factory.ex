defmodule Api.Factory do
  @moduledoc """
  Test data builder, imported by `Api.DataCase`, `ApiWeb.ConnCase` and
  `ApiWeb.ChannelCase`.

  The convention is one factory function per schema, added alongside the
  schema itself (`user_factory/0` next to the user schema, and so on). No
  factory is defined yet because no domain schema exists yet.

  Conventions:

    * `build(:user)` returns an unsaved struct, `insert(:user)` persists one.
      Prefer `build/1` when the test never reads the record back.
    * Override any field inline: `insert(:user, name: "Ada")`.
    * Use `sequence/2` for values with a uniqueness constraint, so a test that
      inserts several records never collides:
      `username: sequence(:username, &"user\#{&1}")`.
    * `params_for(:user)` produces a plain map for controller request bodies.
  """

  use ExMachina.Ecto, repo: Api.Repo
  use Boundary, top_level?: true, check: [in: false, out: false]
end
