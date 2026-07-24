defmodule ApiWeb.ChangesetJSON do
  @moduledoc """
  Renders a failed changeset as the 422 form of the error envelope.

  Keeping this in one place is what lets a client write a single handler that
  reads `errors.fields` to highlight inputs, whichever endpoint rejected the
  request.
  """

  @doc """
  Builds the envelope for `{:error, changeset}`, with one entry per invalid
  field. Interpolation options are substituted into the message, so
  `should be at least %{count} character(s)` reaches the client resolved.
  """
  @spec error(%{changeset: Ecto.Changeset.t()}) :: map()
  def error(%{changeset: changeset}) do
    {code, detail} = ApiWeb.ErrorJSON.error_for(422)

    %{errors: %{code: code, detail: detail, fields: fields(changeset)}}
  end

  @doc """
  The per-field error map, one list of resolved messages per invalid field.

  Public because the channel's `validation_error` reply carries the same
  `fields` shape the 422 envelope does, so both surfaces translate a rejected
  changeset through one function rather than drifting apart.
  """
  @spec fields(Ecto.Changeset.t()) :: map()
  def fields(changeset), do: Api.Changeset.errors(changeset)
end
