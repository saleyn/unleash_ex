defmodule Unleash.FeaturesTest do
  use ExUnit.Case
  use ExUnitProperties

  alias Unleash.Features
  alias Unleash.Feature

  describe "from_map" do
    test "returns a Features struct" do
      assert {:ok, %Features{}} = Features.from_map(%{"version" => "1", "features" => []})
    end

    test "returns error if given incorrect data" do
      assert {:error, _} = Features.from_map(%{})
    end

    test "maps features to a Feature struct" do
      assert {:ok, %Features{features: features}} =
               Features.from_map(%{
                 "version" => "1",
                 "features" => [
                   %{
                     "name" => "test",
                     "description" => "test",
                     "enabled" => true,
                     "strategies" => [
                       %{
                         "name" => "gradualRolloutRandom",
                         "parameters" => %{"percentage" => "21"}
                       },
                       %{
                         "name" => "gradualRolloutUserId",
                         "parameters" => %{"groupId" => "5", "percentage" => 50}
                       }
                     ]
                   }
                 ]
               })

      assert Enum.all?(features, fn f -> Kernel.match?(%Feature{}, f) end)
    end
  end

  describe "get_feature" do
    setup do
      {:ok,
       [
         features: %Features{
           features: [
             %Feature{
               description: "test",
               enabled: true,
               name: "test",
               strategies: [
                 %{
                   "name" => "gradualRolloutRandom",
                   "parameters" => %{"percentage" => "21"}
                 },
                 %{
                   "name" => "gradualRolloutUserId",
                   "parameters" => %{"groupId" => "5", "percentage" => 50}
                 }
               ]
             }
           ],
           version: "1"
         }
       ]}
    end

    test "gets features that exist in the map when the name is an atom", context do
      assert %Feature{name: "test"} = Features.get_feature(context[:features], :test)
    end

    test "gets features that exist in the map when the name is a string", context do
      assert %Feature{name: "test"} = Features.get_feature(context[:features], "test")
    end

    test "gets features that exist in the map when the name is the wrong case", context do
      assert %Feature{name: "test"} = Features.get_feature(context[:features], "TEST")
    end

    test "returns nil if the feature doesn't exist", context do
      refute Features.get_feature(context[:features], "missing")
    end
  end
end
