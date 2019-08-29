defmodule Unleash.Client do
  @moduledoc false

  @callback features(String.t()) :: Tesla.Env.t()
  @callback register_client() :: Tesla.Env.t()
  @callback metrics(map()) :: Tesla.Env.t()

  require Logger

  alias Unleash.Config
  alias Unleash.Features
  @appname "UNLEASH-APPNAME"
  @instance_id "UNLEASH-INSTANCEID"
  @if_none_match "If-None-Match"
  @sdk_version "unleash_ex:#{Mix.Project.config()[:version]}"

  def features(etag \\ nil) do
    request =
      etag
      |> client()

    Logger.debug(fn ->
      "Request sent to features with #{inspect(request, pretty: true)}"
    end)

    response = Tesla.get(request, "/client/features")

    Logger.debug(fn ->
      "Result from features was #{inspect(response, pretty: true)}"
    end)

    response =
      case response do
        {:ok, tesla} -> tesla
        error -> error
      end

    case response do
      {:error, _} = error -> {nil, error}
      tesla -> handle_feature_response(tesla)
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

  def register(client), do: send_data("/client/register", client)

  def metrics(met), do: send_data("/client/metrics", met)

  defp handle_feature_response(tesla) do
    case tesla do
      %Tesla.Env{status: 304} -> :cached
      %Tesla.Env{status: 200} -> pull_out_data(tesla)
    end
  end

  defp pull_out_data(tesla) do
    features =
      tesla
      |> Map.from_struct()
      |> Map.get(:body, %{})
      |> Features.from_map!()

    etag =
      tesla
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
      |> (&Tesla.post(client(), url, &1)).()

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

  defp client(etag \\ nil) do
    headers =
      Config.custom_headers()
      |> Keyword.merge([
        {@appname, Config.appname()},
        {@instance_id, Config.instance_id()}
      ])

    headers =
      if etag do
        [{@if_none_match, etag} | headers]
      else
        headers
      end

    [
      {Tesla.Middleware.BaseUrl, Config.url()},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers, headers}
    ]
    |> Tesla.client()
  end

  defp tag_data(data) do
    data
    |> Map.put(:appName, Config.appname())
    |> Map.put(:instanceId, Config.instance_id())
  end
end
