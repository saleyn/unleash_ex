defmodule Unleash.Strategy.ApplicationHostnameTest do
  use ExUnit.Case
  use ExUnitProperties

  alias Unleash.Strategy.ApplicationHostname

  describe "enabled?" do
    property "returns true if the hostname is in the list" do
      check all {:ok, hostname} <- constant(:inet.gethostname()),
                hosts <- nonempty(list_of(binary())),
                hostnames <- constant(Enum.join([hostname | hosts], ",")) do
        assert {true, _} = ApplicationHostname.enabled?(%{"hostnames" => hostnames}, %{})
      end
    end

    property "returns false if the hostname is in the list" do
      check all hostname <-
                  map(constant(:inet.gethostname()), fn {:ok, host} -> List.to_string(host) end),
                hostnames <- nonempty(list_of(binary())),
                hostname not in hostnames do
        assert {false, _} = ApplicationHostname.enabled?(%{"hostnames" => hostnames}, %{})
      end
    end

    test "returns false if inputs are incorrect" do
      refute ApplicationHostname.enabled?(%{}, %{})
      refute ApplicationHostname.enabled?(nil, nil)
    end
  end
end
