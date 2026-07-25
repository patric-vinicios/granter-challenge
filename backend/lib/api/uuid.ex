defmodule Api.UUID do
  @moduledoc """
  Casts an externally supplied identifier to a UUID.

  Path params, token subjects and channel topic segments all arrive as untrusted
  strings. Every context that scopes a query by id shares the same first step:
  turn a value that cannot name a row into `{:error, :invalid_id}` rather than a
  raised cast exception. Centralizing it gives the contexts, the channels and
  the seeds a single notion of a malformed id.
  """

  @doc """
  Casts `id` to a UUID.

  ## Parameters

    * `id` — an untrusted identifier, usually a string

  Returns `{:ok, uuid}` for a well-formed value and `{:error, :invalid_id}` for
  anything else.

  ## Examples

      iex> Api.UUID.cast("2b8c9f1e-3d4a-4b5c-8d6e-7f0a1b2c3d4e")
      {:ok, "2b8c9f1e-3d4a-4b5c-8d6e-7f0a1b2c3d4e"}

      iex> Api.UUID.cast("not-a-uuid")
      {:error, :invalid_id}
  """
  @spec cast(term()) :: {:ok, Ecto.UUID.t()} | {:error, :invalid_id}
  def cast(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :invalid_id}
    end
  end
end
