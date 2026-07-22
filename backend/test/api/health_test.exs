defmodule Api.HealthTest do
  use Api.DataCase, async: true

  alias Api.Health

  describe "check/0" do
    test "returns :ok when the database answers" do
      assert Health.check() == :ok
    end

    @tag :capture_log
    test "returns an error tuple instead of raising when the database is unreachable" do
      repo =
        start_supervised!(
          {Api.Repo,
           name: :unreachable_repo,
           hostname: "localhost",
           port: 1,
           username: "postgres",
           password: "postgres",
           database: "api_dev",
           pool_size: 1,
           queue_target: 50,
           queue_interval: 100}
        )

      assert {:error, _reason} = Health.check(:unreachable_repo)
      assert Process.alive?(repo)
    end
  end
end
