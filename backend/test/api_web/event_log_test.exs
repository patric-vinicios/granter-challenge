defmodule ApiWeb.EventLogTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias ApiWeb.EventLog

  setup do
    level = Logger.level()
    Logger.configure(level: :debug)
    on_exit(fn -> Logger.configure(level: level) end)
  end

  describe "levels" do
    test "a rejected password is info, not warning" do
      log = capture_log(fn -> EventLog.login_failed({127, 0, 0, 1}, "anabeatriz") end)

      assert log =~ "[info]"
      assert log =~ "event=login_failed username=anabeatriz ip=127.0.0.1"
    end

    test "the throttle engaging is a warning" do
      log = capture_log(fn -> EventLog.login_throttled({127, 0, 0, 1}, "anabeatriz", 42) end)

      assert log =~ "[warning]"
      assert log =~ "event=login_throttled username=anabeatriz ip=127.0.0.1 retry_after_s=42"
    end

    test "a refused socket handshake is a warning" do
      log = capture_log(fn -> EventLog.socket_rejected(:no_token) end)

      assert log =~ "[warning]"
      assert log =~ "event=socket_rejected reason=no_token"
    end

    test "a message ceiling engaging is a warning" do
      log = capture_log(fn -> EventLog.message_rate_limited("user-1", 250) end)

      assert log =~ "[warning]"
      assert log =~ "event=message_rate_limited user_id=user-1 retry_after_ms=250"
    end

    test "an unreachable database is an error" do
      log = capture_log(fn -> EventLog.database_unavailable(:timeout) end)

      assert log =~ "[error]"
      assert log =~ "event=database_unavailable reason=:timeout"
    end

    test "the audit trail of a session is info" do
      log =
        capture_log(fn ->
          EventLog.account_registered("user-1", "anabeatriz")
          EventLog.login_succeeded("user-1")
          EventLog.logged_out("user-1")
          EventLog.token_rejected(:token_expired)
        end)

      assert log =~ "event=account_registered user_id=user-1 username=anabeatriz"
      assert log =~ "event=login_succeeded user_id=user-1"
      assert log =~ "event=logged_out user_id=user-1"
      assert log =~ "event=token_rejected reason=token_expired"
      refute log =~ "[warning]"
      refute log =~ "[error]"
    end

    test "boot names the environment and the effective allowlist" do
      log =
        capture_log(fn -> EventLog.boot(:prod, ["https://a.example", "https://b.example"]) end)

      assert log =~ "event=boot env=prod cors_origins=https://a.example,https://b.example"
    end
  end

  describe "address formatting" do
    test "renders IPv4 and IPv6 in their usual notation" do
      assert capture_log(fn -> EventLog.login_failed({192, 168, 1, 10}, "ana") end) =~
               "ip=192.168.1.10"

      assert capture_log(fn -> EventLog.login_failed({0, 0, 0, 0, 0, 0, 0, 1}, "ana") end) =~
               "ip=::1"
    end

    test "falls back to inspect for anything that is not an address" do
      assert capture_log(fn -> EventLog.login_failed(:unknown, "ana") end) =~ "ip=:unknown"
      assert capture_log(fn -> EventLog.login_failed({1, 2}, "ana") end) =~ "ip={1, 2}"
    end
  end

  describe "level filtering" do
    test "emits nothing when the level is disabled" do
      Logger.configure(level: :error)

      assert capture_log(fn -> EventLog.login_failed({127, 0, 0, 1}, "anabeatriz") end) == ""
    end
  end
end
