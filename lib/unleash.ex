defmodule Unleash do
  @moduledoc """
  If you have no plans on extending the client, then `Unleash` will be the main
  usage point of the library. Upon starting your app, the client is registered
  with the unleash server, and two `GenServer`s are started, one to fetch and
  poll for feature flags from the server, and one to send metrics.

  Configuring `:disable_client` to `true` disables both servers as well as
  registration, while configuring `:disable_metrics` to `true` disables only
  the metrics `GenServer`.

  Configuring `:fast_metrics` to `true` enables the high-performance ETS-based
  metrics collection (~40x faster than the default GenServer-based approach).
  This is recommended for high-throughput applications.
  """

  use Application

  @compile {:no_warn_undefined, Unleash.CompiledFeatures}

  alias Unleash.Config
  alias Unleash.Feature
  alias Unleash.FeatureCompiler
  alias Unleash.Metrics
  alias Unleash.MetricsFast
  alias Unleash.Repo
  alias Unleash.Variant

  require Logger

  @typedoc """
  The context needed for a few activation strategies. Check their documentation
  for the required key.

  * `:user_id` is the ID of the user interacting _with your system_, can be any
    `String.t()`
  * `session_id` is the ID of the current session _in your system_, can be any
    `String.t()`
  * `remote_address` is the address of the user interacting _with your system_,
    can be any `String.t()`
  """
  @type context :: %{
          user_id: String.t(),
          session_id: String.t(),
          remote_address: String.t()
        }

  @doc """
  Aliased to `enabled?/2`
  """
  @spec is_enabled?(atom() | String.t(), boolean) :: boolean
  def is_enabled?(feature, default) when is_boolean(default),
    do: enabled?(feature, default)

  @doc """
  Aliased to `enabled?/3`
  """
  @spec is_enabled?(atom() | String.t(), map(), boolean) :: boolean
  def is_enabled?(feature, context \\ %{}, default \\ false),
    do: enabled?(feature, context, default)

  @doc """
  Checks if the given feature is enabled. Checks as though an empty context was
  passed in.

  ## Examples

      iex> Unleash.enabled?(:my_feature, false)
      false

      iex> Unleash.enabled?(:my_feature, true)
      true
  """
  @spec enabled?(atom() | String.t(), boolean) :: boolean
  def enabled?(feature, default) when is_boolean(default),
    do: enabled?(feature, %{}, default)

  @doc """
  Checks if the given feature is enabled.

  If `:disable_client` is `true`, simply returns the given `default`.

  If `:disable_metrics` is `true`, nothing is logged about the given toggle.

  ## Examples

      iex> Unleash.enabled?(:my_feature)
      false

      iex> Unleash.enabled?(:my_feature, context)
      false

      iex> Unleash.enabled?(:my_feature, context, true)
      false
  """
  @spec enabled?(atom() | String.t(), map(), boolean) :: boolean
  def enabled?(feature, context \\ %{}, default \\ false) do
    if Config.disable_telemetry_fast() do
      enabled_fast(feature, context, default)
    else
      start_metadata = Unleash.Client.telemetry_metadata(%{feature: feature, context: context})

      :telemetry.span(
        [:unleash, :feature, :enabled?],
        start_metadata,
        fn ->
          {result, metadata} = do_enabled(feature, context, default)

          telemetry_metadata =
            start_metadata
            |> Map.merge(metadata)
            |> Map.put(:result, result)

          {result, telemetry_metadata}
        end
      )
    end
  end

  # Fast path: no metadata allocation, no telemetry, minimal branching.
  # Uses persistent_term + static Feature.enabled?/2 instead of the dynamic
  # CompiledFeatures module — under high concurrency the static JIT-optimized
  # code path is faster than dispatching through a hot-swapped module.
  defp enabled_fast(feature, context, default) do
    if Config.disable_client_fast() or not FeatureCompiler.compiled?() do
      default
    else
      eval_feature_fast(to_string(feature), context, default)
    end
  end

  defp eval_feature_fast(feature_name, context, default) do
    case FeatureCompiler.get_feature(feature_name) do
      nil ->
        default

      loaded_feature ->
        {result, _evaluations} = Feature.enabled?(loaded_feature, context)
        Config.metrics_module_fast().add_metric({loaded_feature, result})
        result
    end
  end

  defp do_enabled(feature, context, default) do
    if Config.disable_client() do
      {default, %{reason: :disabled_client}}
    else
      eval_compiled(to_string(feature), context, default)
    end
  end

  defp eval_compiled(feature_name, context, default) do
    unless FeatureCompiler.compiled?() do
      {default, %{reason: :feature_not_found}}
    else
      do_eval_compiled(feature_name, context, default)
    end
  end

  defp do_eval_compiled(feature_name, context, default) do
    case Unleash.CompiledFeatures.enabled?(feature_name, context) do
      nil ->
        {default, %{reason: :feature_not_found}}

      result when is_boolean(result) ->
        f = FeatureCompiler.get_feature(feature_name)
        if f, do: Config.metrics_module().add_metric({f, result})
        {result, %{feature_name: feature_name, reason: :compiled_eval, enabled: f && f.enabled}}
    end
  end

  @doc """
  Returns a variant for the given name.

  If `:disable_client` is `true`, returns the fallback.

  A [variant](https://unleash.github.io/docs/beta_features#feature-toggle-variants)
  allows for more complicated toggling than a simple `true`/`false`, instead
  returning one of the configured variants depending on whether or not there
  are any overrides for a given context value as well as factoring in the
  weights for the various weight options.

  ## Examples

      iex> Unleash.get_variant(:test)
      %{enabled: true, name: "test", payload: %{...}}

      iex> Unleash.get_variant(:test)
      %{enabled: false, name: "disabled"}
  """
  @spec get_variant(atom() | String.t(), map(), Variant.result()) :: Variant.result()
  def get_variant(feature, context \\ %{}, fallback \\ Variant.disabled()) do
    if Config.disable_telemetry_fast() do
      get_variant_fast(feature, context, fallback)
    else
      start_metadata = Unleash.Client.telemetry_metadata(%{feature_name: feature, context: context})

      :telemetry.span(
        [:unleash, :variant, :get],
        start_metadata,
        fn ->
          {result, metadata} = do_get_variant(feature, context, fallback)
          {result, Map.merge(start_metadata, metadata)}
        end
      )
    end
  end

  # Fast path: no metadata allocation, no telemetry
  defp get_variant_fast(feature, context, fallback) do
    if Config.disable_client_fast() or not FeatureCompiler.compiled?() do
      fallback
    else
      select_variant_fast(to_string(feature), context, fallback)
    end
  end

  defp select_variant_fast(feature_name, context, fallback) do
    case FeatureCompiler.get_feature(feature_name) do
      nil ->
        fallback

      loaded_feature ->
        {result, _metadata} = Variant.select_variant(loaded_feature, context)
        Config.metrics_module_fast().add_variant_metric({loaded_feature, result})
        result
    end
  end

  defp do_get_variant(feature, context, fallback) do
    if Config.disable_client() do
      {fallback, %{reason: :disabled_client}}
    else
      eval_variant(to_string(feature), context, fallback)
    end
  end

  defp eval_variant(feature_name, context, fallback) do
    if FeatureCompiler.compiled?() do
      case FeatureCompiler.get_feature(feature_name) do
        nil ->
          {fallback, %{reason: :feature_not_found}}

        loaded_feature ->
          {result, metadata} = Variant.select_variant(loaded_feature, context)
          Config.metrics_module().add_variant_metric({loaded_feature, result})
          {result, metadata}
      end
    else
      {fallback, %{reason: :feature_not_found}}
    end
  end

  @doc false
  def start(_type, _args) do
    :persistent_term.put(Config.persisten_term_key(), false)
    Config.cache_hot_path_config!()

    children =
      [
        {Repo, Config.disable_client()},
        {metrics_child_spec(), Config.disable_client() or Config.disable_metrics()}
      ]
      |> Enum.filter(fn {_m, not_enabled} -> not not_enabled end)
      |> Enum.map(fn {module, _e} -> module end)

    if children != [] do
      spawn(fn ->
        do_registration(
          Config.registration_attempts(),
          0,
          Config.registration_attempts_interval()
        )
      end)
    end

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  defp metrics_child_spec do
    if Config.fast_metrics() do
      # Use Supervisor child_spec to set ID to Unleash.Metrics for compatibility
      Supervisor.child_spec({MetricsFast, []}, id: Metrics)
    else
      {Metrics, name: Metrics}
    end
  end

  def do_registration(n, n, _) do
    Logger.error(
      "#{Config.appname()} #{__MODULE__}; Failed to register unleash client after #{n} attempts"
    )
  end

  def do_registration(n, m, interval) do
    case Config.client().register_client() do
      {:ok, _} ->
        Logger.info(
          "#{Config.appname()} #{__MODULE__} uleash client was registered after #{m + 1} attempts"
        )

        :ok

      {:error, reason} ->
        Logger.warning("#{Config.appname()} #{__MODULE__}; Failed to register unleash client",
          reason: reason
        )

        :timer.sleep(interval)
        do_registration(n, m + 1, interval)
    end
  end
end
