defmodule Unleash.Strategy.FlexibleRollout do
  @moduledoc """
  Can depend on `:user_id` or `:session_id` in `t:Unleash.context/0`

  Based on the
  [`flexibleRollout`](https://unleash.github.io/docs/activation_strategy#flexiblerollout)
  strategy.
  """

  use Unleash.Strategy, name: "FlexibleRollout"
  alias Unleash.Strategy.Utils
  alias Unleash.Stickiness

  def enabled?(%{"rollout" => percentage} = params, context) when is_number(percentage) do
    sticky_value =
      params
      |> Map.get("stickiness", "")
      |> Stickiness.get_seed(context)

    group = Map.get(params, "groupId", Map.get(params, :feature_toggle, ""))

    if sticky_value do
      {percentage > 0 and Utils.normalize(sticky_value, group) <= percentage,
       %{
         group: group,
         percentage: percentage,
         sticky_value: sticky_value,
         stickiness: Map.get(params, "stickiness")
       }}
    else
      {false,
       %{
         group: group,
         percentage: percentage,
         sticky_value: sticky_value,
         stickiness: Map.get(params, "stickiness")
       }}
    end
  end

  def enabled?(%{"rollout" => percentage} = params, context),
    do: enabled?(%{params | "rollout" => Utils.parse_int(percentage)}, context)
end
