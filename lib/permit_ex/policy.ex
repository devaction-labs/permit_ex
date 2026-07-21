defmodule PermitEx.Policy do
  @moduledoc """
  Behaviour for optional resource-level policy checks.

  RBAC answers whether a scope has a permission. A policy can answer whether
  that scope may use the permission against a specific resource.

  The third argument receives the full options keyword list passed to
  `PermitEx.allowed?/4` or `PermitEx.authorize/4` (including `:policy` itself).
  """

  @callback authorize(scope :: term(), resource :: term(), opts :: keyword()) ::
              :ok | true | false | {:error, term()}
end
