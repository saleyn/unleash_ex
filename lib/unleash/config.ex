defmodule Unleash.Config do
  @moduledoc false

  @defaults [
    url: "",
    appname: "",
    instance_id: "",
    auth_token: nil,
    metrics_period: 10 * 60 * 1000,
    features_period: 15 * 1000,
    strategies: Unleash.Strategies,
    backup_file: nil,
    custom_http_headers: [],
    disable_client: false,
    disable_metrics: false,
    retries: -1,
    client: Unleash.Client,
    http_client: Mojito,
    app_env: :test
  ]

  def url do
    application_env()
    |> Keyword.fetch!(:url)
  end

  def test? do
    application_env()
    |> Keyword.fetch!(:app_env) == :test
  end

  def appname do
    application_env()
    |> Keyword.fetch!(:appname)
  end

  def instance_id do
    application_env()
    |> Keyword.fetch!(:instance_id)
  end

  def auth_token do
    application_env()
    |> Keyword.get(:auth_token)
  end

  def metrics_period do
    application_env()
    |> Keyword.fetch!(:metrics_period)
  end

  def features_period do
    application_env()
    |> Keyword.fetch!(:features_period)
  end

  def strategies do
    strategy_module =
      application_env()
      |> Keyword.fetch!(:strategies)

    strategy_module.strategies
  end

  def strategy_names do
    strategies()
    |> Enum.map(fn {n, _} -> n end)
  end

  def backup_file do
    application_env()
    |> Keyword.fetch!(:backup_file)
    |> case do
      nil -> Path.join([System.tmp_dir!(), appname(), "repo.json"])
      f -> f
    end
  end

  def backup_dir do
    backup_file()
    |> Path.dirname()
  end

  def custom_headers do
    application_env()
    |> Keyword.fetch!(:custom_http_headers)
  end

  def disable_client do
    application_env()
    |> Keyword.fetch!(:disable_client)
  end

  def disable_metrics do
    application_env()
    |> Keyword.fetch!(:disable_metrics)
  end

  def retries do
    application_env()
    |> Keyword.fetch!(:retries)
  end

  def client do
    application_env()
    |> Keyword.fetch!(:client)
  end

  def http_client do
    application_env()
    |> Keyword.fetch!(:http_client)
  end

  defp application_env do
    config =
      __MODULE__
      |> Application.get_application()
      |> Application.get_env(Unleash, [])

    Keyword.merge(@defaults, config)
  end
end
