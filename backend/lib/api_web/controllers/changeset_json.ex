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
  def error(%{changeset: changeset}) do
    {code, detail} = ApiWeb.ErrorJSON.error_for(422)

    %{errors: %{code: code, detail: detail, fields: translate_errors(changeset)}}
  end

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _whole, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
