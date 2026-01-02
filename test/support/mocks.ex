Mox.defmock(Unleash.ClientMock, for: Unleash.Client)
Mox.defmock(SimpleHttpMock, for: Unleash.Http.SimpleHttp.Behavior)

# Default stub implementation that provides safe fallbacks for global use
defmodule Unleash.ClientStub do
  @behaviour Unleash.Client

  def register_client, do: {:ok, %{}}
  def features(_), do: {:ok, %{etag: nil, features: %Unleash.Features{features: []}}}
  def metrics(_), do: {:ok, %SimpleHttp.Response{}}
end
