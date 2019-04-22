defmodule Unleash.Feature do
  alias Unleash.Config
  alias Unleash.Strategy
  require Logger

  defstruct name: "",
            description: "",
            enabled: false,
            strategies: []

  def from_map(map) when is_map(map) do
    %__MODULE__{
      name: map["name"],
      description: map["description"],
      enabled: map["enabled"],
      strategies: map["strategies"]
    }
  end

  def from_map(_), do: %__MODULE__{}

  def enabled?(nil), do: false

  def enabled?(%__MODULE__{enabled: enabled, strategies: strat})
      when is_list(strat) and length(strat) == 0,
      do: enabled

  def enabled?(%__MODULE__{enabled: enabled, strategies: strat} = feature)
      when is_list(strat) do
    Logger.debug(fn ->
      strat
      |> Stream.map(&Map.get(&1, "name", ""))
      |> Enum.join(", ")
      |> (&"Strategies for feature #{feature.name} are: #{&1}").()
    end)

    strat
    |> Enum.map(fn strategy ->
      Strategy.enabled?(strategy, %{})
    end)
    |> Enum.any?(fn enabled? -> enabled or enabled? end)
    |> Kernel.and(enabled)
  end
end
