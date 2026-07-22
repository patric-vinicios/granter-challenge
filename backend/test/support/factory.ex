defmodule Api.Factory do
  @moduledoc """
  Test data builder, imported by `Api.DataCase`, `ApiWeb.ConnCase` and
  `ApiWeb.ChannelCase`.

  The convention is one factory function per schema, added alongside the
  schema itself (`user_factory/0` next to the user schema, and so on).

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

  @valid_password "senha123456"
  # Hashed once for the whole suite rather than per record: hashing is
  # deliberately slow, and a factory that paid it per insert would dominate
  # the wall clock of every test that needs a user.
  @hashed_password Argon2.hash_pwd_salt(@valid_password)

  @doc """
  The plaintext behind every factory-built user, so a login test can
  authenticate one without registering it through the context first.
  """
  def valid_password, do: @valid_password

  def user_factory do
    %Api.Accounts.User{
      username: sequence(:username, &"user#{&1}"),
      name: sequence(:name, &"Test User #{&1}"),
      hashed_password: @hashed_password,
      last_seen_at: nil
    }
  end
end
