defmodule Unleash do
  use Application
  require Logger

  alias Unleash.Repo
  alias Unleash.Client
  alias Unleash.Metrics
  alias Unleash.Feature

  @spec is_enabled?(atom() | String.t(), boolean) :: boolean
  def is_enabled?(feature, default) when is_boolean(default),
    do: enabled?(feature, default)

  @spec is_enabled?(atom() | String.t(), Map.t(), boolean) :: boolean
  def is_enabled?(feature, context \\ %{}, default \\ false),
    do: enabled?(feature, context, default)

  @spec enabled?(atom() | String.t(), boolean) :: boolean
  def enabled?(feature, context) when is_boolean(context),
    do: enabled?(feature, %{}, context)

  @spec enabled?(atom() | String.t(), Map.t(), boolean) :: boolean
  def enabled?(feature, context \\ %{}, default \\ false) do
    feature
    |> Repo.get_feature()
    |> case do
      %Feature{name: nil} -> {feature, default}
      feature -> {feature, Feature.enabled?(feature, context)}
    end
    |> Metrics.add_metric()
  end

  def start(_type, _args) do
    children = [
      Repo,
      Metrics
    ]

    Client.register_client()

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
