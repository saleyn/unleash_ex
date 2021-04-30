defmodule Unleash.VariantTest do
  use ExUnit.Case

  setup :start_repo

  test "return a disabled variant if the flag is disabled" do
    assert %{
             enabled: false,
             name: "disabled",
             payload: %{}
           } == Unleash.get_variant(:disabled_variant)
  end

  defp start_repo(_) do
    stop_supervised(Unleash.Repo)

    state = Unleash.Features.from_map!(state())

    {:ok, _pid} = start_supervised({Unleash.Repo, state})
    :ok
  end

  defp state,
    do: %{
      "version" => 1,
      "features" => [
        %{
          "name" => "disabled_variant",
          "description" => "variant with enabled set to false",
          "enabled" => false,
          "strategies" => [
            %{
              "name" => "default",
              "parameters" => %{}
            }
          ],
          "variants" => [
            %{
              "name" => "variant1",
              "weight" => 100,
              "payload" => %{"type" => "string", "value" => "val1"}
            }
          ]
        }
      ]
    }
end
