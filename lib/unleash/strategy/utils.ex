defmodule Unleash.Strategy.Utils do
  @moduledoc """
  Utilities that might help you create your own strategies.

  Automatically `alias`ed when `use`ing `Unleash.Strategy`
  """

  @normalizer 100

  @doc """
  Given a comma-separated list and a member, check to see if the member is in
  the list. An optional transformation function can be passed in to apply
  to the items in the list.

  ## Examples

      iex> in_list?("a,B,c,D", "b", &String.downcase/1)
      true

      iex> in_list?("a,B,c,D", "b")
      false
  """
  def in_list?(list, member, transform \\ &noop/1)

  def in_list?(list, member, transform) when is_binary(list) do
    list
    |> String.split(",")
    |> Stream.map(&String.trim/1)
    |> Stream.map(transform)
    |> Enum.member?(member)
  end

  def in_list?(_list, _member, _transform), do: false

  @doc """
  Given an ID and group ID, normalize them using a `Murmur` hash. Used in all
  strategies that provide "stickiness".

  See the
  [`gradualRolloutUserId`](https://unleash.github.io/docs/activation_strategy#gradualrolloutuserid)
  strategy.
  """
  def normalize(id, group_id) do
    "#{group_id}:#{id}"
    |> Murmur.hash_x86_32()
    |> Integer.mod(@normalizer)
    |> Kernel.+(1)
  end

  @doc """
  Parse a string to a non-negative integer, returning only the number
  or 0 if it isn't just a number.

  ## Examples

      iex> parse_int("5")
      5

      iex> parse_int("5ab23a")
      0

      iex> parse_int(5)
      5
  """
  @spec parse_int(x :: String.t()) :: non_neg_integer()
  def parse_int(x) when is_integer(x), do: x

  def parse_int(x) do
    with {i, ""} <- Integer.parse(x),
         true <- i >= 0 do
      i
    else
      _ -> 0
    end
  end

  defp noop(x), do: x
end
