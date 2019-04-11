defmodule Unleash.Metrics do
  use GenServer

  alias Unleash.Client
  alias Unleash.Config

  @type t :: %{stop: String.t(), start: String.t(), toggles: Map.t()}

  def init(_) do
    {:ok, init_state()}
  end

  def start_link(state) do
    GenServer.start_link(__MODULE__, state)
    schedule_metrics()
  end

  def add_metric(pid, feature, enabled?) do
    GenServer.call(pid, {:add_metric, feature, enabled?})
  end

  def handle_call({:add_metric, feature, enabled?}, state) do
    state = handle_metric(state, feature, enabled?)
    {:noreply, state}
  end

  def handle_info(:send_metrics, state) do
    state
    |> to_bucket()
    |> Client.metrics()

    schedule_metrics()

    {:noreply, init_state()}
  end

  defp handle_metric(%{toggles: features} = state, feature, enabled?) do
    features
    |> update_metric(feature, enabled?)
    |> (&%{state | toggles: &1}).()
  end

  defp update_metric(features, feature, true) do
    features
    |> Map.update(feature, %{yes: 1, no: 0}, &Map.update!(&1, :yes, fn x -> x + 1 end))
  end

  defp update_metric(features, feature, false) do
    features
    |> Map.update(feature, %{yes: 0, no: 1}, &Map.update!(&1, :no, fn x -> x + 1 end))
  end

  defp to_bucket(state), do: %{bucket: %{state | stop: current_date()}}

  defp current_date() do
    DateTime.utc_now()
    |> DateTime.to_iso8601()
  end

  defp init_state() do
    %{start: current_date(), toggles: %{}}
  end

  defp schedule_metrics() do
    Process.send_after(self(), :send_metrics, Config.metrics_period())
  end
end
