defmodule Api.SchemaTest do
  use ExUnit.Case, async: true

  defmodule SampleSchema do
    use Api.Schema

    schema "samples" do
      field :name, :string

      belongs_to :parent, __MODULE__

      timestamps()
    end
  end

  describe "use Api.Schema" do
    test "gives the schema a binary_id primary key" do
      assert SampleSchema.__schema__(:primary_key) == [:id]
      assert SampleSchema.__schema__(:type, :id) == :binary_id
    end

    test "autogenerates the id as a UUID rather than a sequence" do
      assert SampleSchema.__schema__(:autogenerate_id) == {:id, :id, :binary_id}
    end

    test "makes foreign keys binary_id so associations match the primary keys" do
      assert SampleSchema.__schema__(:type, :parent_id) == :binary_id
    end

    test "gives timestamps microsecond precision" do
      assert SampleSchema.__schema__(:type, :inserted_at) == :utc_datetime_usec
      assert SampleSchema.__schema__(:type, :updated_at) == :utc_datetime_usec
    end

    test "imports Ecto.Changeset so schemas do not repeat the import" do
      changeset = Ecto.Changeset.cast(struct!(SampleSchema), %{name: "sample"}, [:name])

      assert changeset.changes == %{name: "sample"}
    end
  end
end
