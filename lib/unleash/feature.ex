defmodule Unleash.Feature do
  @moduledoc false

  alias Unleash.Strategy
  alias Unleash.Variant

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

  def enabled?(%__MODULE__{enabled: enabled, strategies: strat}, context)
      when is_list(strat) do
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
