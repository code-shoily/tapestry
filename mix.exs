defmodule Tapestry.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/code-shoily/tapestry"

  def project do
    [
      app: :tapestry,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      dialyzer: [plt_add_apps: [:mix], flags: [:no_opaque]],

      # Hex
      description: "Graph-native task and project management engine",
      package: package(),

      # Docs
      name: "Tapestry",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs(),

      # Test Coverage
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:yog_ex, "~> 0.97"},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end

  defp package do
    [
      name: "tapestry",
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md"
      ],
      source_ref: "v#{@version}",
      source_url: @source_url,
      mermaid: true,
      before_closing_body_tag: &before_closing_body_tag/1,
      groups_for_modules: [
        Core: [
          Tapestry,
          Tapestry.Serializer
        ],
        Builder: [
          Tapestry.Builder
        ],
        Query: [
          Tapestry.Query
        ],
        Analysis: [
          Tapestry.Analysis
        ],
        Views: [
          Tapestry.View.Kanban,
          Tapestry.View.Timeline,
          Tapestry.View.Graph
        ]
      ]
    ]
  end

  defp before_closing_body_tag(:html) do
    File.read!("priv/docs/graphviz.html")
  end

  defp before_closing_body_tag(_), do: ""
end
