defmodule Unleash.Strategy.GradualRolloutUserIdTest do
  use ExUnit.Case
  use ExUnitProperties

  alias Unleash.Strategy.GradualRolloutUserId
  alias Unleash.Strategy.Utils

  describe "enabled?" do
    property "returns false if the user is empty" do
      check all(
              group_id <- binary(),
              user <- constant(""),
              percentage <- integer(1..100)
            ) do
        refute GradualRolloutUserId.enabled?(
                 %{"percentage" => percentage, "groupId" => group_id},
                 %{user_id: user}
               )
      end
    end

    property "checks if the user and group are within the normalized percentage" do
      check all(
              group_id <- binary(),
              user <- binary(min_length: 1),
              percentage <- integer(1..100),
              {:ok, result} = {:ok, percentage >= Utils.normalize(user, group_id)}
            ) do
        assert {^result, _} =
                 GradualRolloutUserId.enabled?(
                   %{"percentage" => percentage, "groupId" => group_id},
                   %{user_id: user}
                 )
      end
    end

    property "returns false if the percentage is 0" do
      check all(
              group_id <- binary(),
              user <- binary(min_length: 1),
              percentage <- constant(0)
            ) do
        assert {false, _} =
                 GradualRolloutUserId.enabled?(
                   %{"percentage" => percentage, "groupId" => group_id},
                   %{user_id: user}
                 )
      end
    end
  end
end
