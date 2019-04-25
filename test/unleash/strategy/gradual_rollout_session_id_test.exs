defmodule Unleash.Strategy.GradualRolloutSessionIdTest do
  use ExUnit.Case
  use ExUnitProperties

  alias Unleash.Strategy.GradualRolloutSessionId
  alias Unleash.Strategy.Utils

  describe "enabled?" do
    property "returns false if the session is empty" do
      check all group_id <- binary(),
                session <- constant(""),
                percentage <- integer(1..100) do
        refute GradualRolloutSessionId.enabled?(
                 %{"percentage" => percentage, "groupId" => group_id},
                 %{session_id: session}
               )
      end
    end

    property "checks if the session and group are within the normalized percentage" do
      check all group_id <- binary(),
                session <- binary(min_length: 1),
                percentage <- integer(1..100),
                {:ok, result} = {:ok, percentage >= Utils.normalize(session, group_id)} do
        assert {^result, _} =
                 GradualRolloutSessionId.enabled?(
                   %{"percentage" => percentage, "groupId" => group_id},
                   %{session_id: session}
                 )
      end
    end

    property "returns false if the percentage is 0" do
      check all group_id <- binary(),
                session <- binary(min_length: 1),
                percentage <- constant(0) do
        assert {false, _} =
                 GradualRolloutSessionId.enabled?(
                   %{"percentage" => percentage, "groupId" => group_id},
                   %{session_id: session}
                 )
      end
    end
  end
end
