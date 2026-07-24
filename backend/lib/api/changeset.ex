defmodule Api.Changeset do
  @moduledoc """
  Shared changeset helpers.

  `errors/1` folds a changeset's errors into a map of `field => [message]`, with
  each message's interpolation placeholders (`%{count}`) substituted from its
  own options. The 422 renderer and the seed script both need the resolved
  messages, so the traversal lives here rather than being reimplemented — and
  slightly differently — on each side.
  """

  @doc """
  Resolves `changeset`'s errors into `%{field => [message]}` with placeholders
  substituted. A placeholder whose key is absent from the options is left as its
  bare name rather than dropped.
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
