defmodule Unleash.MetricsFastTest do
  use ExUnit.Case
  use ExUnitProperties

  import Mox

  alias Unleash.Config
  alias Unleash.Feature
  alias Unleash.MetricsFast

  setup do
    stop_supervised(Unleash.MetricsFast)

    original_fast_metrics = Config.fast_metrics()
    original_disable_metrics = Config.disable_metrics()
    Application.put_env(:unleash, :fast_metrics, true)

    {:ok, _pid} = start_supervised({Unleash.MetricsFast, []})

    on_exit(fn ->
      Application.put_env(:unleash, :fast_metrics, original_fast_metrics)
      Application.put_env(:unleash, :disable_metrics, original_disable_metrics)
    end)

    :ok
  end

  describe "add_metric/1" do
    property "lazily creates a counter and counts an unregistered feature", %{} do
      check all enabled <- positive_integer(),
                disabled <- positive_integer(),
                feature <- string(:alphanumeric, min_length: 1) do
        # Drain any leftovers from a previous property iteration.
        metrics_pid = Process.whereis(Unleash.MetricsFast)

        Unleash.ClientMock
        |> allow(self(), metrics_pid)
        |> stub(:metrics, fn _ -> {:ok, %SimpleHttp.Response{}} end)

        Application.put_env(:unleash, :client, Unleash.ClientMock)
        :ok = MetricsFast.do_send_metrics()

        for _ <- 1..enabled do
          MetricsFast.add_metric({%Feature{name: feature}, true})
        end

        for _ <- 1..disabled do
          MetricsFast.add_metric({%Feature{name: feature}, false})
        end

        {:ok, %{bucket: %{toggles: toggles}}} = MetricsFast.get_metrics()

        assert Map.get(toggles, feature) == %{yes: enabled, no: disabled}
      end
    end

    test "should not crash for a non-Feature toggle" do
      assert MetricsFast.add_metric({:unrecorded_feature_toggle, false}) == false
      assert Process.alive?(Process.whereis(Unleash.MetricsFast))
    end
  end

  describe "register_features/1" do
    test "pre-creates a counter so get_metrics/0 reports it before any check happens" do
      feature = "pre_registered_feature"

      :ok = MetricsFast.register_features([%Feature{name: feature}])

      {:ok, %{bucket: %{toggles: toggles}}} = MetricsFast.get_metrics()

      assert Map.get(toggles, feature) == %{yes: 0, no: 0}
    end
  end

  describe "add_variant_metric/1" do
    property "aggregates variant counts under the feature's toggle entry" do
      check all v <-
                  nonempty(uniq_list_of(string(:alphanumeric, min_length: 1))),
                n <- list_of(positive_integer(), length: length(v)),
                variants = Enum.zip(v, n) do
        feature = "variant_feature_#{System.unique_integer([:positive])}"

        for {variant_name, count} <- variants do
          for _ <- 1..count do
            MetricsFast.add_variant_metric({%Feature{name: feature}, %{name: variant_name}})
          end
        end

        {:ok, %{bucket: %{toggles: toggles}}} = MetricsFast.get_metrics()

        assert Map.get(Map.get(toggles, feature), :variants) == Map.new(variants)
      end
    end
  end

  describe "get_metrics/0 bucket shape" do
    test "matches the {:ok, %{bucket: %{start:, stop:, toggles:}}} shape" do
      feature = "shape_feature"
      MetricsFast.add_metric({%Feature{name: feature}, true})

      assert {:ok, %{bucket: %{start: start, stop: stop, toggles: toggles}}} =
               MetricsFast.get_metrics()

      assert is_binary(start)
      assert is_binary(stop)
      assert Map.get(toggles, feature) == %{yes: 1, no: 0}
    end
  end

  describe "disable_metrics" do
    test "add_metric/1 is a no-op when disable_metrics was true at startup" do
      stop_supervised(Unleash.MetricsFast)
      Application.put_env(:unleash, :disable_metrics, true)
      {:ok, _pid} = start_supervised({Unleash.MetricsFast, []})

      feature = "disabled_metrics_feature"
      assert MetricsFast.add_metric({%Feature{name: feature}, true}) == true

      {:ok, %{bucket: %{toggles: toggles}}} = MetricsFast.get_metrics()
      assert Map.get(toggles, feature) == nil
    end
  end

  describe "send_metrics / collect+reset race" do
    setup :verify_on_exit!

    test "an add_metric landing between collection and reset is not lost" do
      feature = "race_feature"
      metrics_pid = Process.whereis(Unleash.MetricsFast)

      MetricsFast.add_metric({%Feature{name: feature}, true})

      Unleash.ClientMock
      |> allow(self(), metrics_pid)
      |> stub(:metrics, fn bucket ->
        # Simulate a concurrent check arriving while the previous cycle's
        # counters are being read/reset - it must be preserved for the next
        # collection, not zeroed away.
        assert %{bucket: %{toggles: %{^feature => %{yes: 1, no: 0}}}} = bucket
        MetricsFast.add_metric({%Feature{name: feature}, true})
        {:ok, %SimpleHttp.Response{}}
      end)

      Application.put_env(:unleash, :client, Unleash.ClientMock)

      assert :ok == MetricsFast.do_send_metrics()

      {:ok, %{bucket: %{toggles: toggles}}} = MetricsFast.get_metrics()
      assert Map.get(toggles, feature) == %{yes: 1, no: 0}
    end

    test "sends an empty bucket then reflects newly-added metrics on the next send" do
      metrics_pid = Process.whereis(Unleash.MetricsFast)

      Unleash.ClientMock
      |> allow(self(), metrics_pid)
      |> expect(:metrics, fn %{bucket: %{toggles: toggles}} ->
        assert toggles == %{}
        {:ok, %SimpleHttp.Response{}}
      end)

      Application.put_env(:unleash, :client, Unleash.ClientMock)

      assert :ok == MetricsFast.do_send_metrics()
    end
  end

  describe "prune_stale_features/1" do
    test "removes counters/variant-counters for features no longer present" do
      kept = "kept_feature"
      removed = "removed_feature"

      MetricsFast.add_metric({%Feature{name: kept}, true})

      MetricsFast.add_variant_metric(
        {%Feature{name: kept, enabled: true}, %{name: "kept_variant"}}
      )

      MetricsFast.add_metric({%Feature{name: removed}, true})

      MetricsFast.add_variant_metric(
        {%Feature{name: removed, enabled: true}, %{name: "removed_variant"}}
      )

      :ok = MetricsFast.prune_stale_features([%Feature{name: kept}])

      {:ok, %{bucket: %{toggles: toggles}}} = MetricsFast.get_metrics()

      assert Map.get(toggles, removed) == nil
      assert Map.get(toggles, kept) == %{yes: 2, no: 0, variants: %{"kept_variant" => 1}}
    end
  end

  describe "start metrics" do
    test "should start named process under supervisor" do
      # MetricsFast.start_link/1 always registers itself as __MODULE__, so the
      # instance started in setup/1 must be stopped first to avoid an
      # :already_started clash.
      stop_supervised(Unleash.MetricsFast)

      {:ok, _} =
        Supervisor.start_link(
          [
            {Unleash.MetricsFast, []}
          ],
          strategy: :one_for_one
        )

      assert Process.whereis(Unleash.MetricsFast) != nil
    end
  end
end
