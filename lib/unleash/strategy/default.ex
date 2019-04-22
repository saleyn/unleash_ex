defmodule Unleash.Strategy.Default do
  use Unleash.Strategy, name: "Default"

  def enabled?(_params, _context), do: true
end
