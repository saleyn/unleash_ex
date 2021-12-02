defmodule Unleash.CacheTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Unleash.Cache
  alias Unleash.Feature

  @existing_feature %Feature{name: "exists"}
  @existing_features [%Feature{name: "exists"}]

  @new_feature %Feature{name: "new"}
  @new_features [%Feature{name: "new"}]

  setup context do
    Cache.init([], context.test)

    assert :ok == Cache.upsert_features(@existing_features, context.test)

    {:ok, table_name: context.test}
  end

  describe "get_feature/1" do
    test "get_feature succeeds if the feature name is present", %{table_name: table_name} do
      assert @existing_feature == Cache.get_feature(@existing_feature.name, table_name)
    end

    test "get_feature fails if the key does not exist", %{table_name: table_name} do
      assert nil == Cache.get_feature(@new_feature.name, table_name)
    end
  end

  describe "get_all_feature_names/1" do
    test "get_all_feature_names succeeds", %{
      table_name: table_name
    } do
      assert :ok == Cache.upsert_features(@new_features ++ @existing_features, table_name)

      assert [@existing_feature.name, @new_feature.name] ==
               Cache.get_all_feature_names(table_name)
    end
  end

  describe "upsert_features/2" do
    test "upsert overwrites existing features", %{
      table_name: table_name
    } do
      assert :ok == Cache.upsert_features(@new_features, table_name)

      assert nil == Cache.get_feature(@existing_feature.name, table_name)
      assert @new_feature == Cache.get_feature(@new_feature.name, table_name)
    end
  end
end
