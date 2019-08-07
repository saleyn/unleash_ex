defmodule Unleash.Config do
  @url "http://localhost:4242"
  @appname ""
  @instance_id ""
  @metrics_period 10 * 60 * 1000
  @features_period 15 * 1000
  @strategies Unleash.Strategies

  def url() do
    application()
    |> Application.get_env(:url, @url)
  end

  def appname() do
    application()
    |> Application.get_env(:appname, @appname)
  end

  def instance_id() do
    application()
    |> Application.get_env(:instance_id, @instance_id)
  end

  def metrics_period() do
    application()
    |> Application.get_env(:metrics_period, @metrics_period)
  end

  def features_period() do
    application()
    |> Application.get_env(:features_period, @features_period)
  end

  def strategies() do
    strategy_module =
      application()
      |> Application.get_env(:strategies, @strategies)

    strategy_module.strategies()
  end

  defp application() do
    Application.get_application(__MODULE__)
  end
end
