defmodule Unleash.Config do
  @moduledoc false

  @defaults %{
    url: "",
    appname: "unleash_ex",
    instance_id: Atom.to_string(node()),
    auth_token: {:env_var, "UNLEASH_CLIENT_KEY"},
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
      debug: false
    },
    app_env: :test
  }


  if Mix.env() not in [:test] do
    @app Application.get_application(__MODULE__)
    @http_client Application.compile_env(@app, :http_client, @defaults[:http_client])
  end

  def url, do: application_env(:url)

  def test?, do: application_env(:app_env) == :test

  def appname, do: application_env(:appname)

  def instance_id, do: Atom.to_string(node())

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

  def telemetry_metadata, do: %{appname: appname(), instance_id: instance_id()}

  defp application_env(opt) do
    __MODULE__
    |> Application.get_application()
    |> Application.get_env(opt)
    |> case do
      nil -> Map.get(@defaults, opt)
      val -> val
    end
    |> maybe_get_env_var()
  end

  defp maybe_get_env_var({:env_var, env_var}) do
    System.get_env(env_var)
  end

  defp maybe_get_env_var(val), do: val
end
