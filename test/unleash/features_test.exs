defmodule Unleash.FeaturesTest do
  use ExUnit.Case
  alias Unleash.Features
  alias Unleash.Feature

  describe "enabled?" do
    test "it is false if the given state is nil" do
      refute Features.enabled?(nil, nil)
      refute Features.enabled?(nil, "")
    end

    test "it is false if the requested feature is nil" do
      refute Features.enabled?(%Features{}, nil)
    end

    test "it is false if there are no loaded features" do
      refute Features.enabled?(%Features{features: nil}, nil)
    end

    test "it is true if the requested feature is enabled" do
      state = %Features{
        features: [%Feature{enabled: true, name: "test"}]
      }

      assert Features.enabled?(state, "test")
      assert Features.enabled?(state, :test)
    end
  end
end
