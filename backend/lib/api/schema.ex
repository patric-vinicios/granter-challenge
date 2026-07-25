defmodule Api.Schema do
  @moduledoc """
  Shared schema conventions: UUID primary keys, UUID foreign keys and
  microsecond timestamps.

  The UUIDs stop a client from enumerating other people's records by counting.
  The microsecond precision keeps `(inserted_at, id)` a total order for keyset
  pagination, so two rows written in the same second stay distinguishable.

  ## Example

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
