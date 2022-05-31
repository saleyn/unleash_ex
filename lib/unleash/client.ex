defmodule Unleash.Client do
  @moduledoc false

  @callback features(String.t()) :: Mojito.response()
  @callback register_client() :: Mojito.response()
  @callback metrics(map()) :: Mojito.response()

  require Logger

  alias Unleash.Config
  alias Unleash.Features
  @appname "UNLEASH-APPNAME"
  @instance_id "UNLEASH-INSTANCEID"
  @if_none_match "If-None-Match"
  @sdk_version "unleash_ex:#{Mix.Project.config()[:version]}"
  @accept {"Accept", "application/json"}
  @content_type {"Content-Type", "application/json"}

  def features(etag \\ nil) do
    headers = headers(etag)

    Logger.debug(fn ->
      "Request sent to features with #{inspect(headers, pretty: true)}"
    end)

    response = Config.http_client().get("#{Config.url()}/client/features", headers)

    Logger.debug(fn ->
      "Result from features was #{inspect(response, pretty: true)}"
    end)

    response =
      case response do
        {:ok, mojito} -> mojito
        error -> error
      end

    case response do
      {:error, _} = error -> {nil, error}
      mojito -> handle_feature_response(mojito)
    end
  end

  def register_client,
    do:
      register(%{
        sdkVersion: @sdk_version,
        strategies: Config.strategy_names(),
        started:
          DateTime.utc_now()
          |> DateTime.to_iso8601(),
        interval: Config.metrics_period()
      })

  def register(client), do: send_data("#{Config.url()}/client/register", client)

  def metrics(met), do: send_data("#{Config.url()}/client/metrics", met)

  defp handle_feature_response(mojito) do
    case mojito do
      %Mojito.Response{status_code: 304} ->
        :cached

      %Mojito.Response{status_code: 200} ->
        pull_out_data(mojito)

      resp = %Mojito.Response{status_code: _status} ->
        Logger.warn(fn ->
          "Unexpected response #{inspect(resp)}. Using cached features"
        end)

        :cached
    end
  end

  defp pull_out_data(mojito) do
    features =
      mojito
      |> Map.from_struct()
      |> Map.get(:body, "")
      |> Jason.decode!()
      |> Features.from_map!()

    etag =
      mojito
      |> Map.from_struct()
      |> Map.get(:headers, [])
      |> Enum.into(%{})
      |> Map.get("etag", nil)

    {etag, features}
  end

  defp send_data(url, data) do
    result =
      data
      |> tag_data()
      |> Jason.encode!()
      |> (&Config.http_client().post(url, headers(), &1)).()

    Logger.debug(fn ->
      "Request sent to #{url} with #{inspect(data, pretty: true)}"
    end)

    case result do
      {:ok, r} ->
        Logger.debug(fn ->
          "Result from #{url} was #{inspect(r, pretty: true)}"
        end)

      {:error, e} ->
        Logger.error(fn ->
          "Request #{inspect(data, pretty: true)} failed with result #{inspect(e, pretty: true)}"
        end)
    end

    result
  end

  defp headers(nil), do: headers()

  defp headers(etag),
    do: headers() ++ [{@if_none_match, etag}]

  defp headers,
    do:
      Config.custom_headers() ++
        [
          {@appname, Config.appname()},
          {@instance_id, Config.instance_id()},
          @accept,
          @content_type
        ]

  defp tag_data(data) do
    data
    |> Map.put(:appName, Config.appname())
    |> Map.put(:instanceId, Config.instance_id())
  end
end
