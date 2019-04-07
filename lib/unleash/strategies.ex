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
      {"ActiveForUsersWithId", ActiveForUsersWithId},
      {"ApplicationHostname", ApplicationHostname},
      {"Default", Default},
      {"GradualRolloutRandom", GradualRolloutRandom},
      {"GradualRolloutSessionId", GradualRolloutSessionId},
      {"GradualRolloutUserId", GradualRolloutUserId},
      {"RemoteAddress", RemoteAddress}
    ]
  end
end
