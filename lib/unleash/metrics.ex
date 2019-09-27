defmodule Unleash.Metrics do
  @moduledoc false
  use GenServer
  require Logger

  alias Unleash.Config
  alias Unleash.Feature

  @type t :: %{stop: String.t(), start: String.t(), toggles: map()}

  def add_metric({feature, enabled?}, pid \\ Unleash.Metrics) do
    unless Config.disable_metrics() do
      GenServer.cast(pid, {:add_metric, feature, enabled?})
    end

    enabled?
  end

  def add_variant_metric({name, variant}, pid \\ Unleash.Metrics) do
    unless Config.disable_metrics() do
      GenServer.cast(pid, {:add_variant_metric, name, variant})
    end

    variant
  end

  def init(_) do
    {:ok, init_state()}
  end

  def start_link(state, opts \\ []) do
    {:ok, pid} = GenServer.start_link(__MODULE__, state, opts)

    unless Mix.env() == :test do
      initialize(pid)
    end

    {:ok, pid}
  end

  def handle_cast({:add_metric, feature, enabled?}, state) do
    state = handle_metric(state, feature, enabled?)
    {:noreply, state}
  end

  def handle_cast({:add_variant_metric, variant, name}, state) do
    state = handle_variant_metric(state, variant, name)

    {:noreply, state}
  end

  def handle_info(:send_metrics, state) do
    {:noreply, send_metrics(state)}
  end

  if Mix.env() == :test do
    def handle_call(:send_metrics, _from, state) do
      {:reply, :ok, send_metrics(state)}
    end
  end

  defp send_metrics(state) do
    state
    |> to_bucket()
    |> log_metrics()
    |> Config.client().metrics()

    schedule_metrics()

    init_state()
  end

  defp log_metrics(state) do
    Logger.info(fn ->
      "Sending metrics: #{inspect(state, pretty: true)}"
    end)

    state
  end

  defp handle_metric(%{toggles: features} = state, %Feature{name: feature}, enabled?) do
    features
    |> update_metric(feature, enabled?)
    |> (&Map.put(state, :toggles, &1)).()
  end

  defp update_metric(features, feature, true) do
    features
    |> Map.update(feature, %{yes: 1, no: 0}, &Map.update!(&1, :yes, fn x -> x + 1 end))
  end

  defp update_metric(features, feature, false) do
    features
    |> Map.update(feature, %{yes: 0, no: 1}, &Map.update!(&1, :no, fn x -> x + 1 end))
  end

  defp handle_variant_metric(%{toggles: features} = state, variant, %{name: name}) do
    features
    |> Map.update(variant, Map.new([{name, 1}]), &Map.update(&1, name, 1, fn x -> x + 1 end))
    |> (&Map.put(state, :toggles, &1)).()
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
