defmodule Unleash.MixProject do
  use Mix.Project

  def project do
    [
      app: :unleash,
      version: "0.1.0",
      elixir: "~> 1.8",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      env: [
        url: "http://localhost:4242",
        appname: "",
        instance_id: "",
        metrics_period: 10 * 60 * 1000,
        features_period: 15 * 1000,
        strategies: Unleash.Strategies
      ],
      mod: {Unleash, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:credo, "~> 1.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 0.5", only: [:dev], runtime: false},
      {:stream_data, "~> 0.4.3", only: [:test]},
      {:murmur, "~> 1.0"},
      {:tesla, "~> 1.2"},
      {:hackney, "~> 1.14.0"},
      {:jason, ">= 1.0.0"},
      {:mint, "~>0.1.0"},
      {:mojito, "~> 0.1.0"}
    ]
  end
end
