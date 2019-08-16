defmodule Unleash.Strategy.ActiveForUsersWithIdTest do
  alias Unleash.Strategy.ActiveForUsersWithId

  use ExUnit.Case
  use ExUnitProperties

  describe "enabled?" do
    property "returns true if the user is in the list" do
      check all {user_ids, user} <-
                  map(nonempty(list_of(positive_integer())), fn list ->
                    {Enum.join(list, ","), Enum.random(list)}
                  end) do
        assert {true, _} =
                 ActiveForUsersWithId.enabled?(%{"userIds" => user_ids}, %{user_id: user})
      end
    end

    property "returns false if the user is not in the list" do
      check all {user_ids, user} <-
                  map(nonempty(list_of(positive_integer())), fn list ->
                    {Enum.join(list, ","), Enum.max(list) + 1}
                  end) do
        assert {false, _} =
                 ActiveForUsersWithId.enabled?(%{"userIds" => user_ids}, %{user_id: user})
      end
    end

    test "returns false if inputs are incorrect" do
      refute ActiveForUsersWithId.enabled?(%{}, %{user_id: "2"})
      refute ActiveForUsersWithId.enabled?(%{"userIds" => "1,4,6,7"}, %{})
      refute ActiveForUsersWithId.enabled?(nil, nil)
    end
  end
end
