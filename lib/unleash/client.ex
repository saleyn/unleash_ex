defmodule Unleash.Client do
  @moduledoc false

  require Logger

  alias Unleash.Config
  alias Unleash.Features
  @appname "UNLEASH-APPNAME"
  @instance_id "UNLEASH-INSTANCEID"
  @if_none_match "If-None-Match"

  def features(etag \\ nil) do
    response =
      etag
      |> client()
      |> Tesla.get("/api/client/features")
      |> case do
        {:ok, tesla} -> tesla
        error -> error
      end

    case response do
      {:error, _} = error -> error
      tesla -> handle_feature_response(tesla)
    end
  end

  def register_client,
    do:
      register(%{
        sdkVersion: "unleash_ex:",
        strategies: Config.strategy_names(),
        started:
          DateTime.utc_now()
          |> DateTime.to_iso8601(),
        interval: Config.metrics_period()
      })

  def register(client), do: send_data("/api/client/register", client)

  def metrics(met), do: send_data("/api/client/metrics", met)

  defp handle_feature_response(tesla) do
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

    if etag do
      [{@if_none_match, etag} | headers]
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
