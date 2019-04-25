defmodule Unleash.Strategy.GradualRolloutRandomTest do
  use ExUnit.Case
  use ExUnitProperties

  alias Unleash.Strategy.GradualRolloutRandom

  setup do
    :rand.seed(:exsplus, {101, 102, 103})
    :ok
  end

  describe "enabled?" do
    test "returns true if randomly under the percentage" do
      [1, 84, 56, 58, 76]
      |> Enum.map(fn x -> pick(StreamData.integer(x..100)) end)
      |> Enum.each(fn x ->
        assert {true, _} = GradualRolloutRandom.enabled?(%{"percentage" => x}, %{})
      end)
    end

    test "returns false if randomly over the percentage" do
      [1, 84, 56, 58, 76]
      |> Enum.map(fn x -> pick(StreamData.integer(0..(x - 1))) end)
      |> Enum.each(fn x ->
        assert {false, _} = GradualRolloutRandom.enabled?(%{"percentage" => x}, %{})
      end)
    end

    test "returns false if inputs are incorrect" do
      refute GradualRolloutRandom.enabled?(%{}, %{})
      refute GradualRolloutRandom.enabled?(nil, nil)
    end
  end
end
