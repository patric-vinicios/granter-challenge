defmodule ApiWeb.Accounts.LoginThrottleTest do
  # async: false — this test lowers the global throttle config, so it must not
  # run alongside other login tests. Each test also uses distinct IPs and
  # usernames so counts never collide with another's window.
  use ApiWeb.ConnCase, async: false

  setup do
    original = Application.get_env(:api, ApiWeb.LoginThrottle)

    Application.put_env(:api, ApiWeb.LoginThrottle,
      ip_limit: 3,
      user_limit: 2,
      window_ms: 60_000
    )

    on_exit(fn -> Application.put_env(:api, ApiWeb.LoginThrottle, original) end)
    :ok
  end

  defp from(conn, d), do: %{conn | remote_ip: {10, 9, 0, d}}

  defp bad_login(conn, username) do
    post(conn, ~p"/api/auth/login", %{"username" => username, "password" => "wrong-pass!!"})
  end

  test "returns 429 with Retry-After once one IP fails too many times", %{conn: conn} do
    conn = from(conn, 1)

    # ip_limit is 3, and each attempt uses a different username so only the IP
    # counter accumulates: three failures are 401, the fourth is throttled.
    for i <- 1..3, do: assert(json_response(bad_login(conn, "ip_user_#{i}"), 401))

    throttled = bad_login(conn, "ip_user_final")
    assert json_response(throttled, 429)["errors"]["code"] == "rate_limited"
    assert [retry] = get_resp_header(throttled, "retry-after")
    assert String.to_integer(retry) in 1..60
  end

  test "returns 429 once one username fails too many times, from any IP", %{conn: conn} do
    # user_limit is 2, from a fresh address each time so the IP counter never
    # trips first: the third attempt for the username is throttled.
    assert json_response(bad_login(from(conn, 2), "target_user"), 401)
    assert json_response(bad_login(from(conn, 3), "target_user"), 401)

    throttled = bad_login(from(conn, 4), "target_user")
    assert json_response(throttled, 429)["errors"]["code"] == "rate_limited"
  end

  test "a successful login is not throttled by an earlier failure", %{conn: conn} do
    insert(:user, username: "realuser")
    conn = from(conn, 5)

    assert json_response(bad_login(conn, "realuser"), 401)

    ok =
      post(conn, ~p"/api/auth/login", %{"username" => "realuser", "password" => valid_password()})

    assert json_response(ok, 200)["token"]
  end
end
