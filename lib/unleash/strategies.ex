defmodule Unleash.Strategies do
  alias Unleash.Strategy.{ActiveForUsersWithId, GradualRolloutRandom, RemoteAddress}

  def strategies do
    [
      {"ActiveForUsersWithId", ActiveForUsersWithId},
      {"GradualRolloutRandom", GradualRolloutRandom},
      {"GradualRolloutSessionId", GradualRolloutSessionId},
      {"RemoteAddress", RemoteAddress}
    ]
  end
end
