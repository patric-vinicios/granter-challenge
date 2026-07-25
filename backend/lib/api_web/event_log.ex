defmodule ApiWeb.EventLog do
  @moduledoc """
  The events this API logs on purpose, and the level each one is worth.

  Phoenix already logs every request and Ecto every query, so this module is
  deliberately narrow: it holds the events those two cannot express — who
  authenticated, which credential was refused, when a limiter engaged, and when
  the database stopped answering. Routing them through one module is what keeps
  the level scheme honest (a wrong password is routine, a throttle tripping is
  not) and the field names stable enough to alert on.

  Every line is `event=<name>` followed by `key=value` pairs, so a log search
  needs no parser, and each function takes only ids, usernames, addresses and
  reasons. **No token, password or hash is accepted by any function here**, which
  is the property that makes the whole log safe to ship to an aggregator.

  `user_id` also goes into `Logger.metadata/1` from
  `ApiWeb.Plugs.AssignCurrentUser`, so every line a request emits carries the
  actor alongside the `request_id` — the pair a production incident is traced
  with.
  """

  require Logger

  @doc """
  A successful login, as the audit counterpart to the failures below.

  ## Parameters

    * `user_id` — the account that authenticated

  ## Examples

      iex> ApiWeb.EventLog.login_succeeded("0e8f…")
      :ok
  """
  @spec login_succeeded(String.t()) :: :ok
  def login_succeeded(user_id), do: emit(:info, "login_succeeded", user_id: user_id)

  @doc """
  A rejected password.

  Logged at `:info`, not `:warning`: one wrong password is ordinary user error,
  and treating it as a warning would train everyone to ignore warnings. The
  attack signal is `login_throttled/3` below.

  ## Parameters

    * `ip` — the client address, as `conn.remote_ip`
    * `username` — the normalized `@username` that was attempted

  ## Examples

      iex> ApiWeb.EventLog.login_failed({127, 0, 0, 1}, "anabeatriz")
      :ok
  """
  @spec login_failed(term(), String.t()) :: :ok
  def login_failed(ip, username) do
    emit(:info, "login_failed", username: username, ip: format_ip(ip))
  end

  @doc """
  The login ceiling engaging, which means a burst of failures preceded it.

  ## Parameters

    * `ip` — the client address
    * `username` — the normalized `@username` that was attempted
    * `retry_after` — seconds until the window rolls over

  ## Examples

      iex> ApiWeb.EventLog.login_throttled({127, 0, 0, 1}, "anabeatriz", 42)
      :ok
  """
  @spec login_throttled(term(), String.t(), pos_integer()) :: :ok
  def login_throttled(ip, username, retry_after) do
    emit(:warning, "login_throttled",
      username: username,
      ip: format_ip(ip),
      retry_after_s: retry_after
    )
  end

  @doc """
  An account being created.

  ## Parameters

    * `user_id` — the new account
    * `username` — its normalized `@username`

  ## Examples

      iex> ApiWeb.EventLog.account_registered("0e8f…", "anabeatriz")
      :ok
  """
  @spec account_registered(String.t(), String.t()) :: :ok
  def account_registered(user_id, username) do
    emit(:info, "account_registered", user_id: user_id, username: username)
  end

  @doc """
  A token being revoked by its owner.

  ## Parameters

    * `user_id` — the account that logged out

  ## Examples

      iex> ApiWeb.EventLog.logged_out("0e8f…")
      :ok
  """
  @spec logged_out(String.t()) :: :ok
  def logged_out(user_id), do: emit(:info, "logged_out", user_id: user_id)

  @doc """
  A token the pipeline refused, with the reason that produced the 401.

  The request log already shows the status; the reason is what distinguishes a
  client that must re-login from one that is sending a malformed header.

  ## Parameters

    * `reason` — the domain reason, such as `:token_expired`

  ## Examples

      iex> ApiWeb.EventLog.token_rejected(:token_expired)
      :ok
  """
  @spec token_rejected(atom()) :: :ok
  def token_rejected(reason), do: emit(:info, "token_rejected", reason: reason)

  @doc """
  A refused socket handshake.

  A warning, unlike a refused HTTP token: a browser that reaches the socket has
  already authenticated over HTTP, so a failure here is a broken client or a
  probe rather than an expired session.

  ## Parameters

    * `reason` — `:invalid_token` or `:no_token`

  ## Examples

      iex> ApiWeb.EventLog.socket_rejected(:no_token)
      :ok
  """
  @spec socket_rejected(atom()) :: :ok
  def socket_rejected(reason), do: emit(:warning, "socket_rejected", reason: reason)

  @doc """
  The per-user message ceiling engaging on the socket.

  ## Parameters

    * `user_id` — the account being limited
    * `retry_after_ms` — milliseconds until the next message is accepted

  ## Examples

      iex> ApiWeb.EventLog.message_rate_limited("0e8f…", 250)
      :ok
  """
  @spec message_rate_limited(String.t(), non_neg_integer()) :: :ok
  def message_rate_limited(user_id, retry_after_ms) do
    emit(:warning, "message_rate_limited", user_id: user_id, retry_after_ms: retry_after_ms)
  end

  @doc """
  The health probe failing, which is an outage rather than a request error.

  ## Parameters

    * `reason` — whatever the probe returned, inspected into the line

  ## Examples

      iex> ApiWeb.EventLog.database_unavailable(:timeout)
      :ok
  """
  @spec database_unavailable(term()) :: :ok
  def database_unavailable(reason) do
    emit(:error, "database_unavailable", reason: inspect(reason))
  end

  @doc """
  What the endpoint came up with, logged once at boot.

  The CORS allowlist is here because it is the deploy setting most likely to be
  wrong, and the failure it causes — a browser refusing every response — leaves
  nothing in the log to explain itself.

  ## Parameters

    * `env` — the compiled environment
    * `origins` — the effective CORS allowlist

  ## Examples

      iex> ApiWeb.EventLog.boot(:prod, ["https://app.example.com"])
      :ok
  """
  @spec boot(atom(), [String.t()]) :: :ok
  def boot(env, origins) do
    emit(:info, "boot", env: env, cors_origins: Enum.join(origins, ","))
  end

  defp emit(level, event, fields) do
    Logger.log(level, fn ->
      Enum.map_join([{:event, event} | fields], " ", fn {key, value} -> "#{key}=#{value}" end)
    end)
  end

  defp format_ip(ip) when is_tuple(ip) do
    case :inet.ntoa(ip) do
      {:error, _reason} -> inspect(ip)
      address -> to_string(address)
    end
  end

  defp format_ip(ip), do: inspect(ip)
end
