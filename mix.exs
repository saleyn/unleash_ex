defmodule Unleash.MixProject do
  @moduledoc false
  use Mix.Project

  @gitlab_url "https://www.gitlab.com/afontaine/unleash_ex"

  def project do
    [
      app: :unleash,
      version: "VERSION" |> File.read!() |> String.trim(),
      elixir: "~> 1.8",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      name: "Unleash",
      description: "An Unleash Feature Flag client for Elixir",
      source_url: @gitlab_url,
      homepage_url: @gitlab_url,
      docs: docs(),
      package: [
        files: ~w(mix.exs lib LICENSE README.md CHANGELOG.md VERSION),
        maintainers: ["Andrew Fontaine"],
        licenses: ["MIT"],
        links: %{
          "GitLab" => @gitlab_url
        }
      ],
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Unleash, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:credo, "~> 1.0", only: [:dev, :test], runtime: false},
      {:inch_ex, "~> 2.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 0.5", only: :dev, runtime: false},
      {:ex_doc, "~> 0.21", only: :dev, runtime: false},
      {:eliver, "~> 2.0", only: :dev, runtime: false},
      {:junit_formatter, "~> 3.0", only: :test},
      {:stream_data, "~> 0.4.3", only: [:test, :dev]},
      {:excoveralls, "~> 0.8", only: :test},
      {:mox, "~> 0.5.1", only: :test},
      {:recase, "~> 0.6.0", only: :test},
      {:murmur, "~> 1.0"},
      {:mojito, "~> 0.5.0"},
      {:jason, "~> 1.1"},
      {:plug, "~> 1.8", optional: true},
      {:phoenix_gon, "~> 0.4.0", optional: true}
    ]
  end

  defp aliases do
    [
      test: ["test --no-start"]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      deps: [
        mojito: "https://hexdocs.pm/mojito/",
        murmur: "https://hexdocs.pm/murmur/",
        plug: "https://hexdocs.pm/plug/",
        phoenix_gon: "https://hexdocs.pm/phoenix_gon/"
      ],
      groups_for_modules: [
        Strategies: ~r"Strateg(y|ies)\."
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["test/support", "lib"]

  defp elixirc_paths(_), do: ["lib"]
end
