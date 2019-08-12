defmodule Unleash.Metrics do
  @moduledoc false
  use GenServer
  require Logger

  alias Unleash.Client
  alias Unleash.Config
  alias Unleash.Feature

  @type t :: %{stop: String.t(), start: String.t(), toggles: Map.t()}

  def init(_) do
    {:ok, init_state()}
  end

  def start_link(state) do
    {:ok, pid} = GenServer.start_link(__MODULE__, state, name: Unleash.Metrics)
    initialize()
    {:ok, pid}
  end

  def add_metric({feature, enabled?}) do
    unless Config.disable_metrics() do
      GenServer.cast(Unleash.Metrics, {:add_metric, feature, enabled?})
    end

    enabled?
  end

  def handle_cast({:add_metric, feature, enabled?}, state) do
    state = handle_metric(state, feature, enabled?)
    {:noreply, state}
  end

  def handle_info(:send_metrics, state) do
    state
    |> to_bucket()
    |> log_metrics()
    |> Client.metrics()

    schedule_metrics()

    {:noreply, init_state()}
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

  defp to_bucket(state), do: %{bucket: Map.put(state, :stop, current_date())}

  defp current_date do
    DateTime.utc_now()
    |> DateTime.to_iso8601()
  end

  defp init_state do
    %{start: current_date(), toggles: %{}}
  end

  defp initialize do
    Process.send(Unleash.Metrics, :send_metrics, [])
  end

  defp schedule_metrics do
    Process.send_after(self(), :send_metrics, Config.metrics_period())
  end
end
