defmodule Api.Schema do
  @moduledoc """
  Shared conventions for every schema in the application: UUID primary keys,
  UUID foreign keys and microsecond timestamps.

  Both matter beyond consistency. Sequential ids would let a client enumerate
  other people's records by counting, and `(inserted_at, id)` is only a total
  order for keyset pagination if two rows written in the same second can still
  be told apart.

      defmodule Api.Accounts.User do
        use Api.Schema

        schema "users" do
          field :username, :string
          timestamps()
        end
      end
  """

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema

      import Ecto.Changeset

      @primary_key {:id, :binary_id, autogenerate: true}
      @foreign_key_type :binary_id
      @timestamps_opts [type: :utc_datetime_usec]
    end
  end
end
