defmodule Unleash do
  use Application
  require Logger

  alias Unleash.Repo
  alias Unleash.Client
  alias Unleash.Metrics
  alias Unleash.Feature
  alias Unleash.Config

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
    if Config.disable_client() do
      Logger.warn(fn ->
        "Client is disabled, it will only return default: #{default}"
      end)

      default
    else
      feature
      |> Repo.get_feature()
      |> case do
        %Feature{name: nil} -> {feature, default}
        feature -> {feature, Feature.enabled?(feature, context)}
      end
      |> Metrics.add_metric()
    end
  end

  def start(_type, _args) do
    children = []

    unless Config.disable_client() do
      children = [Repo | children]
      Client.register_client()

      unless Config.disable_metrics() do
        children = [Metrics | children]
      end
    end

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
