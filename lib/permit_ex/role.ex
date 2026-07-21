defmodule PermitEx.Role do
  @moduledoc """
  Ecto schema for global and context-specific roles.

  Roles with `context_id == nil` are global templates. Roles with `context_id`
  belong to one application-defined context, such as a tenant, workspace,
  project, organization, or account.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @context_id_type Application.compile_env(:permit_ex, :context_id_type, Ecto.UUID)

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime_usec]

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          description: String.t() | nil,
          context_id: term() | nil,
          locked: boolean(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "permit_ex_roles" do
    field(:name, :string)
    field(:description, :string)
    field(:context_id, @context_id_type)
    field(:locked, :boolean, default: false)

    has_many(:role_permissions, PermitEx.RolePermission)
    has_many(:permissions, through: [:role_permissions, :permission])
    has_many(:user_roles, PermitEx.UserRole)

    timestamps()
  end

  def changeset(role, attrs) do
    role
    |> cast(attrs, [:name, :description, :context_id, :locked])
    |> validate_required([:name])
    |> validate_format(:name, ~r/\A[a-z0-9_]+\z/, message: "must use slug format")
    |> validate_length(:name, max: 80)
    |> unique_constraint(:name, name: :permit_ex_roles_global_name_index)
    |> unique_constraint([:name, :context_id], name: :permit_ex_roles_context_name_index)
  end
end
