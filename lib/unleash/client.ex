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

  def features(etag \\ nil) do
    headers = headers(etag)

    Logger.debug(fn ->
      "Request sent to features with #{inspect(headers, pretty: true)}"
    end)

    :telemetry.span(
      @telemetry_features_prefix,
      telemetry_metadata(%{etag: etag}),
      fn ->
        url = "#{Config.url()}/client/features"
        result = Config.http_client().get(url, headers)

        Logger.debug(fn ->
          "Result from features was #{inspect(result, pretty: true)}"
        end)

        case result do
          {:ok, response} ->
            {result, metadata} = handle_feature_response(response)

            {result, telemetry_metadata(metadata)}

          {:error, error} ->
            {{nil, error}, telemetry_metadata(%{error: error})}
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

  def register(client), do: send_data("#{Config.url()}/client/register", client)

  def metrics(met), do: send_data("#{Config.url()}/client/metrics", met)

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

  def telemetry_metadata(metadata \\ %{}) do
    Map.merge(
      %{appname: Config.appname(), instance_id: Config.instance_id()},
      metadata
    )
  end
end
