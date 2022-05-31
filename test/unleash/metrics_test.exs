defmodule Unleash.MetricsTest do
  use ExUnit.Case
  use ExUnitProperties

  import Mox

  alias Unleash.Feature

  setup do
    stop_supervised(Unleash.Metrics)

    {:ok, metrics} = start_supervised(Unleash.Metrics)

    %{metrics: metrics}
  end

  @tag capture_log: true
  describe "add_metric/2" do
    property "should add the feature to the metrics bucket", %{metrics: metrics} do
      check all enabled <- positive_integer(),
                disabled <- positive_integer(),
                feature <- string(:alphanumeric, min_length: 1) do
        Unleash.ClientMock
        |> allow(self(), metrics)
        |> stub(:metrics, fn _ -> %Mojito.Response{} end)

        Application.put_env(:unleash, Unleash, client: Unleash.ClientMock)

        for _ <- 1..enabled do
          Unleash.Metrics.add_metric({%Feature{name: feature}, true}, metrics)
        end

        for _ <- 1..disabled do
          Unleash.Metrics.add_metric({%Feature{name: feature}, false}, metrics)
        end

        %{toggles: toggles} = :sys.get_state(metrics)
        f = Map.get(toggles, feature)
        assert ^f = %{yes: enabled, no: disabled}

        Process.send(metrics, :send_metrics, [])
      end
    end

    test "should not crash metric for unrecorded toggle", %{metrics: metrics} do
      Unleash.Metrics.add_metric({:unrecorded_feature_toggle, false}, metrics)

      # Force metrics to process message
      :sys.get_state(metrics)

      assert Process.alive?(metrics)
    end
  end

  @tag capture_log: true
  describe "add_variant_metric/2" do
    property "should add the variant to the metrics bucket", %{metrics: metrics} do
      check all v <-
                  nonempty(uniq_list_of(string(:alphanumeric, min_length: 1))),
                n <- list_of(positive_integer(), length: length(v)),
                variants = Enum.zip(v, n) do
        Unleash.ClientMock
        |> allow(self(), metrics)
        |> stub(:metrics, fn _ -> %Mojito.Response{} end)

        Application.put_env(:unleash, Unleash, client: Unleash.ClientMock)

        for {v, n} <- variants do
          for _ <- 1..n do
            Unleash.Metrics.add_variant_metric({:test, %{name: v}}, metrics)
          end
        end

        %{toggles: toggles} = :sys.get_state(metrics)
        Process.send(metrics, :send_metrics, [])
        f = Map.get(toggles, :test)

        assert ^f = Map.new(variants)
      end
    end
  end

  describe "send_metrics" do
    setup :verify_on_exit!

    @tag capture_log: true
    test "sends the metrics bucket to the client", %{metrics: metrics} do
      Unleash.ClientMock
      |> allow(self(), metrics)
      |> expect(:metrics, fn %{bucket: %{toggles: toggles} = _bucket} ->
        assert ^toggles = %{}
        %Mojito.Response{}
      end)

      Application.put_env(:unleash, Unleash, client: Unleash.ClientMock)

      assert :ok = GenServer.call(metrics, :send_metrics)
    end

    @tag capture_log: true
    property "sends any toggles that have been sent", %{metrics: metrics} do
      check all enabled <- positive_integer(),
                disabled <- positive_integer(),
                feature <- string(:alphanumeric, min_length: 1) do
        Unleash.ClientMock
        |> allow(self(), metrics)
        |> expect(:metrics, fn %{bucket: %{toggles: toggles} = _bucket} ->
          f = Map.get(toggles, feature)
          assert ^f = %{yes: enabled, no: disabled}
          %Mojito.Response{}
        end)

        Application.put_env(:unleash, Unleash, client: Unleash.ClientMock)

        for _ <- 1..enabled do
          Unleash.Metrics.add_metric({%Feature{name: feature}, true}, metrics)
        end

        for _ <- 1..disabled do
          Unleash.Metrics.add_metric({%Feature{name: feature}, false}, metrics)
        end

        assert :ok = GenServer.call(metrics, :send_metrics)
      end
    end
  end

  describe "start metrics" do
    test "should start named process under supervisor" do
      {:ok, _} =
        Supervisor.start_link(
          [
            {Unleash.Metrics, name: :metric_named_process}
          ],
          strategy: :one_for_one
        )

      assert Process.whereis(:metric_named_process) != nil
    end
  end
end
