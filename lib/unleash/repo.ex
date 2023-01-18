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
    telemetry_metadata = Unleash.Client.telemetry_metadata(%{retries: retries, etag: etag})

    if retries > 0 or retries <= -1 do
      cached_features = %Features{features: Cache.get_features()}

      {source, remote_features} =
        case Unleash.Config.client().features(etag) do
          :cached ->
            {:cache, schedule_features(cached_features, etag)}

          {:error, _} ->
            {source, features} = read_file_state(cached_features)

            {source, schedule_features(features, etag, retries - 1)}

          {etag, features} ->
            {:remote, schedule_features(features, etag)}
        end

      :telemetry.execute(
        [:unleash, :repo, :features_update],
        %{},
        Map.put(telemetry_metadata, :source, source)
      )

      if remote_features === cached_features do
        {:noreply, state}
      else
        Cache.upsert_features(remote_features.features)
        write_file_state(remote_features)
        {:noreply, state}
      end
    else
      :telemetry.execute([:unleash, :repo, :disable_polling], telemetry_metadata)

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
      {:backup_file,
       Config.backup_file()
       |> File.read!()
       |> Jason.decode!()
       |> Features.from_map!()}
    else
      {:cache, cached_features}
    end
  end

  defp read_file_state(cached_features), do: {:cache, cached_features}

  defp write_file_state(features) do
    :ok = File.mkdir_p(Config.backup_dir())

    content = Jason.encode_to_iodata!(features)

    Config.backup_file()
    |> File.write!(content)

    :telemetry.execute(
      [:unleash, :repo, :backup_file_update],
      %{},
      Unleash.Client.telemetry_metadata(%{
        content: content,
        filename: Config.backup_file()
      })
    )
  end

  defp initialize do
    Process.send(Unleash.Repo, {:initialize, nil, Config.retries()}, [])
  end

  defp schedule_features(features, etag, retries \\ Config.retries()) do
    :telemetry.execute(
      [:unleash, :repo, :schedule],
      %{},
      Unleash.Client.telemetry_metadata(%{
        retries: retries,
        etag: etag,
        interval: Config.features_period()
      })
    )

    Process.send_after(self(), {:initialize, etag, retries}, Config.features_period())

    features
  end
end
