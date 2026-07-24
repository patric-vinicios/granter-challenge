defmodule ApiWeb.ChangesetJSONTest do
  use ExUnit.Case, async: true

  alias ApiWeb.ChangesetJSON
  alias Ecto.Changeset

  defmodule Sample do
    use Api.Schema

    schema "samples" do
      field :username, :string
      field :password, :string
      field :age, :integer
    end
  end

  defp changeset(params) do
    Sample
    |> struct!()
    |> Changeset.cast(params, [:username, :password, :age])
    |> Changeset.validate_required([:username])
    |> Changeset.validate_length(:password, min: 8)
    |> Changeset.validate_number(:age, greater_than: 0)
  end

  describe "error/1" do
    test "renders the 422 envelope with one entry per invalid field" do
      assert %{errors: errors} =
               ChangesetJSON.error(%{changeset: changeset(%{password: "short"})})

      assert errors.code == "validation_error"
      assert errors.detail == "The request could not be processed"
      assert errors.fields.username == ["can't be blank"]
    end

    test "interpolates the message options so the client gets a finished sentence" do
      %{errors: errors} = ChangesetJSON.error(%{changeset: changeset(%{password: "short"})})

      assert errors.fields.password == ["should be at least 8 character(s)"]
      refute Enum.any?(errors.fields.password, &(&1 =~ "%{count}"))
    end

    test "collects several fields at once so a form can highlight all of them" do
      %{errors: errors} =
        ChangesetJSON.error(%{changeset: changeset(%{password: "short", age: -1})})

      assert Map.keys(errors.fields) |> Enum.sort() == [:age, :password, :username]
    end

    test "a valid changeset renders an empty fields map rather than failing" do
      %{errors: errors} = ChangesetJSON.error(%{changeset: changeset(%{username: "ada"})})

      assert errors.fields == %{}
      assert errors.code == "validation_error"
    end
  end
end
