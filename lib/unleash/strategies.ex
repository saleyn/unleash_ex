defmodule Unleash.Strategies do
  alias Unleash.Strategy.ActiveForUsersWithId

  def strategies do
    [
      {"ActiveForUsersWithId", ActiveForUsersWithId},
    ]
  end
end
