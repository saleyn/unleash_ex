defmodule Unleash.Config do
  @defaults [
    url: "http://localhost:4242",
    appname: "test",
    instance_id: "test",
    metrics_period: 10 * 60 * 1000,
    features_period: 15 * 1000,
    strategies: Unleash.Strategies
  ]

  def url() do
    application_env()
    |> Keyword.fetch!(:url)
  end

  def appname() do
    application_env()
    |> Keyword.fetch!(:appname)
  end

  def instance_id() do
    application_env()
    |> Keyword.fetch!(:instance_id)
  end

  def metrics_period() do
    application_env()
    |> Keyword.fetch!(:metrics_period)
  end

  def features_period() do
    application_env()
    |> Keyword.fetch!(:features_period)
  end

  def strategies() do
    strategy_module =
      application_env()
      |> Keyword.fetch!(:strategies)

    strategy_module.strategies()
  end

  def strategy_names() do
    strategies()
    |> Enum.map(fn {n, _} -> n end)
  end

  defp application_env() do
    __MODULE__
    |> Application.get_application()
    |> Application.get_env(Unleash, [])
    |> Keyword.merge(@defaults)
  end
end
