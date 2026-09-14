defmodule Unleash.Config do
  @moduledoc false

  @defaults %{
    url: "",
    appname: "unleash_ex",
    instance_id: Atom.to_string(node()),
    auth_token: {:env_var, "UNLEASH_CLIENT_KEY"},
    metrics_period: 60 * 1000,
    features_period: 15 * 1000,
    strategies: Unleash.Strategies,
    backup_file: nil,
    custom_http_headers: [],
    disable_client: false,
    disable_metrics: false,
    disable_telemetry: true,
    fast_metrics: true,
    retries: -1,
    client: Unleash.Client,
    http_client: Unleash.Http.SimpleHttp,
    http_opts: %{
      ssl: [verify: :verify_none],
      headers_format: :binary,
      headers: [
        "Content-Type": "application/json"
      ],
      debug: false,
      timeout: 5000
    },
    persisten_term_key: :unleash_client_ready,
    registration_attempts: 5,
    registration_attempts_interval: 5000,
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

  @doc """
  Same data as `strategies/0`, as a `name => module` map, cached in
  `:persistent_term` so `Unleash.Strategy.enabled?/2` doesn't pay for
  rebuilding the strategies list and linear-scanning it on every strategy
  check. Since `:strategies` is a config value a consumer could in principle
  change at runtime (see README's Extensibility section), changing it after
  the first lookup requires a restart to take effect — same caveat already
  documented for `fast_metrics`/`disable_metrics` in `Unleash.MetricsFast`.
  """
  def strategies_map do
    case :persistent_term.get(:unleash_strategies_map, nil) do
      nil ->
        map = Map.new(strategies())
        :persistent_term.put(:unleash_strategies_map, map)
        map

      map ->
        map
    end
  end

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

  def disable_telemetry, do: application_env(:disable_telemetry)

  @doc """
  Fast-path accessors that read from persistent_term (O(1), ~20ns).
  Must call `cache_hot_path_config!/0` once at application start.
  Falls back to `application_env/1` if the cache hasn't been initialized.

  In test mode these always delegate to Application env so that per-test
  overrides via `Application.put_env/3` are respected.
  """
  if Mix.env() in [:test] do
    def disable_client_fast, do: disable_client()
    def disable_telemetry_fast, do: disable_telemetry()
    def metrics_module_fast, do: metrics_module()
  else
    def disable_client_fast do
      :persistent_term.get(:unleash_cfg_disable_client, :not_cached)
      |> case do
        :not_cached -> disable_client()
        val -> val
      end
    end

    def disable_telemetry_fast do
      :persistent_term.get(:unleash_cfg_disable_telemetry, :not_cached)
      |> case do
        :not_cached -> disable_telemetry()
        val -> val
      end
    end

    def metrics_module_fast do
      :persistent_term.get(:unleash_cfg_metrics_module, :not_cached)
      |> case do
        :not_cached -> metrics_module()
        val -> val
      end
    end
  end

  @doc """
  Cache hot-path config values in persistent_term. Call once at app start.
  """
  def cache_hot_path_config! do
    :persistent_term.put(:unleash_cfg_disable_client, disable_client())
    :persistent_term.put(:unleash_cfg_disable_telemetry, disable_telemetry())
    :persistent_term.put(:unleash_cfg_metrics_module, metrics_module())
    :ok
  end

  def fast_metrics, do: application_env(:fast_metrics)

  def metrics_module do
    if fast_metrics() do
      Unleash.MetricsFast
    else
      Unleash.Metrics
    end
  end

  def retries, do: application_env(:retries)

  def client, do: application_env(:client)

  def http_opts, do: application_env(:http_opts)

  def persisten_term_key, do: application_env(:persisten_term_key)

  def registration_attempts, do: application_env(:registration_attempts)

  def registration_attempts_interval, do: application_env(:registration_attempts_interval)

  if Mix.env() in [:test] do
    def http_client, do: application_env(:http_client)
  else
    def http_client, do: @http_client
  end

  def telemetry_metadata, do: %{appname: appname(), instance_id: instance_id()}

  # Application.get_application/1 (~14 μs, see :persistent_term.get/2 below)
  # can't be resolved at compile time: at the point Unleash.Config itself is
  # being compiled, the app-to-module association it depends on doesn't
  # exist yet (it's written after all of the app's modules finish
  # compiling), so a module attribute would silently cache `nil` forever.
  # It's safe to cache lazily at the first *runtime* call instead — by then
  # :unleash is loaded (even if not started) and the owning app for a given
  # module cannot change afterwards.
  defp owning_app do
    case :persistent_term.get(:unleash_config_owning_app, nil) do
      nil ->
        # Don't cache a nil result: it would mean :unleash wasn't loaded yet
        # at this particular call, which is possible very early in startup,
        # so keep retrying until we get a real answer to cache.
        case Application.get_application(__MODULE__) do
          nil ->
            nil

          app ->
            :persistent_term.put(:unleash_config_owning_app, app)
            app
        end

      app ->
        app
    end
  end

  defp application_env(opt) do
    owning_app()
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
