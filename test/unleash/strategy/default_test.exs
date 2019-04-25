defmodule Unleash.Strategy.DefaultTest do
  use ExUnit.Case

  alias Unleash.Strategy.Default

  describe "enabled?" do
    test "it returns true" do
      assert Default.enabled?(%{}, %{})
    end
  end
end
