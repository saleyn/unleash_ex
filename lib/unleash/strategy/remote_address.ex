defmodule Unleash.Strategy.RemoteAddress do
  @moduledoc """
  Requires `:remote_address` in `t:Unleash.context/0`

  Based on the
  [`remoteAddress`](https://unleash.github.io/docs/activation_strategy#remoteaddress)
  strategy.
  """

  use Unleash.Strategy, name: "RemoteAddress"

  alias Unleash.Strategy.Utils

  def enabled?(%{"IPs" => list}, context),
    do: enabled?(%{"ips" => list}, context)

  def enabled?(%{"ips" => _list}, %{remote_address: ""}), do: false

  def enabled?(%{"ips" => _list}, %{remote_address: nil}), do: false

  @impl Strategy
  def enabled?(%{"ips" => list}, %{remote_address: address})
      when is_binary(list) and is_binary(address) do
    {Utils.in_list?(list, address), %{ips: list, remote_address: address}}
  end

  def enabled?(_params, _context), do: false
end
