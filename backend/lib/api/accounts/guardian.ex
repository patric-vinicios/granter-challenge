defmodule Api.Accounts.Guardian do
  @moduledoc """
  Token issuance and verification.

  One token authenticates both surfaces of the API: the `Authorization: Bearer`
  header on every HTTP request and the socket connect param the real-time layer
  reads, so a client manages a single credential and this module is the only
  place that knows how it is signed.
  """

  use Guardian, otp_app: :api

  alias Api.Accounts

  @doc """
  Issues a token for a user along with the moment it stops being valid.

  The expiry is read back from the signed claims rather than recomputed, so the
  `expires_at` a client stores can never disagree with the `exp` the server
  will enforce.
  """
  @spec issue_token(Accounts.User.t()) ::
          {:ok, String.t(), DateTime.t()} | {:error, atom() | term()}
  def issue_token(user) do
    with {:ok, token, %{"exp" => exp}} <- __MODULE__.encode_and_sign(user),
         {:ok, expires_at} <- DateTime.from_unix(exp) do
      {:ok, token, expires_at}
    end
  end

  @impl Guardian
  def subject_for_token(%Accounts.User{id: id}, _claims), do: {:ok, id}
  def subject_for_token(_resource, _claims), do: {:error, :invalid_resource}

  @impl Guardian
  def resource_from_claims(%{"sub" => id}) do
    case Accounts.get_user(id) do
      nil -> {:error, :resource_not_found}
      user -> {:ok, user}
    end
  end

  def resource_from_claims(_claims), do: {:error, :invalid_claims}

  # Rejects a token whose jti was revoked at logout, on both the HTTP pipeline
  # and the socket, since every verification path runs through here.
  @impl Guardian
  def verify_claims(claims, _opts) do
    if Api.TokenRevocation.revoked?(claims["jti"]),
      do: {:error, :token_revoked},
      else: {:ok, claims}
  end
end
