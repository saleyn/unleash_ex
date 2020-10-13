defmodule Unleash.Strategies do
  @moduledoc """
  Used to get all available strategies in the client. You can add your
  strategies to the client by extending this module:

  ```elixir
  defmodule MyApp.Strategies do
    @behaviour Unleash.Strategies

    def strategies, do: Unleash.Strategies.strategies() ++ []
  end
  ```

  and then setting it in your configuration:

  ```elixir
  config :unleash, Unleash, strategies: MyApp.Strategies
  ```
  """

  alias Unleash.Strategy.{
    ActiveForUsersWithId,
    ApplicationHostname,
    Default,
    FlexibleRollout,
    GradualRolloutRandom,
    GradualRolloutSessionId,
    GradualRolloutUserId,
    RemoteAddress
  }

  @doc """
  Should return a list of all the avilable strategies in the format
  `{"name", Module}`. The name must match the name of the strategy in the
  Unleash server, and the module must implement the `Unleash.Strategy` behaviour.
  """
  @callback strategies :: list({String.t(), module})

  @doc """
  Returns all the strategies that are supported by this client. They can be
  viewed under `Strategy`.

  For completeness, the list is:

  * `userWithId`: `Unleash.Strategy.ActiveForUsersWithId`
  * `applicationHostname`: `Unleash.Strategy.ApplicationHostname`
  * `default`: `Unleash.Strategy.Default`
  * `gradualRolloutRandom`: `Unleash.Strategy.GradualRolloutRandom`
  * `gradualRolloutSessionId`: `Unleash.Strategy.GradualRolloutSessionId`
  * `gradualRolloutUserId`: `Unleash.Strategy.GradualRolloutUserId`
  * `remoteAddress`: `Unleash.Strategy.RemoteAddress`
  """
  def strategies do
    [
      {"userWithId", ActiveForUsersWithId},
      {"applicationHostname", ApplicationHostname},
      {"default", Default},
      {"flexibleRollout", FlexibleRollout},
      {"gradualRolloutRandom", GradualRolloutRandom},
      {"gradualRolloutSessionId", GradualRolloutSessionId},
      {"gradualRolloutUserId", GradualRolloutUserId},
      {"remoteAddress", RemoteAddress}
    ]
  end
end
