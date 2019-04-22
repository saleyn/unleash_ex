defmodule Unleash.Strategy.RemoteAddress do
  use Unleash.Strategy, name: "RemoteAddress"

  @impl Strategy
  def enabled?(%{"ips" => list}, %{remote_address: address})
      when is_binary(list) and is_binary(address) do
    result =
      list
      |> String.split(",")
      |> Stream.map(&String.trim/1)
      |> Enum.member?(address)

    {result, %{ips: list, remote_address: address}}
  end
end
