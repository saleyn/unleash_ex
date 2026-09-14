defmodule Unleash.FeatureCompilerTest do
  use ExUnit.Case, async: true

  @compile {:no_warn_undefined, Unleash.CompiledFeatures}

  alias Unleash.Feature
  alias Unleash.FeatureCompiler

  setup do
    on_exit(fn ->
      for name <- :persistent_term.get(:unleash_compiled_names, []) do
        :persistent_term.erase({:unleash_feature, name})
      end

      :persistent_term.erase(:unleash_compiled_names)
      :code.purge(Unleash.CompiledFeatures)
      :code.delete(Unleash.CompiledFeatures)
    end)

    :ok
  end

  describe "compile_all/1" do
    test "compiles a disabled feature — enabled? returns false" do
      feature = %Feature{name: "disabled_feat", enabled: false}
      FeatureCompiler.compile_all([feature])

      assert Unleash.CompiledFeatures.enabled?("disabled_feat", %{}) == false
    end

    test "compiles an enabled feature with no strategies — returns true" do
      feature = %Feature{name: "always_on", enabled: true, strategies: []}
      FeatureCompiler.compile_all([feature])

      assert Unleash.CompiledFeatures.enabled?("always_on", %{}) == true
    end

    test "compiles a feature with default strategy" do
      feature = %Feature{
        name: "with_default",
        enabled: true,
        strategies: [
          %{"name" => "default", "parameters" => %{}, "constraints" => []}
        ]
      }

      FeatureCompiler.compile_all([feature])

      assert Unleash.CompiledFeatures.enabled?("with_default", %{}) == true
    end

    test "compiles a feature with userWithId strategy" do
      feature = %Feature{
        name: "user_check",
        enabled: true,
        strategies: [
          %{
            "name" => "userWithId",
            "parameters" => %{"userIds" => "1,2,3"},
            "constraints" => []
          }
        ]
      }

      FeatureCompiler.compile_all([feature])

      assert Unleash.CompiledFeatures.enabled?("user_check", %{user_id: "2"}) == true
      assert Unleash.CompiledFeatures.enabled?("user_check", %{user_id: "99"}) == false
    end

    test "compiles a feature with NUM_LTE constraint" do
      feature = %Feature{
        name: "num_constrained",
        enabled: true,
        strategies: [
          %{
            "name" => "default",
            "parameters" => %{},
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
          }
        ]
      }

      FeatureCompiler.compile_all([feature])

      # user_id 50 <= 100 → passes constraint → default strategy → true
      assert Unleash.CompiledFeatures.enabled?("num_constrained", %{user_id: "50"}) == true
      # user_id 200 > 100 → fails constraint → false
      assert Unleash.CompiledFeatures.enabled?("num_constrained", %{user_id: "200"}) == false
    end

    test "precomputes NUM constraint values" do
      feature = %Feature{
        name: "precomputed_num",
        enabled: true,
        strategies: [
          %{
            "name" => "default",
            "parameters" => %{},
            "constraints" => [
              %{
                "contextName" => "userId",
                "operator" => "NUM_GT",
                "value" => "42",
                "values" => [],
                "inverted" => false,
                "caseInsensitive" => false
              }
            ]
          }
        ]
      }

      FeatureCompiler.compile_all([feature])

      assert Unleash.CompiledFeatures.enabled?("precomputed_num", %{user_id: "100"}) == true
      assert Unleash.CompiledFeatures.enabled?("precomputed_num", %{user_id: "10"}) == false
    end

    test "handles IN constraint" do
      feature = %Feature{
        name: "in_constrained",
        enabled: true,
        strategies: [
          %{
            "name" => "default",
            "parameters" => %{},
            "constraints" => [
              %{
                "contextName" => "userId",
                "operator" => "IN",
                "value" => "",
                "values" => ["alice", "bob"],
                "inverted" => false,
                "caseInsensitive" => false
              }
            ]
          }
        ]
      }

      FeatureCompiler.compile_all([feature])

      assert Unleash.CompiledFeatures.enabled?("in_constrained", %{user_id: "alice"}) == true
      assert Unleash.CompiledFeatures.enabled?("in_constrained", %{user_id: "charlie"}) == false
    end

    test "stores feature struct for variant access" do
      feature = %Feature{name: "with_variants", enabled: true, strategies: []}
      FeatureCompiler.compile_all([feature])

      assert FeatureCompiler.get_feature("with_variants") == feature
    end

    test "handles inverted constraints" do
      feature = %Feature{
        name: "inverted",
        enabled: true,
        strategies: [
          %{
            "name" => "default",
            "parameters" => %{},
            "constraints" => [
              %{
                "contextName" => "userId",
                "operator" => "IN",
                "value" => "",
                "values" => ["blocked"],
                "inverted" => true,
                "caseInsensitive" => false
              }
            ]
          }
        ]
      }

      FeatureCompiler.compile_all([feature])

      # "blocked" is in the list but inverted → false
      assert Unleash.CompiledFeatures.enabled?("inverted", %{user_id: "blocked"}) == false
      # "allowed" is not in the list, inverted → true
      assert Unleash.CompiledFeatures.enabled?("inverted", %{user_id: "allowed"}) == true
    end

    test "handles multiple strategies with OR semantics" do
      feature = %Feature{
        name: "multi_strat",
        enabled: true,
        strategies: [
          %{
            "name" => "userWithId",
            "parameters" => %{"userIds" => "1,2"},
            "constraints" => []
          },
          %{
            "name" => "default",
            "parameters" => %{},
            "constraints" => []
          }
        ]
      }

      FeatureCompiler.compile_all([feature])

      # Even if userWithId fails, default always passes (OR semantics)
      assert Unleash.CompiledFeatures.enabled?("multi_strat", %{user_id: "99"}) == true
    end
  end

  describe "enabled?/2 fallback" do
    test "returns nil for unknown features" do
      FeatureCompiler.compile_all([%Feature{name: "known", enabled: true, strategies: []}])
      assert Unleash.CompiledFeatures.enabled?("nonexistent", %{}) == nil
    end
  end

  describe "get_feature/1" do
    test "returns nil for unknown features" do
      assert FeatureCompiler.get_feature("nonexistent") == nil
    end

    test "accepts atom names" do
      feature = %Feature{name: "atom_test", enabled: true, strategies: []}
      FeatureCompiler.compile_all([feature])

      assert FeatureCompiler.get_feature(:atom_test) != nil
    end
  end

  describe "concurrent recompilation safety" do
    test "callers survive recompilation (soft_purge does not kill mid-call processes)" do
      # Compile initial version
      feature_v1 = %Feature{name: "hot_swap", enabled: true, strategies: []}
      FeatureCompiler.compile_all([feature_v1])

      # Spawn many processes that continuously call enabled? in a tight loop
      caller_count = 20
      iterations = 5_000
      parent = self()

      callers =
        for i <- 1..caller_count do
          spawn_link(fn ->
            results =
              for _ <- 1..iterations do
                # This call executes in the caller's process — if :code.purge
                # were used, the process would be killed mid-execution
                Unleash.CompiledFeatures.enabled?("hot_swap", %{})
              end

            send(parent, {:done, i, Enum.all?(results, &(&1 in [true, false, nil]))})
          end)
        end

      # Meanwhile, recompile repeatedly to trigger purge/swap
      for _ <- 1..20 do
        feature_v2 = %Feature{name: "hot_swap", enabled: true, strategies: []}
        FeatureCompiler.compile_all([feature_v2])
        Process.sleep(1)
      end

      # All caller processes should survive without being killed
      for _ <- 1..caller_count do
        assert_receive {:done, _i, true}, 5_000
      end

      # Verify no callers died (spawn_link would propagate the exit)
      assert Process.alive?(self())
    end
  end

  describe "cleanup/1" do
    test "removes stale persistent_term entries" do
      features = [
        %Feature{name: "keep", enabled: true, strategies: []},
        %Feature{name: "remove_me", enabled: true, strategies: []}
      ]

      FeatureCompiler.compile_all(features)
      assert FeatureCompiler.get_feature("remove_me") != nil

      # Now only "keep" exists
      FeatureCompiler.cleanup([%Feature{name: "keep", enabled: true}])
      assert FeatureCompiler.get_feature("remove_me") == nil
      assert FeatureCompiler.get_feature("keep") != nil
    end
  end
end
