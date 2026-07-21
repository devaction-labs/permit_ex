defmodule PermitEx.Permission do
  @moduledoc """
  Ecto schema for permission names.

  Permission names are stored as strings so they can be seeded, edited and
  transported through APIs without creating atoms at runtime.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime_usec]

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          description: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "permit_ex_permissions" do
    field(:name, :string)
    field(:description, :string)

    has_many(:role_permissions, PermitEx.RolePermission)

    timestamps()
  end

  def changeset(permission, attrs) do
    permission
    |> cast(attrs, [:name, :description])
    |> validate_required([:name])
    |> validate_format(:name, ~r/\A[a-z0-9_]+:[a-z0-9_*]+\z/,
      message: "must use resource:action format"
    )
    |> validate_length(:name, max: 120)
    |> unique_constraint(:name)
  end
end
