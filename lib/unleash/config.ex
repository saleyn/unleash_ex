defmodule Unleash.Config do
  def url() do
    application()
    |> Application.get_env(:url, "localhost")
  end

  def appname() do
    application()
    |> Application.get_env(:appname, "")
  end

  def instance_id() do
    application()
    |> Application.get_env(:instance_id, "")
  end

  def metrics_period() do
    application()
    |> Application.get_env(:metrics_period, "")
  end

  def strategies() do
    Unleash.Strategies.strategies()
  end

  defp application() do
    Application.get_application(__MODULE__)
  end
end
