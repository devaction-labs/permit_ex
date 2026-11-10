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
  def get(user_id, context_id), do: do_get(enabled?(), user_id, context_id)

  defp do_get(false, _user_id, _context_id), do: :miss

  defp do_get(true, user_id, context_id) do
    ensure_table!()

    case :ets.lookup(@table, key(user_id, context_id)) do
      [{_key, data, expires_at}] ->
        check_expiry(System.monotonic_time(:millisecond) < expires_at, data, user_id, context_id)

      [] ->
        :miss
    end
  end

  defp check_expiry(true, data, _user_id, _context_id), do: {:ok, data}

  defp check_expiry(false, _data, user_id, context_id) do
    :ets.delete(@table, key(user_id, context_id))
    :miss
  end

  @doc "Stores scope data for a user/context pair when caching is enabled."
  def put(user_id, context_id, data), do: do_put(enabled?(), user_id, context_id, data)

  defp do_put(false, _user_id, _context_id, _data), do: :ok

  defp do_put(true, user_id, context_id, data) do
    ensure_table!()
    expires_at = System.monotonic_time(:millisecond) + PermitEx.Config.cache_ttl_ms()
    true = :ets.insert(@table, {key(user_id, context_id), data, expires_at})
    :ok
  end

  @doc """
  Invalidates cached scope data.

  * `invalidate(user_id, context_id)` — one scope (use `nil` for global)
  * `invalidate(user_id, :all)` — every context for that user
  """
  def invalidate(user_id, context_id \\ nil)

  def invalidate(user_id, :all) do
    when_table(fn -> :ets.match_delete(@table, {{user_id, :_}, :_, :_}) end)
  end

  def invalidate(user_id, context_id) do
    when_table(fn -> :ets.delete(@table, key(user_id, context_id)) end)
  end

  @doc "Drops the entire scope cache."
  def invalidate_all do
    when_table(fn -> :ets.delete_all_objects(@table) end)
  end

  defp key(user_id, context_id), do: {user_id, context_id}

  defp table_exists?, do: :ets.whereis(@table) != :undefined

  defp when_table(fun), do: run_if_table(table_exists?(), fun)

  defp run_if_table(true, fun) do
    fun.()
    :ok
  end

  defp run_if_table(false, _fun), do: :ok

  defp ensure_table! do
    case table_exists?() do
      true -> :ok
      false -> init()
    end
  end
end
