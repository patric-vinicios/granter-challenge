defmodule Api.UUID do
  @moduledoc """
  Casts an externally supplied identifier to a UUID, with a tagged error.

  Path params, token subjects and channel topic segments all arrive as untrusted
  strings, so every context that scopes a query by id needs the same first step:
  turn a value that cannot name a row into `{:error, :invalid_id}` rather than a
  raised cast exception. Keeping that one step here means the contexts, the
  channel and the seeds share a single notion of what a malformed id is.
  """

  @spec cast(term()) :: {:ok, Ecto.UUID.t()} | {:error, :invalid_id}
  def cast(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :invalid_id}
    end
  end
end
