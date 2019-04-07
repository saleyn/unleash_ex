defmodule Unleash.Strategy.Utils do
  @normalizer 100

  def in_list?(list, member, transform \\ &noop/1)

  def in_list?(list, member, transform) when is_binary(list) do
    list
    |> String.split(",")
    |> Stream.map(&String.trim/1)
    |> Stream.map(transform)
    |> Enum.member?(member)
  end

  def in_list?(_list, _member, _transform), do: false

  def normalize(id, group_id) do
    "#{id}:#{group_id}"
    |> Murmur.hash_x86_32()
    |> Integer.mod(@normalizer)
    |> Kernel.+(1)
  end

  @spec parse_int(x :: String.t()) :: non_neg_integer()
  def parse_int(x) do
    with {i, _} <- Integer.parse(x),
         true <- i >= 0 do
      i
    else
      _ -> 0
    end
  end

  def noop(x), do: x
end
