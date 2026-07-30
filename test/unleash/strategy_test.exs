defmodule Unleash.StrategyTest do
  use ExUnit.Case

  alias Unleash.Config
  alias Unleash.Strategy

  describe "enabled?/2" do
    test "dispatches to the matching strategy module by name" do
      assert Strategy.enabled?(%{"name" => "default", "parameters" => %{}}, %{})
    end

    test "raises for an unknown strategy name (unchanged behavior vs. the previous Enum.find + tuple-match)" do
      assert_raise KeyError, fn ->
        Strategy.enabled?(%{"name" => "not_a_real_strategy", "parameters" => %{}}, %{})
      end
    end

    test "returns false for a strategy map without a name" do
      refute Strategy.enabled?(%{}, %{})
    end

    test "still checks constraints before dispatching to the strategy module" do
      strategy =
        Unleash.Strategy.update_map(%{
          "name" => "default",
          "constraints" => [
            %{
              "contextName" => "appName",
              "operator" => "IN",
              "values" => ["unleash"],
              "inverted" => false
            }
          ]
        })

      refute Strategy.enabled?(strategy, %{app_name: "not-unleash"})
      assert Strategy.enabled?(strategy, %{app_name: "unleash"})
    end
  end

  describe "update_map/1" do
    test "pre-resolves constraint context-name atoms" do
      strategy =
        Strategy.update_map(%{
          "name" => "default",
          "constraints" => [%{"contextName" => "userId", "operator" => "IN", "values" => []}]
        })

      assert [%{"contextNameAtom" => :user_id}] = strategy["constraints"]
    end

    test "defaults constraints to an empty list when absent" do
      assert %{"name" => "default"} = Strategy.update_map(%{"name" => "default"})
    end
  end

  describe "Config.strategies_map/0" do
    test "contains the same entries as Config.strategies/0, keyed by name" do
      assert Config.strategies_map() == Map.new(Config.strategies())
    end

    test "resolves every built-in strategy name to its module" do
      map = Config.strategies_map()

      assert map["default"] == Unleash.Strategy.Default
      assert map["userWithId"] == Unleash.Strategy.ActiveForUsersWithId
      assert map["gradualRolloutUserId"] == Unleash.Strategy.GradualRolloutUserId
    end
  end
end
