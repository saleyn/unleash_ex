defmodule Unleash.Repo do
  use GenServer

  alias Unleash.Client
  alias Unleash.Features

  def init(_) do
    {:ok, %Features{}}
  end

  def start_link(state) do
    {:ok, pid} = GenServer.start_link(__MODULE__, state, name: Unleash.Repo)

    initialize()

    {:ok, pid}
  end


  def get_feature(name) do
    GenServer.call(Unleash.Repo, {:get_feature, name})
  end

  def handle_call({:get_feature, name}, _from, state) do
    feature = Features.get_feature(state, name)

    {:reply, feature, state}
  end

  def handle_cast(:initialize, _state) do
    case Client.features() do
      {:ok, features} -> {:noreply, features}
      {:error, r} -> {:stop, r}
    end
  end

  defp initialize() do
    GenServer.cast(Unleash.Repo, :initialize)
  end
end
