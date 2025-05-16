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

  defp verify(
         %{"contextName" => name, "operator" => op, "inverted" => inverted} = constraint,
         context
       ) do
    context
    |> find_value(name)
    |> check(op, constraint)
    |> invert(inverted)
  end

  defp verify(%{}, _context), do: false

  defp check(value, "IN", %{"values" => values}), do: value in values
  defp check(value, "NOT_IN", %{"values" => values}), do: value not in values

  defp check(daytime, "DATE_AFTER", %{"value" => value}),
    do: daytime |> compare_dates(value) == :gt

  defp check(daytime, "DATE_BEFORE", %{"value" => value}),
    do: daytime |> compare_dates(value) == :lt

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

  defp compare_dates(d1, d2), do: day_adapter(d1) |> day_cpm(day_adapter(d2))

  defp day_adapter(:now), do: {:ok, DateTime.utc_now(), 0}

  defp day_adapter(day) when is_binary(day) do
    DateTime.from_iso8601(day)
  end

  defp day_adapter(_), do: {:error, "Invalid Date"}

  defp day_cpm({:ok, date1, _}, {:ok, date2, _}), do: date1 |> DateTime.compare(date2)
  defp day_cpm(_, _), do: :error
end
