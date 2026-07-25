defmodule ApiWeb.UserSocketTest do
  use ApiWeb.ChannelCase, async: false

  import ExUnit.CaptureLog

  alias Api.Accounts.Guardian
  alias Api.Repo
  alias ApiWeb.UserSocket

  @moduletag :capture_log

  defp token_for(user) do
    {:ok, token, _expires_at} = Guardian.issue_token(user)
    token
  end

  test "connects with a valid token" do
    user = insert(:user)

    assert {:ok, socket} = connect(UserSocket, %{"token" => token_for(user)})
    assert socket.assigns.current_user_id == user.id
    assert socket.assigns.current_user.id == user.id
  end

  test "rejects a missing token" do
    assert :error = connect(UserSocket, %{})
  end

  test "rejects a malformed token" do
    assert :error = connect(UserSocket, %{"token" => "not-a-jwt"})
  end

  test "rejects an expired token" do
    user = insert(:user)
    {:ok, token, _claims} = Guardian.encode_and_sign(user, %{}, ttl: {-1, :hour})

    assert :error = connect(UserSocket, %{"token" => token})
  end

  test "rejects a token whose subject no longer exists" do
    user = insert(:user)
    token = token_for(user)
    Repo.delete!(user)

    assert :error = connect(UserSocket, %{"token" => token})
  end

  test "rejects a token revoked at logout" do
    token = token_for(insert(:user))
    {:ok, claims} = Guardian.decode_and_verify(token)
    Api.TokenRevocation.revoke(claims["jti"], claims["exp"])

    assert :error = connect(UserSocket, %{"token" => token})
  end

  test "assigns a per-user socket id" do
    user = insert(:user)
    {:ok, socket} = connect(UserSocket, %{"token" => token_for(user)})

    assert UserSocket.id(socket) == "user_socket:#{user.id}"
  end

  test "a refused handshake yields no socket to reach a channel through" do
    assert :error = connect(UserSocket, %{"token" => "not-a-jwt"})
  end

  test "a refused handshake is logged as a warning, with the reason" do
    missing = capture_log(fn -> assert :error = connect(UserSocket, %{}) end)
    invalid = capture_log(fn -> assert :error = connect(UserSocket, %{"token" => "nope"}) end)

    assert missing =~ "[warning]"
    assert missing =~ "event=socket_rejected reason=no_token"
    assert invalid =~ "event=socket_rejected reason=invalid_token"
    refute invalid =~ "nope"
  end
end
