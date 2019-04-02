defmodule Unleash.Strategies do
  alias Unleash.Strategy.{ActiveForUsersWithId, GradualRolloutRandom, RemoteAddress}

  def strategies do
    [
      {"ActiveForUsersWithId", ActiveForUsersWithId},
      {"GradualRolloutRandom", GradualRolloutRandom},
      {"RemoteAddress", RemoteAddress}
    ]
  end
end
