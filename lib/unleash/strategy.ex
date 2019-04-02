defmodule Unleash.Strategy do
  defmacro __using__(opts) do
    name = opts[:name]

    quote line: true do
      require Logger

      alias unquote(__MODULE__)

      @behaviour unquote(__MODULE__)

      @name unquote(name)

      def check_enabled(params, context) do
        case enabled?(params, context) do
          {result, opts} -> log_result(result, opts)
          result -> result
        end
      end

      defp log_result(result, opts) when is_map(opts) do
        Logger.debug(fn ->
          opts
          |> Stream.map(fn {k, v} -> "#{k}: #{v}" end)
          |> Enum.join(", ")
          |> (&"#{@name} computed #{result} from #{&1}").()
        end)

        result
      end
    end
  end

  defstruct name: "default", params: %{}

  @callback enabled?(params :: Map.t(), context :: Map.t()) :: {boolean, Map.t()}

  def enabled?(%__MODULE__{} = _strat, _context) do
    true
  end
end
