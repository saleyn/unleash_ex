defmodule Unleash.Variant do
  @moduledoc false
  alias Unleash.Feature
  alias Unleash.Strategy.Utils

  @sticky_props [:user_id, :session_id, :remote_address]

  @derive Jason.Encoder
  defstruct name: "",
            weight: 0,
            payload: %{},
            overrides: []

  @type t :: %{enabled: boolean(), name: String.t(), payload: map()}
  @type result :: %{
          required(:enabled) => boolean(),
          required(:name) => String.t(),
          optional(:payload) => map()
        }

  def select_variant(%Feature{variants: variants} = feature, context)
      when is_list(variants) and length(variants) > 0 do
    case Feature.enabled?(feature, context) do
      true -> variants(feature, context)
      _ -> disabled()
    end
  end

  def from_map(map) when is_map(map) do
    %__MODULE__{
      name: map["name"],
      weight: map["weight"],
      payload: map["payload"],
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
      Enum.any?(values, fn v -> v === context[get_context_name(name)] end)
    end)
  end

  defp get_seed(context) do
    context
    |> Enum.filter(fn {k, _} ->
      Enum.member?(@sticky_props, k)
    end)
    |> Enum.at(0)
    |> case do
      nil -> to_string(:rand.uniform(100_000))
      {_, v} -> v
    end
  end

  defp get_context_name("userId"), do: :user_id
  defp get_context_name("sessionId"), do: :session_id
  defp get_context_name("remoteAddress"), do: :remote_address

  defp disabled do
    %{
      enabled: false,
      name: "disabled",
      payload: %{}
    }
  end

  defp variants(%Feature{variants: variants, name: name}, context)
       when is_list(variants) and length(variants) > 0 do
    total_weight =
      variants
      |> Enum.map(fn %{weight: w} -> w end)
      |> Enum.sum()

    variants
    |> find_override(context)
    |> case do
      nil ->
        variants
        |> find_variant(Utils.normalize(get_seed(context), name, total_weight))

      v ->
        v
    end
    |> to_map(true)
  end
end
