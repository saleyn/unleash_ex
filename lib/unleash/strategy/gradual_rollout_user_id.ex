defmodule Unleash.Strategy.GradualRolloutUserId do
  @moduledoc """
  Requires `:user_id` in `t:Unleash.context/0`

  Based on the
  [`gradualRolloutUserId`](https://unleash.github.io/docs/activation_strategy#gradualrolloutuserid)
  strategy.
  """

  use Unleash.Strategy, name: "GradualRolloutUserId"
  alias Unleash.Strategy.Utils

  def enabled?(_params, %{user_id: ""}), do: false

  def enabled?(_params, %{user_id: nil}), do: false

  def enabled?(%{"percentage" => percentage, "groupId" => group_id}, %{user_id: user_id})
      when is_binary(group_id) and is_binary(user_id) do
    result =
      percentage
      |> Utils.parse_int()
      |> (&(&1 > 0 and Utils.normalize(user_id, group_id) <= &1)).()

    {result, %{group: group_id, user: user_id, percentage: percentage}}
  end

  def enabled?(%{"percentage" => _p} = params, %{user_id: _s} = context) do
    enabled?(%{params | "groupId" => ""}, context)
  end

  def enabled?(_params, _context), do: false
end
