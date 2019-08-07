defmodule Unleash do
  use Application
  require Logger

  alias Unleash.Repo
  alias Unleash.Client
  alias Unleash.Metrics
  alias Unleash.Feature

  @spec enabled?(atom() | String.t(), boolean) :: boolean
  def enabled?(feature, context) when is_boolean(context),
    do: enabled?(feature, %{}, context)

  @spec enabled?(atom() | String.t(), Map.t(), boolean) :: boolean
  def enabled?(feature, context \\ %{}, default \\ false) do
    case Repo.get_feature(feature) do
      %Feature{name: nil} -> default
      feature -> Feature.enabled?(feature, context)
    end
  end

  def start(_type, _args) do
    children = [
      Repo,
      Metrics
    ]

    result = Client.register_client()

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
