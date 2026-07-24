defmodule ApiWeb.Params do
  @moduledoc """
  Validates and normalises HTTP transport parameters through a schemaless
  changeset.

  Every controller that reads a body or a query string shares the same steps —
  cast the raw params into a typed map, optionally trim and require fields, run
  any extra check, and apply — so the shape lives here and each action declares
  only its `types` and a few options. Returns `{:ok, atom-keyed map}` or the
  changeset the fallback controller renders as a 422 under `fields`.

  Options:

    * `:required` — fields that must be present (default: all keys of `types`)
    * `:required_message` — message for the required check
    * `:trim` — fields to `String.trim/1` before the required check
    * `:defaults` — a map of default values seeded before the cast
    * `:message` — a cast error message, or `(field, meta -> message | nil)`
    * `:validate` — a `changeset -> changeset` callback for extra validations
  """

  alias Ecto.Changeset

  @spec validate(map(), map(), keyword()) :: {:ok, map()} | {:error, Changeset.t()}
  def validate(params, types, opts \\ []) do
    defaults = Keyword.get(opts, :defaults, %{})
    required = Keyword.get(opts, :required, Map.keys(types))

    {defaults, types}
    |> Changeset.cast(params, Map.keys(types), Keyword.take(opts, [:message]))
    |> trim_fields(Keyword.get(opts, :trim, []))
    |> require_fields(required, Keyword.get(opts, :required_message))
    |> run_extra(Keyword.get(opts, :validate))
    |> Changeset.apply_action(:insert)
  end

  defp trim_fields(changeset, fields),
    do:
      Enum.reduce(fields, changeset, &Changeset.update_change(&2, &1, fn v -> String.trim(v) end))

  defp require_fields(changeset, fields, nil),
    do: Changeset.validate_required(changeset, fields)

  defp require_fields(changeset, fields, message),
    do: Changeset.validate_required(changeset, fields, message: message)

  defp run_extra(changeset, nil), do: changeset
  defp run_extra(changeset, fun) when is_function(fun, 1), do: fun.(changeset)
end
