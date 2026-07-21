defmodule PermitEx.Config do
  @moduledoc false

  @app :permit_ex

  @id_type Application.compile_env(@app, :id_type, Ecto.UUID)
  @user_id_type Application.compile_env(@app, :user_id_type, @id_type)
  @context_id_type Application.compile_env(@app, :context_id_type, @user_id_type)

  def repo do
    Application.get_env(@app, :repo)
  end

  def repo! do
    repo() || raise ArgumentError, "configure :permit_ex, repo: MyApp.Repo"
  end

  def context_key do
    Application.get_env(@app, :context_key, :context_id)
  end

  def user_key do
    Application.get_env(@app, :user_key, :user_id)
  end

  def cache? do
    Application.get_env(@app, :cache, false) == true
  end

  def cache_ttl_ms do
    Application.get_env(@app, :cache_ttl, :timer.minutes(5))
  end

  def wildcards? do
    Application.get_env(@app, :wildcards, false) == true
  end

  def super_roles do
    Application.get_env(@app, :super_roles, [])
    |> List.wrap()
    |> Enum.map(&to_string/1)
  end

  @doc """
  Type used for primary keys and role/permission foreign keys.

  Configure before compiling PermitEx:

      config :permit_ex, id_type: Ecto.UUID
  """
  def id_type, do: @id_type

  @doc """
  Type used for `user_id` columns. Defaults to `id_type/0`.

      config :permit_ex, user_id_type: :id
  """
  def user_id_type, do: @user_id_type

  @doc """
  Type used for `context_id` columns. Defaults to `user_id_type/0`.

      config :permit_ex, context_id_type: :id
  """
  def context_id_type, do: @context_id_type
end
