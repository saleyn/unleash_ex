defmodule Unleash.Strategies do
  alias Unleash.Strategy.{
    ActiveForUsersWithId,
    ApplicationHostname,
    GradualRolloutRandom,
    RemoteAddress
  }

  def strategies do
    [
      {"ActiveForUsersWithId", ActiveForUsersWithId},
      {"ApplicationHostname", ApplicationHostname},
      {"GradualRolloutRandom", GradualRolloutRandom},
      {"GradualRolloutSessionId", GradualRolloutSessionId},
      {"RemoteAddress", RemoteAddress}
    ]
  end
end
