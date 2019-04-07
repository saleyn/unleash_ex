defmodule Unleash.Strategies do
  alias Unleash.Strategy.{
    ActiveForUsersWithId,
    ApplicationHostname,
    GradualRolloutRandom,
    GradualRolloutSessionId,
    GradualRolloutUserId,
    RemoteAddress
  }

  def strategies do
    [
      {"ActiveForUsersWithId", ActiveForUsersWithId},
      {"ApplicationHostname", ApplicationHostname},
      {"GradualRolloutRandom", GradualRolloutRandom},
      {"GradualRolloutSessionId", GradualRolloutSessionId},
      {"GradualRolloutUserId", GradualRolloutUserId},
      {"RemoteAddress", RemoteAddress}
    ]
  end
end
