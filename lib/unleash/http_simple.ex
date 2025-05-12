defmodule Unleash.Http.SimpleHttp do
  alias Unleash.Config

  def get(url, headers) do
    opts = Config.http_opts()
    {opt_headers, opts} = Map.pop(opts, :headers, [])
    headers = SimpleHttp.List.merge(opt_headers, headers)
    SimpleHttp.get(url, [{:headers, headers} | Map.to_list(opts)])
  end

  def post(url, headers, body \\ "") do
    opts = Config.http_opts()
    {opt_headers, opts} = Map.pop(opts, :headers, [])

    headers =
      opt_headers
      |> SimpleHttp.List.merge(headers)
      |> case do
        list when body == "" -> list
        list -> [{"Content-Type", "application/json"} | list]
      end

    SimpleHttp.post(url, [{:headers, headers}, {:body, body} | Map.to_list(opts)])
  end

  def status_code!({:ok, %SimpleHttp.Response{status: code}}), do: code
  def status_code!({:error, reason}) when is_atom(reason), do: :erlang.error(reason)
  def status_code!({:error, reason}), do: RuntimeError.exception(reason)

  def response_body!({:ok, %SimpleHttp.Response{body: body}}), do: body
  def response_body!({:error, reason}) when is_atom(reason), do: :erlang.error(reason)
  def response_body!({:error, reason}), do: RuntimeError.exception(reason)

  def response_headers!({:ok, %SimpleHttp.Response{headers: hdrs}}), do: hdrs
  def response_headers!({:error, reason}) when is_atom(reason), do: :erlang.error(reason)
  def response_headers!({:error, reason}), do: RuntimeError.exception(reason)
end
