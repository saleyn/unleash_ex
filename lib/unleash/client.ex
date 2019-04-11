defmodule Unleash.Client do
  alias Unleash.Config
  @appname "UNLEASH-APPNAME"
  @instance_id "UNLEASH-INSTANCEID"

  def features() do
    client()
    |> Tesla.get("/api/client/features")
  end

  def register(client), do: send_data("/api/client/register", client)

  def metrics(met), do: send_data("/api/client/metrics", met)

  defp send_data(url, data) do
    data
    |> tag_data()
    |> (&Tesla.post(client(), url, &1)).()
  end

  defp client() do
    [
      {Tesla.Middleware.BaseUrl, Config.url()},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers,
       [
         {@appname, Config.appname()},
         {@instance_id, Config.instance_id()}
       ]}
    ]
    |> Tesla.client()

  defp tag_data(data) do
    data
    |> Map.put(:app_name, Config.appname())
    |> Map.put(:instance_id, Config.instance_id())
  end
end
