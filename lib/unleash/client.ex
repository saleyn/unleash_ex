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

  @telemetry_features_prefix [:unleash, :client, :fetch_features]
  @telemetry_register_prefix [:unleash, :client, :register]

  def features(etag \\ nil) do
    headers = headers(etag)
    url = "#{Config.url()}/client/features"

    Logger.debug(fn ->
      "Request sent to features with #{inspect(headers, pretty: true)}"
    end)

    start_metadata = telemetry_metadata(%{etag: etag, url: url})

    :telemetry.span(
      @telemetry_features_prefix,
      start_metadata,
      fn ->
        result = Config.http_client().get(url, headers)

        Logger.debug(fn ->
          "Result from features was #{inspect(result, pretty: true)}"
        end)

        case result do
          {:ok, response} ->
            {result, metadata} = handle_feature_response(response)
            {result, Map.merge(start_metadata, metadata)}

          {:error, error} ->
            {{nil, error}, Map.put(start_metadata, :error, error)}
        end
      end
    )
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

  def register(client) do
    url = "#{Config.url()}/client/register"

    start_metadata =
      client
      |> Map.take([:sdkVersion, :strategies, :interval])
      |> Map.new(fn
        {:sdkVersion, value} -> {:sdk_version, value}
        {key, value} -> {key, value}
      end)
      |> Map.put(:url, url)
      |> telemetry_metadata()

    :telemetry.span(
      @telemetry_register_prefix,
      start_metadata,
      fn ->
        {result, metadata}= send_data(url, client)
        {result, Map.merge(start_metadata, metadata)}
      end
    )
  end

  def metrics(met) do
    {result, _metadata} = send_data("#{Config.url()}/client/metrics", met)

    result
  end

  defp handle_feature_response(mojito) do
    case mojito do
      %Mojito.Response{status_code: 304} ->
        {:cached, %{http_response_status: 304}}

      %Mojito.Response{status_code: 200} ->
        pull_out_data(mojito)

      resp = %Mojito.Response{status_code: status} ->
        Logger.warn(fn ->
          "Unexpected response #{inspect(resp)}. Using cached features"
        end)

        {:cached, %{http_response_status: status}}
    end
  end

  defp pull_out_data(mojito) do
    features =
      mojito
      |> Map.get(:body, "")
      |> Jason.decode!()
      |> Features.from_map!()

    etag =
      mojito
      |> Map.get(:headers, [])
      |> Map.new()
      |> Map.get("etag", nil)

    {{etag, features}, %{http_response_status: 200, etag: etag}}
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
      {:ok, %Mojito.Response{status_code: status_code} = response} ->
        Logger.debug(fn ->
          "Result from #{url} was #{inspect(response, pretty: true)}"
        end)

        {{:ok, response}, %{http_response_status: status_code}}

      {:error, e} ->
        Logger.error(fn ->
          "Request #{inspect(data, pretty: true)} failed with result #{inspect(e, pretty: true)}"
        end)

        {{:error, e}, %{error: e}}
    end
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

  def telemetry_metadata(metadata \\ %{}) do
    Map.merge(
      %{appname: Config.appname(), instance_id: Config.instance_id()},
      metadata
    )
  end
end
