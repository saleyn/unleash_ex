defmodule Unleash.MixProject do
  use Mix.Project

  def project do
    [
      app: :unleash_ex,
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
      env: [url: "localhost", app_name: "", instance_id: ""]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:credo, "~>1.0", only: [:dev, :test], runtime: false},
      {:murmur, "~> 1.0"},
      {:mint, "~>0.1.0"},
      {:mojito, "~> 0.1.0"}
    ]
  end
end
