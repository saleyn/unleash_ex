defmodule Unleash.Strategies do
  alias Unleash.Strategy.{
    ActiveForUsersWithId,
    ApplicationHostname,
    Default,
    GradualRolloutRandom,
    GradualRolloutSessionId,
    GradualRolloutUserId,
    RemoteAddress
  }

  def strategies do
    [
      {"userWithId", ActiveForUsersWithId},
      {"applicationHostname", ApplicationHostname},
      {"default", Default},
      {"gradualRolloutRandom", GradualRolloutRandom},
      {"gradualRolloutSessionId", GradualRolloutSessionId},
      {"gradualRolloutUserId", GradualRolloutUserId},
      {"remoteAddress", RemoteAddress}
    ]
  end
end
