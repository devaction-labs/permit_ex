defmodule PermitEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :permit_ex,
      version: "0.3.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      description: description(),
      package: package(),
      source_url: "https://github.com/devaction-labs/permit_ex",
      homepage_url: "https://github.com/devaction-labs/permit_ex",
      docs: docs(),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {PermitEx.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto_sql, "~> 3.14"},
      {:postgrex, "~> 0.22", only: :test},
      {:plug, "~> 1.19", optional: true},
      {:phoenix_live_view, "~> 1.1", optional: true},
      {:absinthe, "~> 1.10", optional: true},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp description do
    "Role and permission management for Ecto and Phoenix applications."
  end

  defp package do
    [
      licenses: ["MIT"],
      files: ~w(lib priv .formatter.exs mix.exs README.md LICENSE CHANGELOG.md docs),
      links: %{"GitHub" => "https://github.com/devaction-labs/permit_ex"}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "LICENSE",
        "docs/phoenix.md",
        "docs/api.md",
        "docs/absinthe.md",
        "docs/testing.md",
        "docs/use-nexus.md"
      ],
      groups_for_extras: [
        Guides: ~r/docs\/.*/
      ],
      source_ref: "v0.3.0",
      source_url: "https://github.com/devaction-labs/permit_ex"
    ]
  end
end
