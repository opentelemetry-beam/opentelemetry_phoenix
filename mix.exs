defmodule OpentelemetryPhoenix.MixProject do
  use Mix.Project

  def project do
    [
      app: :opentelemetry_phoenix,
      description: description(),
      version: "0.1.0",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Opentelemetry Phoenix",
      docs: [
        main: "OpentelemetryPhoenix",
        extras: ["README.md"]
      ],
      elixirc_paths: elixirc_paths(Mix.env()),
      package: package(),
      source_url: "https://github.com/opentelemetry-beam/opentelemetry_phoenix"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: []
    ]
  end

  defp description do
    "Trace Phoenix requests with OpenTelemetry."
  end

  defp package do
    [
      description: "OpenTelemetry tracing for the Phoenix Framework",
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => "https://github.com/opentelemetry-beam/opentelemetry_phoenix",
        "OpenTelemetry Erlang" => "https://github.com/open-telemetry/opentelemetry-erlang",
        "OpenTelemetry.io" => "https://opentelemetry.io"
      }
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:opentelemetry_api,
       github: "open-telemetry/opentelemetry-erlang-api",
       ref: "6dff2509273a023da9fb33f8ead21fbf7885d3e1",
       override: true},
      {:opentelemetry,
       github: "open-telemetry/opentelemetry-erlang",
       ref: "cdbda95ba6d2e58f50ed4a7428bffce62588ba64"},
      {:telemetry, "~> 0.4"},
      {:plug, "~> 1.10", only: [:dev, :test]},
      {:ex_doc, "~> 0.21.0", only: [:dev], runtime: false},
      {:plug_cowboy, "~> 2.3", only: [:test]},
      {:dialyxir, "~> 1.0", only: [:dev, :test]}
    ]
  end
end
