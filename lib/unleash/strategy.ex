defmodule Unleash.Strategy do
  @moduledoc """
  Used to extend the client and create custom strategies. To do so, `use` this
  module within your custom strategy and implmenent `c:enabled?/2`. Provide a
  name that is human-readable, as it is logged.

  ```elixir
  defmodule MyApp.CustomStrategy
    use Unleash.Strategy, name: "CustomStrategy"

    def enabled?(_params, _context), do: true
  end
  ```
  """

  alias Unleash.Config
  alias Unleash.Strategy.Constraint
  alias Unleash.Variant

  def update_map(map) when is_map(map) do
    {_, new_map1} =
      Map.get_and_update(map, "variants", fn variants ->
        {variants, Enum.map(variants || [], &Variant.from_map/1)}
      end)

    {_, new_map2} =
      Map.get_and_update(new_map1, "parameters", fn parameters ->
        {parameters, parameters || %{}}
      end)

    {_, new_map3} =
      Map.get_and_update(new_map2, "constraints", fn constraints ->
        {constraints, Enum.map(constraints || [], &Constraint.precompute_context_atom/1)}
      end)

    new_map3
  end

  defmacro __using__(opts) do
    name = opts[:name]

    quote line: true do
      alias unquote(__MODULE__)

      @behaviour unquote(__MODULE__)

      @name unquote(name)

      @doc false
      def check_enabled(params \\ %{}, context) do
        Unleash.Strategy.normalize_enabled(enabled?(params, context))
      end
    end
  end

  @doc false
  @spec normalize_enabled(boolean() | {boolean(), map()}) :: boolean()
  def normalize_enabled({result, _used_opts}), do: result
  def normalize_enabled(result), do: result

  @doc """
  You can implmenet this callback a couple of ways, returning a bare `boolean()`
  or a `{boolean, map()}`. The latter is preferred, as it generates a
  `:debug` level log entry detailing the name of the strategy, the result, and
  the contents of `map()`, in an effort to help understand why the result was
  what it was.

  ## Arguments

  * `parameters` - A map of paramters returned from the Unleash server. This
    can be whatever you like, such as a configured list of `userIds`.
  * `context` - The context passed into `Unleash.enabled?/3`.


  ## Examples

  ```elixir
  @behaviour Unleash.Strategy

  def enabled?(params, context), do: {false, params}

  def enabled(params, %{}), do: false
  ```

  """
  @callback enabled?(parameters :: map(), context :: Unleash.context()) ::
              boolean() | {boolean(), map()}

  @doc false
  def enabled?(%{"name" => name} = strategy, context) do
    module = Map.fetch!(Config.strategies_map(), name)

    check_constraints(strategy, context) and module.check_enabled(strategy["parameters"], context)
  end

  def enabled?(_strat, _context), do: false

  defp check_constraints(%{"constraints" => constraints}, context),
    do: Constraint.verify_all(constraints, context)

  defp check_constraints(_strategy, _context), do: true
end
