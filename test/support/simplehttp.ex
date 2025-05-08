defmodule Unleash.Http.SimpleHttp.Behavior do
  @moduledoc """
  From: https://github.com/appcues/mojito/blob/master/lib/mojito.ex#L191
  """
  @type header :: {String.t(), String.t()}
  @type headers :: [header]
  @type response :: %SimpleHttp.Response{
          status: pos_integer,
          headers: headers,
          body: String.t()
        }
  @callback get(String.t(), headers) :: {:ok, response} | no_return
  @callback post(String.t(), headers, String.t()) :: {:ok, response} | no_return
  @callback status_code!(response) :: pos_integer
  @callback response_headers!(response) :: headers
  @callback response_body!(response) :: String.t()
end
