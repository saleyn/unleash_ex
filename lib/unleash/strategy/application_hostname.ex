defmodule Unleash.Strategy.ApplicationHostname do
  use Unleash.Strategy, name: "ApplicationHostname"

  alias Unleash.Strategy.Utils

  def enabled?(%{"hostnames" => hostnames}, _context) do
    case :inet.gethostname() do
      {:ok, hostname} ->
        {Utils.in_list?(hostname, hostnames, &String.downcase/1),
         %{hostname: hostname, hostnames: hostnames}}
    end
  end

  def enabled?(_params, _context), do: false
end
