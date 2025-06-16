defmodule Unleash.Strategy.Utils do
  @moduledoc """
  Utilities that might help you create your own strategies.

  Automatically `alias`ed when `use`ing `Unleash.Strategy`
  """
  import Bitwise

  @normalizer 100

  @c1_32 0xCC9E2D51
  @c2_32 0x1B873593
  @n_32 0xE6546B64

  defmacro mask_32(x), do: quote(do: unquote(x) &&& 0xFFFFFFFF)

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
    |> Enum.member?(transform.(member))
  end

  def in_list?(_list, _member, _transform), do: false

  @doc """
  Given an ID and group ID, normalize them using a `Murmur` hash. Used in all
  strategies that provide "stickiness".

  See the
  [`gradualRolloutUserId`](https://unleash.github.io/docs/activation_strategy#gradualrolloutuserid)
  strategy.
  """
  def normalize(id, group_id, normalizer \\ @normalizer) do
    "#{group_id}:#{id}"
    |> murmur_hash_x86_32()
    |> Integer.mod(normalizer)
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

  defp murmur_hash_x86_32(data) when is_binary(data) do
    hash =
      case body(0, data) do
        {h, []} ->
          h

        {h, t} ->
          h
          |> bxor(
            t
            |> swap_uint()
            |> Kernel.*(@c1_32)
            |> mask_32
            |> rotl32(15)
            |> Kernel.*(@c2_32)
            |> mask_32
          )
      end

    hash
    |> bxor(byte_size(data))
    |> fmix32()
  end

  @spec body(non_neg_integer, binary) :: {non_neg_integer, [binary] | binary}
  defp body(h0, <<k::size(8)-little-unit(4), t::binary>>) do
    k1 = k_32_op(k, @c1_32, 15, @c2_32)

    h0
    |> bxor(k1)
    |> rotl32(13)
    |> Kernel.*(5)
    |> Kernel.+(@n_32)
    |> mask_32
    |> body(t)
  end

  defp body(h, t) when byte_size(t) > 0, do: {h, t}
  defp body(h, _), do: {h, []}

  defp rotl32(x, r), do: mask_32(x <<< r ||| x >>> (32 - r))

  def bxor_and_shift_right(h, v), do: bxor(h, h >>> v)

  def fmix32(h) do
    h
    |> bxor_and_shift_right(16)
    |> Kernel.*(0x85EBCA6B)
    |> mask_32
    |> bxor_and_shift_right(13)
    |> Kernel.*(0xC2B2AE35)
    |> mask_32
    |> bxor_and_shift_right(16)
  end

  def k_32_op(k, c1, rotl, c2) do
    k
    |> Kernel.*(c1)
    |> mask_32
    |> rotl32(rotl)
    |> mask_32
    |> Kernel.*(c2)
    |> mask_32
  end

  @spec swap_uint(binary) :: non_neg_integer
  def swap_uint(
        <<v1::size(8), v2::size(8), v3::size(8), v4::size(8), v5::size(8), v6::size(8),
          v7::size(8), v8::size(8)>>
      ) do
    v8 <<< 56
    |> bxor(v7 <<< 48)
    |> bxor(v6 <<< 40)
    |> bxor(v5 <<< 32)
    |> bxor(v4 <<< 24)
    |> bxor(v3 <<< 16)
    |> bxor(v2 <<< 8)
    |> bxor(v1)
  end

  def swap_uint(
        <<v1::size(8), v2::size(8), v3::size(8), v4::size(8), v5::size(8), v6::size(8),
          v7::size(8)>>
      ) do
    v7 <<< 48
    |> bxor(v6 <<< 40)
    |> bxor(v5 <<< 32)
    |> bxor(v4 <<< 24)
    |> bxor(v3 <<< 16)
    |> bxor(v2 <<< 8)
    |> bxor(v1)
  end

  def swap_uint(<<v1::size(8), v2::size(8), v3::size(8), v4::size(8), v5::size(8), v6::size(8)>>) do
    v6 <<< 40
    |> bxor(v5 <<< 32)
    |> bxor(v4 <<< 24)
    |> bxor(v3 <<< 16)
    |> bxor(v2 <<< 8)
    |> bxor(v1)
  end

  def swap_uint(<<v1::size(8), v2::size(8), v3::size(8), v4::size(8), v5::size(8)>>) do
    v5 <<< 32
    |> bxor(v4 <<< 24)
    |> bxor(v3 <<< 16)
    |> bxor(v2 <<< 8)
    |> bxor(v1)
  end

  def swap_uint(<<v1::size(8), v2::size(8), v3::size(8), v4::size(8)>>) do
    v4 <<< 24
    |> bxor(v3 <<< 16)
    |> bxor(v2 <<< 8)
    |> bxor(v1)
  end

  def swap_uint(<<v1::size(8), v2::size(8), v3::size(8)>>) do
    v3 <<< 16
    |> bxor(v2 <<< 8)
    |> bxor(v1)
  end

  def swap_uint(<<v1::size(8), v2::size(8)>>) do
    v2 <<< 8 |> bxor(v1)
  end

  def swap_uint(<<v1::size(8)>>), do: 0 |> bxor(v1)

  def swap_uint(""), do: 0
end
