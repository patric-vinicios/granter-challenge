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

    ApiWeb.Params.validate(params, types,
      defaults: %{limit: default},
      required: [],
      message: &cast_message(&1, &2, message),
      validate:
        &Changeset.validate_number(&1, :limit,
          greater_than_or_equal_to: 1,
          less_than_or_equal_to: max,
          message: message
        )
    )
  end

  defp cast_message(:limit, _meta, message), do: message
  defp cast_message(_field, _meta, _message), do: nil

  @doc """
  Lifts a context list result into an ok/error tuple for a controller `with`.

  `Api.Contacts.list_contacts/2` and `Api.Conversations.list_conversations/2`
  return a plain page map on success and `{:error, reason}` on a bad cursor;
  this normalizes the success case to `{:ok, page}` so an action can chain it.

  ## Parameters

    * `result` — a page map, or `{:error, reason}`

  ## Examples

      iex> ApiWeb.Pagination.ok_or_error(%{contacts: [], has_more: false})
      {:ok, %{contacts: [], has_more: false}}

      iex> ApiWeb.Pagination.ok_or_error({:error, :invalid_cursor})
      {:error, :invalid_cursor}
  """
  @spec ok_or_error(map() | {:error, term()}) :: {:ok, map()} | {:error, term()}
  def ok_or_error({:error, reason}), do: {:error, reason}
  def ok_or_error(page), do: {:ok, page}
end
