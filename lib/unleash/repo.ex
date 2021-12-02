defmodule Unleash.Repo do
  @moduledoc """
  This genserver polls the unleash service each time the given interval has
  elapsed, refreshing both our local ETS cache and the backup state file if the
  flag state has diverged.

  The following configuration values are used:

  Config.features_period(): polling interval - default 15 seconds
  Config.retries(): number of time the call to refresh values is allowed to retry - default -1 (0)
  """

  use GenServer
  require Logger

  alias Unleash.Cache
  alias Unleash.Config
  alias Unleash.Features

  def init(%Features{} = features) do
    Cache.init(features.features)
    {:ok, []}
  end

  def init(_) do
    Cache.init()
    {:ok, []}
  end

  def start_link(state) do
    {:ok, pid} = GenServer.start_link(__MODULE__, state, name: Unleash.Repo)

    unless Config.test?() do
      initialize()
    end

    {:ok, pid}
  end

  def get_feature(name) do
    Cache.get_feature(name)
  end

  def get_all_feature_names do
    Cache.get_all_feature_names()
  end

  def handle_info({:initialize, etag, retries}, state) do
    if retries > 0 or retries <= -1 do
      cached_features = %Features{features: Cache.get_features()}

      {etag, response} =
        case Unleash.Config.client().features(etag) do
          :cached -> {etag, cached_features}
          x -> x
        end

      remote_features =
        case response do
          {:error, _} ->
            cached_features
            |> read_file_state()
            |> schedule_features(etag, retries - 1)

          f ->
            schedule_features(f, etag)
        end

      if remote_features === cached_features do
        {:noreply, state}
      else
        Cache.upsert_features(remote_features.features)
        write_file_state(remote_features)
        {:noreply, state}
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

  defp read_file_state(%Features{features: []} = cached_features) do
    if File.exists?(Config.backup_file()) do
      Config.backup_file()
      |> File.read!()
      |> Jason.decode!()
      |> Features.from_map!()
    else
      cached_features
    end
  end

  defp read_file_state(cached_features), do: cached_features

  defp write_file_state(features) do
    :ok = File.mkdir_p(Config.backup_dir())

    content = Jason.encode_to_iodata!(features)

    Config.backup_file()
    |> File.write!(content)

    Logger.debug(fn ->
      ["Wrote ", content, " to file ", Config.backup_file()]
    end)
  end

  defp initialize do
    Process.send(Unleash.Repo, {:initialize, nil, Config.retries()}, [])
  end

  defp schedule_features(features, etag, retries \\ Config.retries()) do
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
    features
  end
end
