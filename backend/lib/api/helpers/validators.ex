defmodule Api.Helpers.Validators do
  @moduledoc """
  Common validation helpers for Ecto changesets.
  """

  @spec cast_uuids(ids :: list(String.t())) ::
          {:ok, list(Ecto.UUID.t())} | {:error, reason :: String.t()}
  def cast_uuids(ids) when is_list(ids) do
    result = Enum.map(ids, &Ecto.UUID.cast/1)

    case Enum.member?(result, :error) do
      true -> {:error, "Invalid UUID"}
      false -> {:ok, ids}
    end
  end

  @doc """
  Receive a string and validates if it is a UUID
  """
  @spec cast_uuid(id :: String.t()) ::
          {:ok, uuid :: Ecto.UUID.t()} | {:error, reason :: String.t()}
  def cast_uuid(id) do
    case Ecto.UUID.cast(id) do
      :error -> {:error, "Invalid UUID"}
      {:ok, uuid} -> {:ok, uuid}
    end
  end
end
