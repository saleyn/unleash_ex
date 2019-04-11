defmodule Unleash.Client do
  alias Unleash.Config
  @appname "UNLEASH-APPNAME"
  @instance_id "UNLEASH-INSTANCEID"

  def features() do
    client()
    |> Tesla.get("/api/client/features")
  end

  def register(client) do
    client
    |> tag_data()
    |> (&Tesla.post(client(), url, &1)).()
  end

  @spec metrics(met :: Map.t()) :: Tesla.Result.t()
  def metrics(met) do
    met
    |> tag_data()
    |> (&post("/api/client/metrics", &1)).()
  end

  defp tag_data(data),
    do: %{
      data
      | app_name: Application.get_env(:unleash, :appname),
        instance_id: Application.get_env(:unleash, :instance_id)
    }

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
  end
end
