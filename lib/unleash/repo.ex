defmodule Unleash.Repo do
  @moduledoc false
  use GenServer
  require Logger

  alias Unleash.Client
  alias Unleash.Config
  alias Unleash.Features

  def init(_) do
    {:ok, %Features{}}
  end

  def start_link(state) do
    {:ok, pid} = GenServer.start_link(__MODULE__, state, name: Unleash.Repo)

    initialize()

    {:ok, pid}
  end

  def get_feature(name) do
    GenServer.call(Unleash.Repo, {:get_feature, name})
  end

  def handle_call({:get_feature, name}, _from, state) do
    feature = Features.get_feature(state, name)

    {:reply, feature, state}
  end

  def handle_info({:initialize, etag}, state) do
    {etag, response} = Client.features(etag)

    schedule_features(etag)

    features =
      case response do
        {:error, _} -> read_state(state)
        f -> f
      end

    if features === state do
      {:noreply, features}
    else
      write_state(features)
    end
  end

  defp read_state(%Features{features: []} = state) do
    if File.exists?(Config.backup_file()) do
      Config.backup_file()
      |> File.read!()
      |> Jason.decode!()
      |> Features.from_map!()
    else
      state
    end
  end

  defp read_state(state), do: state

  defp write_state(state) do
    if not File.dir?(Config.backup_dir()) do
      Config.backup_dir()
      |> File.mkdir_p!()
    end

    content = Jason.encode_to_iodata!(state)

    Config.backup_file()
    |> File.write!(content)

    Logger.debug(fn ->
      ["Wrote ", content, " to file ", Config.backup_file()]
    end)

    {:noreply, state}
  end

  defp initialize do
    Process.send(Unleash.Repo, :initialize, [])
  end

  defp schedule_features(etag) do
    Process.send_after(self(), {:initialize, etag}, Config.features_period())
  end
end
