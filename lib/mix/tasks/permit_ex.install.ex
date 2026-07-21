defmodule Mix.Tasks.PermitEx.Install do
  @moduledoc """
  Installs PermitEx migrations into the host application.

      mix permit_ex.install
      mix permit_ex.install --migrations-path priv/repo/migrations
      mix permit_ex.install --id-type uuid
      mix permit_ex.install --id-type id

  ## Options

  * `--migrations-path` — target directory (default `priv/repo/migrations`)
  * `--id-type` — column type for `user_id` and `context_id`:
    * `uuid` / `binary_id` (default) — PostgreSQL `uuid`
    * `id` / `bigint` / `integer` — PostgreSQL `bigint`

  Role and permission primary keys always use `uuid`.

  When using non-UUID user/context ids, configure the schemas before compiling:

      config :permit_ex,
        user_id_type: :id,
        context_id_type: :id

  Then force-recompile: `mix deps.compile permit_ex --force`.
  """

  use Mix.Task

  @shortdoc "Copies PermitEx migrations"

  @switches [migrations_path: :string, id_type: :string]

  @impl Mix.Task
  def run(args) do
    Mix.Project.get!()

    {opts, _} = OptionParser.parse!(args, strict: @switches)
    target_dir = Keyword.get(opts, :migrations_path, Path.join(["priv", "repo", "migrations"]))
    id_type = normalize_id_type(Keyword.get(opts, :id_type, "uuid"))

    File.mkdir_p!(target_dir)

    case existing_migration(target_dir) do
      {:ok, path} ->
        Mix.shell().info("Migration already exists: #{path}")

      :none ->
        path = write_migration(target_dir, id_type)
        Mix.shell().info("Created #{path}")
        Mix.shell().info("id_type for user_id/context_id: #{id_type}")
        Mix.shell().info("Run `mix ecto.migrate` to apply it.")

        if id_type != "uuid" do
          Mix.shell().info("""

          Non-UUID ids: add to config and recompile permit_ex:

              config :permit_ex,
                user_id_type: :id,
                context_id_type: :id

              mix deps.compile permit_ex --force
          """)
        end
    end
  end

  defp existing_migration(dir) do
    case Path.wildcard(Path.join(dir, "*_create_permit_ex_tables.exs")) do
      [path | _] -> {:ok, path}
      [] -> :none
    end
  end

  defp write_migration(dir, id_type) do
    filename = "#{timestamp()}_create_permit_ex_tables.exs"
    path = Path.join(dir, filename)
    module = "CreatePermitExTables"

    contents =
      template_path()
      |> File.read!()
      |> EEx.eval_string(module: module, id_type: id_type)

    File.write!(path, contents)
    Mix.Task.run("format", [path])
    path
  end

  defp template_path do
    :permit_ex
    |> :code.priv_dir()
    |> to_string()
    |> Path.join("templates/create_permit_ex_tables.exs")
  end

  defp normalize_id_type(type) when type in ["uuid", "binary_id"], do: "uuid"
  defp normalize_id_type(type) when type in ["id", "bigint", "integer"], do: "bigint"

  defp normalize_id_type(other) do
    Mix.raise("Unknown --id-type #{inspect(other)}. Use uuid, binary_id, id, bigint, or integer.")
  end

  defp timestamp do
    {{year, month, day}, {hour, minute, second}} = :calendar.universal_time()

    [year, month, day, hour, minute, second]
    |> Enum.map_join(&(&1 |> Integer.to_string() |> String.pad_leading(2, "0")))
  end
end
