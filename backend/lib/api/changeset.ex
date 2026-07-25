defmodule Api.Changeset do
  @moduledoc """
  Shared changeset helpers.

  `errors/1` resolves a changeset's errors into `%{field => [message]}` with
  interpolation placeholders substituted. The 422 renderer and the seed script
  both need the resolved messages, so the traversal lives here rather than being
  reimplemented on each side.
  """

  @doc """
  Resolves `changeset`'s errors into `%{field => [message]}`.

  ## Parameters

    * `changeset` — the invalid changeset whose errors are rendered

  Each message's interpolation placeholders (`%{count}`) are substituted from
  its own options. A placeholder whose key is absent from the options is left as
  its bare name rather than dropped.

  ## Examples

      iex> Api.Changeset.errors(changeset)
      %{password: ["should be at least 8 character(s)"]}
  """
  @spec errors(Ecto.Changeset.t()) :: %{atom() => [String.t()]}
  def errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _whole, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
