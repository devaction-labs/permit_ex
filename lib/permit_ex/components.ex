if Code.ensure_loaded?(Phoenix.Component) do
  defmodule PermitEx.Components do
    @moduledoc """
    Optional HEEx helpers for permission-aware UI.

        <.permit_can scope={@current_scope} permission="orders:manage">
          <.link navigate={~p"/orders/new"}>New order</.link>
        </.permit_can>

        <.permit_can scope={@current_scope} role="admin">
          Admin panel
        </.permit_can>
    """

    use Phoenix.Component

    attr(:scope, :any, required: true)
    attr(:permission, :string, default: nil)
    attr(:role, :string, default: nil)
    attr(:any_permissions, :list, default: [])
    attr(:all_permissions, :list, default: [])
    attr(:any_roles, :list, default: [])
    attr(:all_roles, :list, default: [])
    slot(:inner_block, required: true)

    def permit_can(assigns) do
      if allowed?(assigns) do
        ~H"""
        <%= render_slot(@inner_block) %>
        """
      else
        ~H""
      end
    end

    defp allowed?(assigns) do
      opts =
        []
        |> maybe_put(:permission, assigns.permission)
        |> maybe_put(:role, assigns.role)
        |> maybe_put(:any_permissions, assigns.any_permissions)
        |> maybe_put(:all_permissions, assigns.all_permissions)
        |> maybe_put(:any_roles, assigns.any_roles)
        |> maybe_put(:all_roles, assigns.all_roles)

      case opts do
        [] -> false
        _ -> PermitEx.Guard.authorized?(assigns.scope, opts)
      end
    end

    defp maybe_put(opts, _key, nil), do: opts
    defp maybe_put(opts, _key, []), do: opts
    defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
  end
end
