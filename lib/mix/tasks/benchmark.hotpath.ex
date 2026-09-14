defmodule Mix.Tasks.Benchmark.Hotpath do
  @moduledoc """
  Benchmarks the full Unleash.enabled?/3 and get_variant/3 hot path
  under different configuration combinations.

  Usage:
      mix benchmark.hotpath
  """

  use Mix.Task

  @compile {:no_warn_undefined, Unleash.CompiledFeatures}

  alias Unleash.Config
  alias Unleash.Feature
  alias Unleash.FeatureCompiler
  alias Unleash.Strategy
  alias Unleash.Variant

  @shortdoc "Benchmark the full enabled?/get_variant hot path"

  def run(_args) do
    Mix.Task.run("app.start", ["--no-start"])
    Application.ensure_all_started(:telemetry)

    features = build_features()
    setup_compiled(features)
    setup_metrics_fast(features)

    context = %{user_id: "50", session_id: "sess-123", remote_address: "10.0.0.1"}

    IO.puts("\n=== Hot Path Benchmark: Unleash.enabled?/3 ===\n")
    IO.puts("Features: #{length(features)}")
    IO.puts("Context: #{inspect(context)}\n")

    # Benchmark enabled?
    bench_enabled(features, context)

    IO.puts("\n=== Hot Path Benchmark: Unleash.get_variant/3 ===\n")

    # Benchmark get_variant
    bench_get_variant(features, context)

    IO.puts("\n=== Component Breakdown ===\n")

    # Benchmark individual components
    bench_components(features, context)
  end

  defp bench_enabled(_features, context) do
    feature_name = "user_check"

    # --- telemetry OFF, fast_metrics ---
    Application.put_env(:unleash, :disable_client, false)
    Application.put_env(:unleash, :disable_telemetry, true)
    Application.put_env(:unleash, :fast_metrics, true)

    IO.puts("--- Config: telemetry OFF, fast_metrics ON ---")
    Benchee.run(
      %{"enabled? (telemetry OFF, fast_metrics)" => fn ->
        Unleash.enabled?(feature_name, context)
      end},
      time: 3, warmup: 1, memory_time: 1, print: [configuration: false]
    )

    # --- telemetry ON, fast_metrics ---
    Application.put_env(:unleash, :disable_telemetry, false)

    IO.puts("--- Config: telemetry ON, fast_metrics ON ---")
    Benchee.run(
      %{"enabled? (telemetry ON, fast_metrics)" => fn ->
        Unleash.enabled?(feature_name, context)
      end},
      time: 3, warmup: 1, memory_time: 1, print: [configuration: false]
    )

    # --- telemetry ON, genserver metrics ---
    Application.put_env(:unleash, :fast_metrics, false)

    IO.puts("--- Config: telemetry ON, GenServer metrics ---")
    Benchee.run(
      %{"enabled? (telemetry ON, genserver metrics)" => fn ->
        Unleash.enabled?(feature_name, context)
      end},
      time: 3, warmup: 1, memory_time: 1, print: [configuration: false]
    )

    # Reset
    Application.put_env(:unleash, :fast_metrics, true)
  end

  defp bench_get_variant(_features, context) do
    feature_name = "variant_feature"

    Application.put_env(:unleash, :disable_client, false)
    Application.put_env(:unleash, :fast_metrics, true)
    Application.put_env(:unleash, :disable_telemetry, true)

    IO.puts("--- Config: telemetry OFF, fast_metrics ON ---")
    Benchee.run(
      %{"get_variant (telemetry OFF, fast_metrics)" => fn ->
        Unleash.get_variant(feature_name, context)
      end},
      time: 3, warmup: 1, memory_time: 1, print: [configuration: false]
    )

    Application.put_env(:unleash, :disable_telemetry, false)

    IO.puts("--- Config: telemetry ON, fast_metrics ON ---")
    Benchee.run(
      %{"get_variant (telemetry ON, fast_metrics)" => fn ->
        Unleash.get_variant(feature_name, context)
      end},
      time: 3, warmup: 1, memory_time: 1, print: [configuration: false]
    )
  end

  defp bench_components(_features, context) do
    feature_name = "user_check"

    Benchee.run(
      %{
        "persistent_term.get (config flag)" => fn ->
          :persistent_term.get(:unleash_cfg_disable_telemetry, false)
        end,
        "Application.get_env (config flag)" => fn ->
          Application.get_env(:unleash, :disable_telemetry, false)
        end,
        "FeatureCompiler.compiled?()" => fn ->
          FeatureCompiler.compiled?()
        end,
        "CompiledFeatures.enabled?" => fn ->
          Unleash.CompiledFeatures.enabled?(feature_name, context)
        end,
        "FeatureCompiler.get_feature" => fn ->
          FeatureCompiler.get_feature(feature_name)
        end,
        "MetricsFast.add_metric" => fn ->
          f = FeatureCompiler.get_feature(feature_name)
          Unleash.MetricsFast.add_metric({f, true})
        end
      },
      time: 3,
      warmup: 1,
      memory_time: 1,
      print: [configuration: false]
    )
  end

  defp build_features do
    [
      %Feature{
        name: "user_check",
        enabled: true,
        strategies: [
          Strategy.update_map(%{
            "name" => "userWithId",
            "parameters" => %{"userIds" => "1,2,50,100"},
            "constraints" => []
          })
        ]
      },
      %Feature{
        name: "variant_feature",
        enabled: true,
        strategies: [
          Strategy.update_map(%{
            "name" => "default",
            "parameters" => %{},
            "constraints" => []
          })
        ],
        variants: [
          %Variant{name: "A", weight: 50, payload: %{"type" => "string", "value" => "a"}},
          %Variant{name: "B", weight: 50, payload: %{"type" => "string", "value" => "b"}}
        ]
      },
      %Feature{
        name: "simple_default",
        enabled: true,
        strategies: [
          Strategy.update_map(%{
            "name" => "default",
            "parameters" => %{},
            "constraints" => []
          })
        ]
      }
    ]
  end

  defp setup_compiled(features) do
    FeatureCompiler.compile_all(features)
  end

  defp setup_metrics_fast(features) do
    # Start MetricsFast if not running
    case GenServer.whereis(Unleash.MetricsFast) do
      nil ->
        {:ok, _} = Unleash.MetricsFast.start_link([])

      _pid ->
        :ok
    end

    Unleash.MetricsFast.register_features(features)
  end
end
