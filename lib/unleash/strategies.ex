defmodule Unleash.Strategies do
  alias Unleash.Strategy.{ActiveForUsersWithId, GradualRolloutRandom}

  def strategies do
    [
      {"ActiveForUsersWithId", ActiveForUsersWithId},
      {"GradualRolloutRandom", GradualRolloutRandom},
    ]
  end
end
