defmodule Unleash.Strategy.ActiveForUsersWithIdTest do
  alias Unleash.Strategy.ActiveForUsersWithId

  use ExUnit.Case

  def params, do: %{user_id_list: "1,4,6,7"}

  describe "enabled?" do
    test "returns true if the user is in the list" do
      assert ActiveForUsersWithId.enabled?(params(), %{user_id: "1"})
      assert ActiveForUsersWithId.enabled?(params(), %{user_id: 1})
    end

    test "returns false if the user is not in the list" do
      refute ActiveForUsersWithId.enabled?(params(), %{user_id: "2"})
      refute ActiveForUsersWithId.enabled?(params(), %{user_id: 2})
    end

    test "returns false if inputs are incorrect" do
      refute ActiveForUsersWithId.enabled?(%{}, %{user_id: "2"})
      refute ActiveForUsersWithId.enabled?(params(), %{})
      refute ActiveForUsersWithId.enabled?(nil, nil)
    end
  end
end
