defmodule Unleash.Strategy.RemoteAddress do
  use Unleash.Strategy, name: "RemoteAddress"

  alias Unleash.Strategy.Utils

  @impl Strategy
  def enabled?(%{"ips" => list}, %{remote_address: address})
      when is_binary(list) and is_binary(address) do
    {Utils.in_list?(list, address), %{ips: list, remote_address: address}}
  end

  def enabled?(_params, _context), do: false
end
