defmodule <%= module %> do
  use Ecto.Migration

  def change do
    create table(:permit_ex_permissions, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false
      add :description, :text

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:permit_ex_permissions, [:name])

    create table(:permit_ex_roles, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :context_id, :<%= id_type %>
      add :locked, :boolean, null: false, default: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:permit_ex_roles, [:name],
             where: "context_id IS NULL",
             name: :permit_ex_roles_global_name_index
           )

    create unique_index(:permit_ex_roles, [:context_id, :name],
             where: "context_id IS NOT NULL",
             name: :permit_ex_roles_context_name_index
           )

    create table(:permit_ex_role_permissions, primary_key: false) do
      add :role_id, references(:permit_ex_roles, type: :uuid, on_delete: :delete_all),
        null: false,
        primary_key: true

      add :permission_id,
          references(:permit_ex_permissions, type: :uuid, on_delete: :delete_all),
          null: false,
          primary_key: true

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:permit_ex_role_permissions, [:permission_id])

    create table(:permit_ex_user_roles, primary_key: false) do
      add :user_id, :<%= id_type %>, null: false
      add :context_id, :<%= id_type %>

      add :role_id, references(:permit_ex_roles, type: :uuid, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:permit_ex_user_roles, [:user_id, :role_id],
             where: "context_id IS NULL",
             name: :permit_ex_user_roles_global_role_index
           )

    create unique_index(:permit_ex_user_roles, [:user_id, :context_id, :role_id],
             where: "context_id IS NOT NULL",
             name: :permit_ex_user_roles_context_role_index
           )

    create index(:permit_ex_user_roles, [:user_id, :context_id])
    create index(:permit_ex_user_roles, [:role_id, :context_id])
    create index(:permit_ex_user_roles, [:context_id])
  end
end
