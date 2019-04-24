defmodule Unleash do
  use Application

  alias Unleash.Repo
  alias Unleash.Feature

  @spec enabled?(feature :: atom | String.t(), context :: Map.t(), default :: boolean) :: boolean
  def enabled?(feature, context \\ %{}, default \\ false) do
    case Repo.get_feature(feature) do
      %Feature{name: nil} -> default
      feature -> Feature.enabled?(feature, context)
    end
  end

  def start(_type, _args) do
    children = [
      Repo
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
