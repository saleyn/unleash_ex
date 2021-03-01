defmodule Unleash.Repo do
  @moduledoc false
  use GenServer
  require Logger

  alias Unleash.Config
  alias Unleash.Features

  def init(%Features{} = features) do
    {:ok, features}
  end

  def init(_) do
    {:ok, %Features{}}
  end

  def start_link(state) do
    {:ok, pid} = GenServer.start_link(__MODULE__, state, name: Unleash.Repo)

    unless Config.test? do
      initialize()
    end

    {:ok, pid}
  end

  def get_feature(name) do
    GenServer.call(Unleash.Repo, {:get_feature, name})
  end

  def get_all_feature_names do
    GenServer.call(Unleash.Repo, {:get_all_feature_names})
  end

  def handle_call({:get_feature, name}, _from, state) do
    feature = Features.get_feature(state, name)

    {:reply, feature, state}
  end

  def handle_call({:get_all_feature_names}, _from, state) do
    names = Features.get_all_feature_names(state)
    {:reply, names, state}
  end

  def handle_info({:initialize, etag, retries}, state) do
    if retries > 0 or retries <= -1 do
      {etag, response} =
        case Unleash.Config.client().features(etag) do
          :cached -> {etag, state}
          x -> x
        end

      features =
        case response do
          {:error, _} ->
            state
            |> read_state()
            |> schedule_features(etag, retries - 1)

          f ->
            schedule_features(f, etag)
        end

      if features === state do
        {:noreply, state}
      else
        write_state(features)
      end
    else
      Logger.debug(fn ->
        "Retries === 0, disabling polling"
      end)

      {:noreply, state}
    end
  end

  # https://github.com/appcues/mojito/issues/57
  # Work around for messages received from Mojito after we've passed over the timeout
  # threshold.
  def handle_info({:mojito_response, _ref, _message}, state) do
    {:noreply, state}
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
    Process.send(Unleash.Repo, {:initialize, nil, Config.retries()}, [])
  end

  defp schedule_features(state, etag, retries \\ Config.retries()) do
    Logger.debug(fn ->
      retries_log =
        if retries >= 0 do
          ", retries: #{retries}"
        else
          ""
        end

      "etag: #{etag}" <> retries_log
    end)

    Process.send_after(self(), {:initialize, etag, retries}, Config.features_period())
    state
  end
end
