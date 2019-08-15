defmodule Unleash.ClientSpecificationTest do
  @moduledoc false
  use ExUnit.Case

  @specification_path "priv/client-specification/specifications"

  @specs "#{@specification_path}/index.json"
         |> File.read!()
         |> Jason.decode!()

  Enum.each(@specs, fn spec ->
    test_spec =
      "#{@specification_path}/#{spec}"
      |> File.read!()
      |> Jason.decode!()

    %{"name" => name, "state" => state} = test_spec

    tests = Enum.concat(Map.get(test_spec, "variantTests", []), Map.get(test_spec, "tests", []))

    @state state

    describe name do
      setup do
        stop_supervised(Unleash.Repo)
        state = Unleash.Features.from_map!(@state)
        {:ok, _pid} = start_supervised({Unleash.Repo, state})

        :ok
      end

      Enum.each(tests, fn %{
                            "context" => ctx,
                            "description" => t,
                            "expectedResult" => expected,
                            "toggleName" => feature
                          } ->
        @context ctx
        @feature feature
        @expected expected

        test t do
          context = context_from_file(@context)

          assert @expected == Unleash.enabled?(@feature, context)
        end
      end)
    end
  end)

  defp context_from_file(ctx) do
    %{
      user_id: ctx["userId"],
      session_id: ctx["sessionId"],
      remote_address: ctx["remoteAddress"]
    }
  end
end
