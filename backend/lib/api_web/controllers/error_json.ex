defmodule ApiWeb.ErrorJSON do
  @moduledoc """
  Renders the error envelope for failures the endpoint handles on its own:
  unmatched routes, unparseable bodies and unhandled exceptions.

  This module owns the status-to-code table for the whole API. Failures raised
  inside a controller action travel through `ApiWeb.FallbackController`, which
  renders back through here, so a given status always answers with the same
  `code` no matter which layer produced it.
  """

  @errors %{
    400 => {"malformed_request", "The request body is not valid JSON"},
    401 => {"unauthenticated", "Authentication is required"},
    403 => {"forbidden", "You are not allowed to perform this action"},
    404 => {"not_found", "The requested resource was not found"},
    405 => {"method_not_allowed", "This method is not supported for this path"},
    409 => {"conflict", "The request conflicts with the current state"},
    413 => {"payload_too_large", "The request body is too large"},
    415 => {"unsupported_media_type", "The request content-type must be application/json"},
    422 => {"validation_error", "The request could not be processed"},
    429 => {"rate_limited", "Too many requests, please retry later"},
    500 => {"internal_error", "Something went wrong"},
    503 => {"database_unavailable", "Database connection is not available"}
  }

  @fallback {"internal_error", "Something went wrong"}

  @doc """
  Returns the `{code, detail}` pair for an HTTP status, so other renderers do
  not restate the table.
  """
  @spec error_for(integer()) :: {String.t(), String.t()}
  def error_for(status) when is_integer(status), do: Map.get(@errors, status, @fallback)

  @spec render(atom() | String.t(), map()) :: map()
  def render(template, assigns) do
    {code, detail} =
      template
      |> status_from_template()
      |> error_for()

    %{errors: %{code: code, detail: detail(assigns, detail)}}
  end

  defp detail(%{reason: %Plug.Parsers.ParseError{}}, _default),
    do: "The request body is not valid JSON"

  defp detail(%{reason: %Plug.Parsers.UnsupportedMediaTypeError{}}, _default),
    do: "The request content-type must be application/json"

  # Any other exception may carry internals in its message, so only the
  # table's generic detail is sent and the exception is left to the logger.
  defp detail(_assigns, default), do: default

  defp status_from_template(template) do
    template
    |> to_string()
    |> String.split(".")
    |> hd()
    |> Integer.parse()
    |> case do
      {status, _rest} -> status
      :error -> 500
    end
  end
end
