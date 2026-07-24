defmodule ApiWeb.Pagination do
  @moduledoc """
  The page parameters every paginated endpoint validates the same way.

  Three lists page — message history, the conversation inbox and the contact
  list — and each one has to reject a non-numeric or out-of-range `limit` before
  the domain call, so a bad page size is a 422 naming the field rather than a
  value the context silently clamps. What differs between them is the accepted
  range and the name of the cursor parameter; the cast, the range check and the
  sentence a client reads off the failure do not.

  The message is the same for both failure modes on purpose. A non-numeric limit
  fails the cast and an out-of-range one the numeric bound, and a client that
  reads the accepted range off either failure never has to guess the cap.
  """

  alias Ecto.Changeset

  @doc """
  Casts `params` against `types`, defaulting and bounding `:limit`.

  Returns the accepted parameters as a map with atom keys, or the changeset the
  fallback controller renders as a 422 under `fields`.
  """
  @spec validate(map(), map(), keyword()) :: {:ok, map()} | {:error, Changeset.t()}
  def validate(params, types, opts) do
    default = Keyword.fetch!(opts, :default_limit)
    max = Keyword.fetch!(opts, :max_limit)
    message = "must be between 1 and #{max}"

    {%{limit: default}, types}
    |> Changeset.cast(params, Map.keys(types), message: &cast_message(&1, &2, message))
    |> Changeset.validate_number(:limit,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: max,
      message: message
    )
    |> Changeset.apply_action(:insert)
  end

  defp cast_message(:limit, _meta, message), do: message
  defp cast_message(_field, _meta, _message), do: nil
end
