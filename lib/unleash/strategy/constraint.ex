defmodule Unleash.Strategy.Constraint do
  @moduledoc """
  Module that is used to verify
  [constraints](https://www.unleash-hosted.com/docs/strategy-constraints/) are
  met.

  These constraints allow for very complex and specifc strategies to be
  enacted by allowing users to specify context values to include or exclude.
  """

  @doc """
  Pre-resolves `constraint["contextName"]` into the context-map atom key it
  will be looked up under (e.g. `"userId"` -> `:user_id`), stashing it as
  `"contextNameAtom"`. `contextName` is invariant for the lifetime of the
  constraint (it only changes when the next features poll replaces it), but
  computing it involves a regex-based case conversion (`Recase.to_snake/1`)
  plus an atom-table lookup/creation — real per-call cost if left to
  `find_value/2` to recompute on every single evaluation. Called once per
  constraint when features are parsed, from `Unleash.Strategy.update_map/1`.
  """
  def precompute_context_atom(%{"contextName" => name} = constraint) do
    Map.put(constraint, "contextNameAtom", context_name_atom(name))
  end

  def precompute_context_atom(constraint), do: constraint

  def verify_all(constraints, context) do
    Enum.all?(constraints, &verify(&1, context))
  end

  defp verify(
         %{"contextName" => name, "operator" => op, "inverted" => inverted} = constraint,
         context
       ) do
    name_atom = Map.get(constraint, "contextNameAtom") || context_name_atom(name)

    context
    |> find_value(name, name_atom)
    |> check(op, constraint)
    |> invert(inverted)
  end

  defp verify(%{}, _context), do: false

  defp context_name_atom(name), do: String.to_atom(Recase.to_snake(name))

  defp check(nil, _, _), do: false

  defp check(value, "IN", %{"values" => values}), do: value in values
  defp check(value, "NOT_IN", %{"values" => values}), do: value not in values

  defp check(daytime, "DATE_AFTER", %{"value" => value}),
    do: daytime |> compare_dates(value) == :gt

  defp check(daytime, "DATE_BEFORE", %{"value" => value}),
    do: daytime |> compare_dates(value) == :lt

  defp check(str, "STR_CONTAINS", %{"values" => values}),
    do: str |> String.contains?(values)

  defp check(str, "STR_STARTS_WITH", %{"values" => values}),
    do: str |> String.starts_with?(values)

  defp check(str, "STR_ENDS_WITH", %{"values" => values}),
    do: str |> String.ends_with?(values)

  defp check(numb, "NUM_EQ", %{"value" => value}) do
    case to_numbers(numb, value) do
      :error -> false
      {n, m} -> n == m
    end
  end

  defp check(numb, "NUM_GT", %{"value" => value}) do
    case to_numbers(numb, value) do
      :error -> false
      {n, m} -> n > m
    end
  end

  defp check(numb, "NUM_GTE", %{"value" => value}) do
    case to_numbers(numb, value) do
      :error -> false
      {n, m} -> n >= m
    end
  end

  defp check(numb, "NUM_LE", %{"value" => value}) do
    case to_numbers(numb, value) do
      :error -> false
      {n, m} -> n < m
    end
  end

  defp check(numb, "NUM_LTE", %{"value" => value}) do
    case to_numbers(numb, value) do
      :error -> false
      {n, m} -> n <= m
    end
  end

  defp check(semver, "SEMVER_EQ", %{"value" => value}),
    do: cmp_semver(semver, value, &Kernel.==/2)

  defp check(semver, "SEMVER_GT", %{"value" => value}), do: cmp_semver(semver, value, &Kernel.>/2)
  defp check(semver, "SEMVER_LT", %{"value" => value}), do: cmp_semver(semver, value, &Kernel.</2)

  defp find_value(nil, _name, _name_atom), do: nil

  defp find_value(ctx, name, name_atom) do
    Map.get(
      ctx,
      name_atom,
      find_value(Map.get(ctx, :properties), name, name_atom)
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

  def to_numbers(a, b) do
    case to_number(a) do
      :error ->
        :error

      n ->
        case to_number(b) do
          :error -> :error
          m -> {n, m}
        end
    end
  end

  def to_number(str) when is_binary(str) do
    case Integer.parse(str, 10) do
      {int, ""} -> int
      {_, _} -> to_real(str)
      _ -> :error
    end
  end

  def to_number(num) when is_number(num), do: num
  def to_number(_), do: :error

  defp to_real(str) when is_binary(str) do
    case Float.parse(str) do
      {float, _} -> float
      _ -> :error
    end
  end

  def mk_semver(version) when is_binary(version) do
    l = for x <- String.split(version, "."), do: Integer.parse(x, 10)
    mk_semver(for y <- l, do: elem(y, 0))
  end

  def mk_semver(version) when is_list(version), do: mk_semver(List.to_tuple(version))

  def mk_semver({a}), do: {a, 0, 0}
  def mk_semver({a, b}), do: {a, b, 0}
  def mk_semver({a, b, c}), do: {a, b, c}

  def mk_semver(version) when is_tuple(version),
    do: {elem(version, 0), elem(version, 1), elem(version, 2)}

  def cmp_semver(v1, v2, pred), do: pred.(mk_semver(v1), mk_semver(v2))
end
