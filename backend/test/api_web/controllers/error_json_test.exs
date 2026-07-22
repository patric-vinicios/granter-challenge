defmodule ApiWeb.ErrorJSONTest do
  use ExUnit.Case, async: true

  alias ApiWeb.ErrorJSON

  describe "render/2" do
    test "renders the envelope for every status F01 owns" do
      assert ErrorJSON.render("400.json", %{}) ==
               %{
                 errors: %{
                   code: "malformed_request",
                   detail: "The request body is not valid JSON"
                 }
               }

      assert ErrorJSON.render("404.json", %{}) ==
               %{
                 errors: %{code: "not_found", detail: "The requested resource was not found"}
               }

      assert ErrorJSON.render("405.json", %{}) ==
               %{
                 errors: %{
                   code: "method_not_allowed",
                   detail: "This method is not supported for this path"
                 }
               }

      assert ErrorJSON.render("415.json", %{}) ==
               %{
                 errors: %{
                   code: "unsupported_media_type",
                   detail: "The request content-type must be application/json"
                 }
               }

      assert ErrorJSON.render("503.json", %{}) ==
               %{
                 errors: %{
                   code: "database_unavailable",
                   detail: "Database connection is not available"
                 }
               }
    end

    test "every rendered error carries a non-empty code and detail, and no fields key" do
      for status <- [400, 401, 403, 404, 405, 409, 415, 422, 429, 500, 503] do
        assert %{errors: %{code: <<_, _::binary>>, detail: <<_, _::binary>>} = errors} =
                 ErrorJSON.render("#{status}.json", %{})

        refute Map.has_key?(errors, :fields)
      end
    end

    test "an unknown status falls back to internal_error rather than raising" do
      assert ErrorJSON.render("418.json", %{}) ==
               %{errors: %{code: "internal_error", detail: "Something went wrong"}}

      assert ErrorJSON.render("oops.json", %{}) ==
               %{errors: %{code: "internal_error", detail: "Something went wrong"}}
    end

    test "a 500 never leaks the exception behind it" do
      assigns = %{reason: %RuntimeError{message: "postgres://user:hunter2@db/secret exploded"}}

      assert %{errors: errors} = ErrorJSON.render("500.json", assigns)
      assert errors == %{code: "internal_error", detail: "Something went wrong"}
      refute errors.detail =~ "hunter2"
    end

    test "a parse error is reported as a malformed body, not as the parser's message" do
      assigns = %{reason: %Plug.Parsers.ParseError{exception: %RuntimeError{message: "boom"}}}

      assert ErrorJSON.render("400.json", assigns) ==
               %{
                 errors: %{
                   code: "malformed_request",
                   detail: "The request body is not valid JSON"
                 }
               }
    end

    test "an unsupported media type reports the accepted content type" do
      assigns = %{
        reason: %Plug.Parsers.UnsupportedMediaTypeError{media_type: "text/plain"}
      }

      assert ErrorJSON.render("415.json", assigns) ==
               %{
                 errors: %{
                   code: "unsupported_media_type",
                   detail: "The request content-type must be application/json"
                 }
               }
    end
  end

  describe "error_for/1" do
    test "exposes the shared table so other renderers do not restate it" do
      assert ErrorJSON.error_for(422) ==
               {"validation_error", "The request could not be processed"}

      assert ErrorJSON.error_for(503) ==
               {"database_unavailable", "Database connection is not available"}
    end
  end
end
