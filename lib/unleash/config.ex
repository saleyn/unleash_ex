defmodule Unleash.Config do
  @moduledoc false

  @defaults %{
    url: "",
    appname: "unleash_ex",
    instance_id: Atom.to_string(node()),
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
    http_client: Unleash.Http.SimpleHttp,
    http_opts: %{
        ssl: [verify: :verify_none],
        headers_format: :binary,
        headers: [
          "Content-Type": "application/json"
        ],
        debug: true
      },
    app_env: :test
  }

  @app Application.get_application(__MODULE__)

  @http_client Application.compile_env(@app, :http_client, @defaults[:http_client])
  @app_name Application.compile_env(@app, :appname, @defaults[:appname])
  @instance_id Application.compile_env(@app, :instance_id, @defaults[:instance_id])

  @telemetry_metadata %{appname: @app_name, instance_id: @instance_id}

  def url, do: application_env(:url)

  def test?, do: application_env(:app_env) == :test

  def appname, do: @app_name

  def instance_id, do: @instance_id

  def auth_token, do: application_env(:auth_token)

  def metrics_period, do: application_env(:metrics_period)

  def features_period, do: application_env(:features_period)

  def strategies, do: application_env(:strategies).strategies()

  def strategy_names, do: for({n, _} <- strategies(), do: n)

  def backup_file do
    application_env(:backup_file)
    |> case do
      nil -> Path.join([System.tmp_dir!(), appname(), "repo.json"])
      f -> f
    end
  end

  def backup_dir, do: backup_file() |> Path.dirname()

  def custom_headers, do: application_env(:custom_http_headers)

  def disable_client, do: application_env(:disable_client)

  def disable_metrics, do: application_env(:disable_metrics)

  def retries, do: application_env(:retries)

  def client, do: application_env(:client)

  def http_opts, do: application_env(:http_opts)

  if Mix.env() in [:test] do
    def http_client, do: application_env(:http_client)
  else
    def http_client, do: @http_client
  end

  def telemetry_metadata, do: @telemetry_metadata

  defp application_env(opt) do
    __MODULE__
    |> Application.get_application()
    |> Application.get_env(opt)
    |> case do
      nil -> Map.get(@defaults, opt)
      val -> val
    end
  end
end
