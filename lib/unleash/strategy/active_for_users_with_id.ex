defmodule Unleash.Strategy.ActiveForUsersWithId do
  @moduledoc """
  Requires `:user_id` in `t:Unleash.context/0`

  Based on the
  [`userWithId`](https://unleash.github.io/docs/activation_strategy#userwithid)
  strategy.
  """

  use Unleash.Strategy, name: "ActiveForUsersWithId"
  alias Unleash.Strategy.Utils

  @impl Strategy
  @doc false
  def enabled?(%{"userIds" => list}, %{user_id: user_id})
      when is_binary(list) and is_binary(user_id) do
    {Utils.in_list?(list, user_id), %{user_id_list: list, user_id: user_id}}
  end

  @impl Strategy
  @doc false
  def enabled?(%{"userIds" => list}, %{user_id: user_id})
      when is_binary(list) and is_integer(user_id) do
    {Utils.in_list?(list, user_id, &Utils.parse_int/1), %{user_id_list: list, user_id: user_id}}
  end

  @impl Strategy
  @doc false
  def enabled?(_params, _context), do: false
end
