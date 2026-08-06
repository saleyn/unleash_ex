defmodule Unleash.Feature do
  @moduledoc false

  alias Unleash.Strategy
  alias Unleash.Variant

  @derive Jason.Encoder
  defstruct name: "",
            type: "",
            project: "",
            description: "",
            enabled: false,
            strategies: [],
            parameters: %{},
            variants: []

  def from_map(map) when is_map(map) do
    %__MODULE__{
      name: Map.get(map, "name", ""),
      type: Map.get(map, "type", ""),
      project: Map.get(map, "project", ""),
      description: Map.get(map, "description", ""),
      enabled: Map.get(map, "enabled", false),
      strategies: Enum.map(Map.get(map, "strategies", []) || [], &Strategy.update_map/1),
      parameters: Map.get(map, "parameters", %{}),
      variants: Enum.map(Map.get(map, "variants", []) || [], &Variant.from_map/1)
    }
  end

  def from_map(_), do: %__MODULE__{}

  def enabled?(nil, _context), do: {false, []}

  def enabled?(%__MODULE__{enabled: enabled, strategies: []}, _context),
    do: {enabled, []}

  def enabled?(%__MODULE__{enabled: enabled, strategies: strat}, context)
      when is_list(strat) do
    {result, strategy_evaluations} = evaluate_strategies(strat, context)
    {result and enabled, strategy_evaluations}
  end

  # Walks strategies in order, stopping as soon as one of them enables the
  # feature - the overall result is an OR across strategies, so nothing past
  # the first `true` can change it. `strategy_evaluations` (surfaced via
  # telemetry for debugging) therefore only contains the strategies actually
  # checked; ones skipped by the short-circuit don't appear.
  defp evaluate_strategies(strategies, context) do
    {result, evaluations} =
      Enum.reduce_while(strategies, {false, []}, fn strategy, {_, acc} ->
        enabled? = Strategy.enabled?(strategy, context)
        acc = [{strategy["name"], enabled?} | acc]

        if enabled?, do: {:halt, {true, acc}}, else: {:cont, {false, acc}}
      end)

    {result, Enum.reverse(evaluations)}
  end

  @doc false
  # Same OR-of-strategies + feature-level `enabled` semantics as `enabled?/2`,
  # but (unlike `enabled?/2`) walks every strategy without short-circuiting
  # and also collects each enabled strategy's variants list along the way.
  # `Unleash.Variant.select_variant/2` needs every enabled strategy's variants
  # regardless of which one made the feature enabled, so it can't stop early
  # - this lets it get both `feature_enabled?` and the variants in one pass
  # over `strategies` instead of two.
  @spec enabled_with_variants?(struct() | nil, Unleash.context()) :: {boolean(), list()}
  def enabled_with_variants?(%__MODULE__{enabled: enabled, strategies: []}, _context),
    do: {enabled, []}

  def enabled_with_variants?(%__MODULE__{enabled: enabled, strategies: strat}, context)
      when is_list(strat) do
    {any_enabled?, variants} =
      Enum.reduce(strat, {false, []}, fn strategy, {any_enabled?, variants} ->
        case Strategy.enabled?(strategy, context) do
          true -> {true, variants ++ Map.get(strategy, "variants", [])}
          _ -> {any_enabled?, variants}
        end
      end)

    {any_enabled? and enabled, variants}
  end
end
