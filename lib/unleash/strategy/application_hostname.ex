defmodule Unleash.Strategy.ApplicationHostname do
  @moduledoc """
  Does not require anything in `t:Unleash.context/0`

  Based on the
  [`applicationHostname`](https://unleash.github.io/docs/activation_strategy#applicationhostname)
  strategy.

  """
  use Unleash.Strategy, name: "ApplicationHostname"

  alias Unleash.Strategy.Utils

  def enabled?(%{"hostnames" => hostnames}, _context) do
    with {:ok, hostname} <- :inet.gethostname(),
         hostname = List.to_string(hostname) do
      {Utils.in_list?(hostnames, hostname, &String.downcase/1),
       %{hostname: hostname, hostnames: hostnames}}
    end
  end

  def enabled?(_params, _context), do: false
end
