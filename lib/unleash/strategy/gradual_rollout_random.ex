defmodule Unleash.Strategy.GradualRolloutRandom do
  use Unleash.Strategy, name: "GradualRolloutRandom"

  @impl Strategy
  def enabled?(%{"percentage" => per}, _context) when is_binary(per) do
    case Integer.parse(per, 10) do
      {percentage, _} -> enabled?(percentage)
      :error -> false
    end
  end

  def enabled?(%{"percentage" => per}, _context) when is_number(per) do
    enabled?(per)
  end

  defp enabled?(percentage) do
    rand = :random.uniform(100)

    {percentage >= rand, %{percentage: percentage, random: rand}}
  end
end
