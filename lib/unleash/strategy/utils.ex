defmodule Unleash.Strategy.Utils do
  def in_list?(list, member, transform \\ &noop/1)

  def in_list?(list, member, transform) when is_binary(list) do
    list
    |> String.split(",")
    |> Stream.map(&String.trim/1)
    |> Stream.map(transform)
    |> Enum.member?(member)
  end

  def in_list?(_list, _member, _transform), do: false

  def parse_int(x) do
    case Integer.parse(x) do
      {i, _} -> i
      error -> error
    end
  end

  def noop(x), do: x
end
