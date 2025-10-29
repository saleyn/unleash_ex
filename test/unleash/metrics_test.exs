defmodule Unleash.MetricsTest do
  use ExUnit.Case
  use ExUnitProperties

  import Mox

  alias Unleash.Config
  alias Unleash.Feature

  setup do
    stop_supervised(Unleash.Metrics)

    original_metrics_period = Config.metrics_period()
    Application.put_env(:unleash, :metrics_period, 60_000_000_000)
    {:ok, metrics} = start_supervised(Unleash.Metrics)

    on_exit(fn ->
      Application.put_env(:unleash, :metrics_period, original_metrics_period)
    end)

    %{metrics: metrics}
  end

  describe "add_metric/2" do
    property "should add the feature to the metrics bucket", %{metrics: metrics} do
      check all enabled <- positive_integer(),
                disabled <- positive_integer(),
                feature <- string(:alphanumeric, min_length: 1) do
        Unleash.ClientMock
        |> allow(self(), metrics)
        |> stub(:metrics, fn _ -> %SimpleHttp.Response{} end)

        Application.put_env(:unleash, :client, Unleash.ClientMock)

        for _ <- 1..enabled do
          Unleash.Metrics.add_metric({%Feature{name: feature}, true}, metrics)
        end

        for _ <- 1..disabled do
          Unleash.Metrics.add_metric({%Feature{name: feature}, false}, metrics)
        end

        {:ok, %{bucket: %{toggles: toggles}}} = Unleash.Metrics.get_metrics(metrics)
        assert Map.get(toggles, feature) == %{yes: enabled, no: disabled}

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

  describe "add_variant_metric/2" do
    property "should add the variant to the metrics bucket", %{metrics: metrics} do
      check all v <-
                  nonempty(uniq_list_of(string(:alphanumeric, min_length: 1))),
                n <- list_of(positive_integer(), length: length(v)),
                variants = Enum.zip(v, n) do
        test_pid = self()

        feature = "feature_1"
        Unleash.ClientMock
        |> allow(test_pid, metrics)
        |> stub(:metrics, fn _ -> %SimpleHttp.Response{} end)

        Application.put_env(:unleash, :client, Unleash.ClientMock)
        assert :ok == Process.send(metrics, :send_metrics, [])

        for {v, n} <- variants do
          for _ <- 1..n do
            Unleash.Metrics.add_variant_metric({%Feature{name: feature}, %{name: v}}, metrics)
          end
        end

        {:ok, %{bucket: %{toggles: toggles}}} = Unleash.Metrics.get_metrics(metrics)
        assert Map.get(Map.get(toggles, feature), :variants) == Map.new(variants)
        assert :ok == Process.send(metrics, :send_metrics, [])
        {:ok, %{bucket: %{toggles: toggles}}} = Unleash.Metrics.get_metrics(metrics)
        assert Map.get(toggles, feature) == nil
      end
    end
  end

  describe "send_metrics" do
    setup :verify_on_exit!

    test "sends the metrics bucket to the client", %{metrics: metrics} do
      Unleash.ClientMock
      |> allow(self(), metrics)
      |> expect(:metrics, fn %{bucket: %{toggles: toggles} = _bucket} ->
        assert toggles == %{}
        %Finch.Response{}
      end)

      Application.put_env(:unleash, :client, Unleash.ClientMock)

      assert :ok = GenServer.call(metrics, :send_metrics)
    end

    property "sends any toggles that have been sent", %{metrics: metrics} do
      check all enabled <- positive_integer(),
                disabled <- positive_integer(),
                feature <- string(:alphanumeric, min_length: 1) do
        Unleash.ClientMock
        |> allow(self(), metrics)
        |> expect(:metrics, fn _ ->
          %SimpleHttp.Response{}
        end)

        Application.put_env(:unleash, :client, Unleash.ClientMock)

        for _ <- 1..enabled do
          Unleash.Metrics.add_metric({%Feature{name: feature}, true}, metrics)
        end

        for _ <- 1..disabled do
          Unleash.Metrics.add_metric({%Feature{name: feature}, false}, metrics)
        end

        {:ok, %{bucket: %{toggles: toggles}}} = Unleash.Metrics.get_metrics(metrics)
        assert Map.get(toggles, feature) == %{yes: enabled, no: disabled}
        assert :ok == GenServer.call(metrics, :send_metrics)
        {:ok, %{bucket: %{toggles: toggles}}} = Unleash.Metrics.get_metrics(metrics)
        assert Map.get(toggles, :test) == nil
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
