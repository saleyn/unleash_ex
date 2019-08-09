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

  require Logger

  alias Unleash.Config

  defmacro __using__(opts) do
    name = opts[:name]

    quote line: true do
      require Logger

      alias unquote(__MODULE__)

      @behaviour unquote(__MODULE__)

      @name unquote(name)

      @doc false
      def check_enabled(params, context) do
        params
        |> enabled?(context)
        |> log_result()
      end

      defp log_result(result) when is_boolean(result) do
        Logger.debug(fn ->
          "#{@name} computed #{result}"
        end)

        result
      end

      defp log_result({result, opts}) when is_map(opts) do
        Logger.debug(fn ->
          opts
          |> Stream.map(fn {k, v} -> "#{k}: #{v}" end)
          |> Enum.join(", ")
          |> (&"#{@name} computed #{result} from #{&1}").()
        end)

        result
      end

      defp log_result({result, _opts}), do: result
    end
  end

  @doc """
  You can implmenet this callback a couple of ways, returning a bare `boolean()`
  or a `{boolean, Map.t()}`. The latter is preferred, as it generates a
  `:debug` level log entry detailing the name of the strategy, the result, and
  the contents of `Map.t()`, in an effort to help understand why the result was
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
  @callback enabled?(parameters :: Map.t(), context :: Unleash.context()) ::
              boolean() | {boolean(), Map.t()}

  @doc false
  def enabled?(%{"name" => name, "parameters" => params}, context) do
    {_name, module} =
      Config.strategies()
      |> Enum.find(fn {n, _mod} -> n == name end)

    module.check_enabled(params, context)
  end

  def enabled?(_strat, _context), do: false
end
