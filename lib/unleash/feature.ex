defmodule Unleash.Feature do
  require Logger

  defstruct name: "",
            description: "",
            enabled: false,
            strategies: []

  def enabled?(nil), do: false

  def enabled?(%__MODULE__{enabled: enabled, strategies: strat} = feature)
      when is_list(strat) and length(strat) == 0 do
    Logger.debug(fn ->
      strat
      |> Stream.map(&Map.get(&1, :name, ""))
      |> Enum.join(", ")
      |> (&"Strategies for feature #{feature.name} are: #{&1}").()
    end)

    enabled
  end
end
