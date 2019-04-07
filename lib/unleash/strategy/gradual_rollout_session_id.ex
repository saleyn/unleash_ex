defmodule Unleash.Strategy.GradualRolloutSessionId do
  use Unleash.Strategy, name: "GradualRolloutSessionId"
  alias Unleash.Strategy.Utils

  def enabled?(_params, %{session_id: ""}), do: false

  def enabled?(%{percentage: percentage, group_id: group_id}, %{session_id: session_id})
      when is_binary(percentage) and is_binary(group_id) and is_binary(session_id) do
    result =
      percentage
      |> Utils.parse_int()
      |> (&(&1 > 0 and Utils.normalize(session_id, group_id) <= &1)).()

    {result, %{group: group_id, session: session_id, percentage: percentage}}
  end

  def enabled?(%{percentage: _p} = params, %{session_id: _s} = context) do
    enabled?(%{params | group_id: ""}, context)
  end

  def enabled?(_params, _context), do: false
end
