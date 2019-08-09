defmodule Unleash.Strategy.Default do
  @moduledoc """
  Does not require anything in `t:Unleash.context/0`

  Based on the
  [`default`](https://unleash.github.io/docs/activation_strategy#default)
  strategy.
  """

  use Unleash.Strategy, name: "Default"

  def enabled?(_params, _context), do: true
end
