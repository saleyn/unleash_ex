defmodule Unleash do
  use Application

  alias Unleash.Repo
  alias Unleash.Feature

  def enabled?(feature, context \\ %{}) do
    Repo.get_feature(feature)
    |> Feature.enabled?(context)
  end

  def start(_type, _args) do
    children = [
      Repo
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
