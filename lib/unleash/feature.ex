defmodule Unleash.Feature do
  @moduledoc false

  alias Unleash.Strategy
  alias Unleash.Variant
  require Logger

  @derive Jason.Encoder
  defstruct name: "",
            description: "",
            enabled: false,
            strategies: [],
            variants: %{}

  def from_map(map) when is_map(map) do
    %__MODULE__{
      name: map["name"],
      description: map["description"],
      enabled: map["enabled"],
      strategies: map["strategies"],
      variants: Enum.map(map["variants"] || [], &Variant.from_map/1)
    }
  end

  def from_map(_), do: %__MODULE__{}

  def enabled?(nil, _context), do: {false, []}

  def enabled?(%__MODULE__{enabled: enabled, strategies: []}, _context),
    do: {enabled, []}

  def enabled?(%__MODULE__{enabled: enabled, strategies: strat} = feature, context)
      when is_list(strat) do
    Logger.debug(fn ->
      strat
      |> Stream.map(&Map.get(&1, "name", ""))
      |> Enum.join(", ")
      |> (&"Strategies for feature #{feature.name} are: #{&1}").()
    end)

    strategy_evaluations =
      Enum.map(strat, fn strategy ->
        {strategy["name"], Strategy.enabled?(strategy, context)}
      end)

    result =
      strategy_evaluations
      |> Enum.any?(fn {_, enabled?} -> enabled? end)
      |> Kernel.and(enabled)

    {result, strategy_evaluations}
  end
end
