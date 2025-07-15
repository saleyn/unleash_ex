defmodule Unleash.Variant do
  @moduledoc false
  alias Unleash.Stickiness
  alias Unleash.Feature
  alias Unleash.Strategy
  alias Unleash.Strategy.Utils

  @derive Jason.Encoder
  defstruct name: "", # Name is the value of the variant name.
            payload: %{}, # Payload is the value of the variant payload
            enabled: true, # Enabled indicates whether the variant is enabled. This is only false when it's a default variant
            feature_enabled: false, # FeatureEnabled indicates whether the Feature for this variant is enabled
            weight: 0, # Weight is the traffic ratio for the request
            stickiness: "",
            overrides: [] # Override is used to get a variant according to the Unleash context field

  @type t :: %{
    enabled: boolean(),
    name: String.t(),
    payload: map(),
    feature_enabled: boolean(),
    weight: integer(),
    stickiness: binary()}

  @type result :: %{
          required(:enabled) => boolean(),
          required(:name) => String.t(),
          optional(:payload) => map()
        }

  def select_variant(
        %Feature{variants: variants, strategies: strategies, name: name} = feature,
        context
      ) do

    sticky_field = case variants do
      [%__MODULE__{stickiness: sticky_field} | _] ->
          sticky_field
      _ ->
        "default"
    end
    seed = Stickiness.get_seed(sticky_field, context)
    {variant, metadata} =
      case Feature.enabled?(feature, context) do
        {true, _} -> variants(variants(strategies, context) ++ variants, name, context, seed)
        _ -> {disabled(), %{reason: :feature_disabled}}
      end

    common_metadata = %{
      seed: seed,
      variants: Enum.map(variants, &{&1.name, &1.weight})
    }

    {variant, Map.merge(metadata, common_metadata)}
  end

  def from_map(map) when is_map(map) do
    %__MODULE__{
      name: Map.get(map, "name", ""),
      payload: Map.get(map, "payload", %{}),
      enabled: Map.get(map, "enabled", %{}),
      feature_enabled: Map.get(map, "feature_enabled", %{}),
      weight: Map.get(map, "weight", 0),
      stickiness: Map.get(map, "stickiness"),
      overrides: Map.get(map, "overrides", [])
    }
  end

  def to_map(%__MODULE__{name: "disabled" = name}) do
    %{
      enabled: false,
      name: name
    }
  end

  def to_map(%__MODULE__{name: name, payload: payload}, enabled \\ false) do
    %{
      enabled: enabled,
      name: name,
      payload: payload
    }
  end

  defp find_variant(variants, target) do
    Enum.reduce_while(variants, 0, fn v, acc ->
      case acc + v.weight do
        x when x < target -> {:cont, x}
        _ -> {:halt, v}
      end
    end)
  end

  defp find_override(variants, context) do
    variants
    |> Enum.filter(fn v -> check_variant_for_override(v, context) end)
    |> Enum.at(0)
  end

  defp check_variant_for_override(%__MODULE__{overrides: []}, _context), do: false

  defp check_variant_for_override(%__MODULE__{overrides: overrides}, context) do
    Enum.any?(overrides, fn %{"contextName" => name, "values" => values} ->
      Enum.any?(values, fn v -> v === context[Stickiness.sticky_context_field(name)] end)
    end)
  end

  def disabled do
    %{
      enabled: false,
      name: "disabled"
    }
  end

  defp variants(variants, name, context, seed)
       when is_list(variants) and length(variants) > 0 do
    total_weight =
      variants
      |> Enum.map(fn %{weight: w} -> w end)
      |> Enum.sum()

    metadata = %{
      seed: seed,
      variants: Enum.map(variants, &{&1.name, &1.weight}),
      reason: nil
    }

    variants
    |> find_override(context)
    |> case do
      nil ->
        variant =
          find_variant(
            variants,
            Utils.normalize(seed, name, total_weight)
          )

        {to_map(variant, true), %{metadata | reason: :variant_selected}}

      variant ->
        {to_map(variant, true), %{metadata | reason: :override_found}}
    end
  end

  defp variants(_variants, _name, _context, _seed), do: {disabled(), %{reason: :feature_has_no_variants}}

  defp variants([], _context), do: []

  defp variants([strategy | tail], context) do
    case Strategy.enabled?(strategy, context) do
      true -> Map.get(strategy, "variants", []) ++ variants(tail, context)
      {true, _} -> Map.get(strategy, "variants", []) ++ variants(tail, context)
      _ -> variants(tail, context)
    end
  end
end
