defmodule UnleashTest do
  use ExUnit.Case
  doctest Unleash

  test "greets the world" do
    assert Unleash.hello() == :world
  end
end
