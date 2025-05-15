defmodule Unleash.Strategy.Constraint do
  @moduledoc """
  Module that is used to verify
  [constraints](https://www.unleash-hosted.com/docs/strategy-constraints/) are
  met.

  These constraints allow for very complex and specifc strategies to be
  enacted by allowing users to specify context values to include or exclude.
  """

  def verify_all(constraints, context) do
    Enum.all?(constraints, &verify(&1, context))
  end

  defp verify(%{"contextName" => name, "operator" => op, "inverted" => inverted} = constrain, context) do
    context
    |> find_value(name)
    |> check(op, constrain)
    |> invert(inverted)
  end

  defp verify(%{}, _context), do: false

  defp check(value, "IN", %{"values" => values}), do: value in values
  defp check(value, "NOT_IN", %{"values" => values}), do: value not in values
  defp check(_, "DATE_AFTER", %{"value" => value}), do: compare_date(value) == :gt
  defp check(_, "DATE_BEFORE", %{"value" => value}), do: compare_date(value) == :lt
  defp check(nil, _, _), do: false

  defp find_value(nil, _name), do: nil

  defp find_value(ctx, name) do
    Map.get(
      ctx,
      String.to_atom(Recase.to_snake(name)),
      find_value(Map.get(ctx, :properties), name)
    )
  end

  defp invert(result, true), do: !result
  defp invert(result, _), do: result

  defp compare_date(nil), do: false

  defp compare_date(value) do
    case DateTime.from_iso8601(value) do
      {:ok, date, _shift} ->
        DateTime.utc_now()
        |> DateTime.compare(date)

      _ ->
        false
    end
  end

end
