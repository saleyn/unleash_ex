defmodule Unleash.Strategy.RemoteAddressTest do
  use ExUnit.Case
  use ExUnitProperties

  alias Unleash.Strategy.RemoteAddress

  describe "enabled?" do
    property "returns true if an IP is in the list" do
      check all(
              list <-
                map(nonempty(list_of(string(:alphanumeric, min_length: 1))), fn list ->
                  Enum.map(list, &String.replace(&1, ",", ""))
                end),
              address <- member_of(list),
              ips = Enum.join(list, ",")
            ) do
        assert {true, _} = RemoteAddress.enabled?(%{"ips" => ips}, %{remote_address: address})
      end
    end

    property "returns false if an IP is not in the list" do
      check all(
              list <-
                map(nonempty(list_of(string(:alphanumeric, min_length: 1))), fn list ->
                  Enum.map(list, &String.replace(&1, ",", ""))
                end),
              address <- string(:alphanumeric, min_length: 1),
              address not in list,
              ips = Enum.join(list, ",")
            ) do
        assert {false, _} = RemoteAddress.enabled?(%{"ips" => ips}, %{remote_address: address})
      end
    end

    test "returns false with missing params" do
      refute RemoteAddress.enabled?(%{}, %{})
      refute RemoteAddress.enabled?(nil, %{})
      refute RemoteAddress.enabled?(%{}, nil)
      refute RemoteAddress.enabled?(nil, nil)
    end
  end
end
