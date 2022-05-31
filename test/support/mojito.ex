defmodule Mojito.Behavior do
  @moduledoc """
  From: https://github.com/appcues/mojito/blob/master/lib/mojito.ex#L191
  """
  @type header :: {String.t(), String.t()}
  @type headers :: [header]
  @type response :: %Mojito.Response{
          status_code: pos_integer,
          headers: headers,
          body: String.t(),
          complete: boolean
        }
  @type error :: %Mojito.Error{
          reason: any,
          message: String.t() | nil
        }

  @callback get(String.t(), headers) :: {:ok, response} | {:error, error} | no_return
  @callback post(String.t(), headers, String.t()) :: {:ok, response} | {:error, error} | no_return
end
