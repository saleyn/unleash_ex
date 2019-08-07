defmodule Unleash.Strategy do
  require Logger

  alias Unleash.Config

  defmacro __using__(opts) do
    name = opts[:name]

    quote line: true do
      require Logger

      alias unquote(__MODULE__)

      @behaviour unquote(__MODULE__)

      @name unquote(name)

      def check_enabled(params, context) do
        params
        |> enabled?(context)
        |> log_result()
      end

      defp log_result(result) when is_boolean(result), do: result

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

  @callback enabled?(Map.t(), Map.t()) :: boolean() | {boolean(), Map.t()}

  def enabled?(%{"name" => name, "parameters" => params}, context) do
    {_name, module} =
      Config.strategies()
      |> Enum.find(fn {n, _mod} -> n == name end)

    module.check_enabled(params, context)
  end

  def enabled?(_strat, _context), do: false
end
