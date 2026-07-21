defmodule PermitEx.Telemetry do
  @moduledoc """
  Telemetry events emitted by PermitEx.

  ## Events

  * `[:permit_ex, :scope, :load]` — span around scope data loading
    * measurements: `:duration` (native time)
    * metadata: `:user_id`, `:context_id`, `:cache_hit`

  * `[:permit_ex, :authorize, :stop]` — emitted after permission/role checks
    * measurements: `:duration` (native time)
    * metadata: `:result` (`:ok` | `:unauthorized` | `true` | `false`),
      `:permission` or `:role`, `:check` (`:can?` | `:has_role?` | `:authorize` | ...)

  * `[:permit_ex, :mutation, :stop]` — emitted after mutating APIs
    * measurements: `:duration`
    * metadata: `:operation` (atom), `:result` (`:ok` | `:error`)
  """

  @doc false
  def span(event_prefix, meta, fun) when is_function(fun, 0) do
    start = System.monotonic_time()
    {result, extra_meta} = fun.()
    duration = System.monotonic_time() - start

    :telemetry.execute(
      event_prefix ++ [:stop],
      %{duration: duration},
      Map.merge(meta, extra_meta)
    )

    result
  end

  @doc false
  def span_result(event_prefix, meta, fun) when is_function(fun, 0) do
    start = System.monotonic_time()
    result = fun.()
    duration = System.monotonic_time() - start

    :telemetry.execute(
      event_prefix ++ [:stop],
      %{duration: duration},
      Map.put(meta, :result, classify(result))
    )

    result
  end

  defp classify(:ok), do: :ok
  defp classify(true), do: true
  defp classify(false), do: false
  defp classify({:ok, _}), do: :ok
  defp classify({:error, _}), do: :error
  defp classify(_), do: :other
end
