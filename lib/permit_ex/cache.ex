defmodule PermitEx.Cache do
  @moduledoc """
  Optional ETS cache for scope data (`roles` + `permissions`).

  Disabled by default. Enable with:

      config :permit_ex,
        cache: true,
        cache_ttl: :timer.minutes(5)

  Mutation APIs invalidate cache automatically. Call `invalidate/2` or
  `invalidate_all/0` after external changes (raw SQL, another node, etc.).
  """

  @table :permit_ex_scope_cache

  @doc false
  def init do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [
          :named_table,
          :public,
          :set,
          read_concurrency: true,
          write_concurrency: true
        ])

      _tid ->
        @table
    end

    :ok
  end

  @doc "Returns true when caching is enabled via config."
  def enabled?, do: PermitEx.Config.cache?()

  @doc """
  Fetches cached scope data for a user/context pair.

  Returns `{:ok, {roles, permissions}}` or `:miss`.
  """
  def get(user_id, context_id) do
    if enabled?() do
      ensure_table!()

      case :ets.lookup(@table, key(user_id, context_id)) do
        [{_key, data, expires_at}] ->
          if System.monotonic_time(:millisecond) < expires_at do
            {:ok, data}
          else
            :ets.delete(@table, key(user_id, context_id))
            :miss
          end

        [] ->
          :miss
      end
    else
      :miss
    end
  end

  @doc "Stores scope data for a user/context pair when caching is enabled."
  def put(user_id, context_id, data) do
    if enabled?() do
      ensure_table!()
      expires_at = System.monotonic_time(:millisecond) + PermitEx.Config.cache_ttl_ms()
      true = :ets.insert(@table, {key(user_id, context_id), data, expires_at})
    end

    :ok
  end

  @doc """
  Invalidates cached scope data.

  * `invalidate(user_id, context_id)` — one scope (use `nil` for global)
  * `invalidate(user_id, :all)` — every context for that user
  """
  def invalidate(user_id, context_id \\ nil)

  def invalidate(user_id, :all) do
    if table_exists?() do
      :ets.match_delete(@table, {{user_id, :_}, :_, :_})
    end

    :ok
  end

  def invalidate(user_id, context_id) do
    if table_exists?() do
      :ets.delete(@table, key(user_id, context_id))
    end

    :ok
  end

  @doc "Drops the entire scope cache."
  def invalidate_all do
    if table_exists?() do
      :ets.delete_all_objects(@table)
    end

    :ok
  end

  defp key(user_id, context_id), do: {user_id, context_id}

  defp table_exists? do
    :ets.whereis(@table) != :undefined
  end

  defp ensure_table! do
    if table_exists?(), do: :ok, else: init()
  end
end
