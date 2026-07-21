defmodule PermitEx.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    PermitEx.Cache.init()

    children = []
    opts = [strategy: :one_for_one, name: PermitEx.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
