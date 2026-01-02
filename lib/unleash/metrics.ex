defmodule Unleash.Metrics do
  @moduledoc false
  use GenServer

  alias Unleash.Config
  alias Unleash.Feature

  require Logger

  @type t :: %{stop: String.t(), start: String.t(), toggles: map()}

  def add_metric({feature, enabled?}, pid \\ Unleash.Metrics) do
    unless Config.disable_metrics() do
      GenServer.cast(pid, {:add_metric, feature, enabled?})
    end

    enabled?
  end

  def add_variant_metric({feature, variant}, pid \\ Unleash.Metrics) do
    unless Config.disable_metrics() do
      GenServer.cast(pid, {:add_variant_metric, feature, variant})
    end

    variant
  end

  # if Config.test?() do
  def get_metrics(pid \\ Unleash.Metrics) do
    GenServer.call(pid, :get_metrics)
  end

  def do_send_metrics(pid \\ Unleash.Metrics) do
    GenServer.call(pid, :send_metrics)
  end

  # end

  def init(_) do
    {:ok, init_state()}
  end

  def start_link(opts) do
    start_link(init_state(), opts)
  end

  def start_link(state, opts) do
    {:ok, pid} = GenServer.start_link(__MODULE__, state, opts)

    unless Config.test?() do
      initialize(pid)
    end

    {:ok, pid}
  end

  def handle_cast({:add_metric, feature, enabled?}, state) do
    state = handle_metric(state, feature, enabled?)
    {:noreply, state}
  end

  def handle_cast({:add_variant_metric, feature, variant}, state) do
    state = handle_variant_metric(state, feature, variant)

    {:noreply, state}
  end

  def handle_info(:send_metrics, state) do
    {:noreply, send_metrics(state)}
  end

  # if Config.test?() do
  def handle_call(:send_metrics, _from, state) do
    {:reply, :ok, send_metrics(state)}
  end

  def handle_call(:get_metrics, _from, state) do
    {:reply, {:ok, to_bucket(state)}, state}
  end

  # end

  defp send_metrics(state) do
    resp =
      state
      |> to_bucket()
      |> Config.client().metrics()

    schedule_metrics()

    case resp do
      {:ok, _} ->
        init_state()

      _ ->
        Logger.error("#{Config.appname()} #{__MODULE__}; HTTP response: #{Kernel.inspect(resp)}")
        state
    end
  end

  defp handle_metric(%{toggles: features} = state, %Feature{name: feature}, enabled?) do
    features
    |> update_metric(feature, enabled?)
    |> (&Map.put(state, :toggles, &1)).()
  end

  defp handle_metric(state, _feature, _enabled?) do
    state
  end

  defp update_metric(features, feature, true) do
    features
    |> Map.update(feature, %{yes: 1, no: 0}, &Map.update!(&1, :yes, fn x -> x + 1 end))
  end

  defp update_metric(features, feature, false) do
    features
    |> Map.update(feature, %{yes: 0, no: 1}, &Map.update!(&1, :no, fn x -> x + 1 end))
  end

  defp handle_variant_metric(
         %{toggles: features} = state,
         %Feature{name: feature, enabled: enabled?},
         %{name: variant}
       ) do
    features
    |> update_variant_metric(feature, enabled?, variant)
    |> (&Map.put(state, :toggles, &1)).()
  end

  defp update_variant_metric(features, feature, true, variant) do
    features
    |> Map.update(
      feature,
      %{yes: 1, no: 0, variants: %{variant => 1}},
      &(&1
        |> Map.update!(:yes, fn x -> x + 1 end)
        |> Map.update(:variants, %{variant => 1}, fn x ->
          Map.update(x, variant, 1, fn x -> x + 1 end)
        end))
    )
  end

  defp update_variant_metric(features, feature, false, variant) do
    features
    |> Map.update(
      feature,
      %{yes: 0, no: 1, variants: %{variant => 1}},
      &(&1
        |> Map.update!(:no, fn x -> x + 1 end)
        |> Map.update(:variants, %{variant => 1}, fn x ->
          Map.update(x, variant, 1, fn x -> x + 1 end)
        end))
    )
  end

  defp to_bucket(state), do: %{bucket: Map.put(state, :stop, current_date())}

  defp current_date do
    DateTime.utc_now()
    |> DateTime.to_iso8601()
  end

  defp init_state do
    %{start: current_date(), toggles: %{}}
  end

  defp initialize(pid) do
    Process.send(pid, :send_metrics, [])
  end

  defp schedule_metrics do
    Process.send_after(self(), :send_metrics, Config.metrics_period())
  end
end
