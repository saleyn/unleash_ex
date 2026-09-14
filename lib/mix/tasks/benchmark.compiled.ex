defmodule Mix.Tasks.Benchmark.Compiled do
  @moduledoc """
  Benchmarks code-generated module evaluation vs. the ETS+interpret path.

  Usage:
      mix benchmark.compiled
  """

  use Mix.Task

  @compile {:no_warn_undefined, Unleash.CompiledFeatures}

  alias Unleash.Cache
  alias Unleash.Feature
  alias Unleash.FeatureCompiler
  alias Unleash.Strategy
  alias Unleash.Strategy.Constraint

  @shortdoc "Benchmark generated-module vs ETS-based feature evaluation"

  def run(_args) do
    Mix.Task.run("app.start", ["--no-start"])
    Application.ensure_all_started(:telemetry)

    features = build_features()
    setup_ets(features)
    setup_compiled(features)

    context = %{user_id: "50", session_id: "sess-123", remote_address: "10.0.0.1"}

    IO.puts("\n=== Code-Generated Module Benchmark ===\n")
    IO.puts("Features: #{length(features)}")
    IO.puts("Context: #{inspect(context)}\n")

    Benchee.run(
      %{
        "generated module (Module.create)" => fn ->
          Enum.each(features, fn f ->
            Unleash.CompiledFeatures.enabled?(f.name, context)
          end)
        end,
        "ets + interpret (current main path)" => fn ->
          Enum.each(features, fn f ->
            loaded = Cache.get_feature(f.name)
            Feature.enabled?(loaded, Map.put(context, :feature_toggle, loaded.name))
          end)
        end,
        "constraint only: precomputed" => fn ->
          Enum.each(features, fn f ->
            Enum.each(f.strategies, fn s ->
              constraints = s["constraints"] || []
              precomputed = Enum.map(constraints, &Constraint.precompute/1)
              Constraint.verify_all(precomputed, context)
            end)
          end)
        end,
        "constraint only: raw (no precompute)" => fn ->
          Enum.each(features, fn f ->
            Enum.each(f.strategies, fn s ->
              constraints = s["constraints"] || []
              Constraint.verify_all(constraints, context)
            end)
          end)
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
      # Simple default strategy (no constraints)
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
      },
      # userWithId strategy
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
      # flexibleRollout with NUM_LTE constraint (matches the production "ups" feature)
      %Feature{
        name: "ups_like",
        enabled: true,
        strategies: [
          Strategy.update_map(%{
            "name" => "flexibleRollout",
            "parameters" => %{
              "groupId" => "ups",
              "rollout" => "100",
              "stickiness" => "default"
            },
            "constraints" => [
              %{
                "contextName" => "userId",
                "operator" => "NUM_LTE",
                "value" => "100",
                "values" => [],
                "inverted" => false,
                "caseInsensitive" => false
              }
            ]
          })
        ]
      },
      # Multiple constraints
      %Feature{
        name: "multi_constraint",
        enabled: true,
        strategies: [
          Strategy.update_map(%{
            "name" => "default",
            "parameters" => %{},
            "constraints" => [
              %{
                "contextName" => "userId",
                "operator" => "IN",
                "value" => "",
                "values" => ["50", "51", "52"],
                "inverted" => false,
                "caseInsensitive" => false
              },
              %{
                "contextName" => "sessionId",
                "operator" => "STR_STARTS_WITH",
                "value" => "",
                "values" => ["sess-"],
                "inverted" => false,
                "caseInsensitive" => false
              }
            ]
          })
        ]
      },
      # Disabled feature
      %Feature{
        name: "disabled_feat",
        enabled: false,
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

  defp setup_ets(features) do
    try do
      :ets.delete(:unleash_cache)
    rescue
      ArgumentError -> :ok
    end

    Cache.init(features)
  end

  defp setup_compiled(features) do
    FeatureCompiler.compile_all(features)
  end
end
