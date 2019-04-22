defmodule Unleash.Strategy.ActiveForUsersWithId do
  use Unleash.Strategy
  alias Unleash.Strategy.Utils

  @impl Strategy
  def enabled?(%{"userIdList" => list}, %{"userId" => user_id})
      when is_binary(list) and is_binary(user_id) do
    {Utils.in_list?(list, user_id), %{user_id_list: list, user_id: user_id}}
  end

  @impl Strategy
  def enabled?(%{"userIdList" => list}, %{"userId" => user_id})
      when is_binary(list) and is_integer(user_id) do
    {Utils.in_list?(list, user_id, &Utils.parse_int/1), %{user_id_list: list, user_id: user_id}}
  end

  @impl Strategy
  def enabled?(_params, _context), do: false
end
