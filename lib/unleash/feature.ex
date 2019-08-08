defmodule Unleash.Feature do
  @moduledoc false

  alias Unleash.Strategy
  require Logger

  @derive Jason.Encoder
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

  def enabled?(nil, _context), do: false

  def enabled?(%__MODULE__{enabled: enabled, strategies: []}, _context),
    do: enabled

  def enabled?(%__MODULE__{enabled: enabled, strategies: strat} = feature, context)
      when is_list(strat) do
    Logger.debug(fn ->
      strat
      |> Stream.map(&Map.get(&1, "name", ""))
      |> Enum.join(", ")
      |> (&"Strategies for feature #{feature.name} are: #{&1}").()
    end)

    strat
    |> Enum.map(fn strategy ->
      Strategy.enabled?(strategy, context)
    end)
    |> Enum.any?(fn enabled? -> enabled? end)
    |> Kernel.and(enabled)
  end
end
