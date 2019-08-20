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

    tests = Map.get(test_spec, "tests", [])

    variant_tests = Map.get(test_spec, "variantTests", [])

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
          context = entity_from_file(@context)

          assert @expected == Unleash.enabled?(@feature, context)
        end
      end)

      Enum.each(variant_tests, fn %{
                                    "context" => ctx,
                                    "description" => t,
                                    "expectedResult" => expected,
                                    "toggleName" => feature
                                  } ->
        @context ctx
        @feature feature
        @expected expected

        test t do
          context = entity_from_file(@context)

          assert entity_from_file(@expected) == Unleash.get_variant(@feature, context)
        end
      end)
    end
  end)

  defp entity_from_file(e) do
    e
    |> Enum.map(fn {k, v} -> {String.to_atom(Recase.to_snake(k)), v} end)
    |> Enum.into(%{})
  end
end
