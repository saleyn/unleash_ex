defmodule Unleash.Features do
  alias Unleash.Feature

  defstruct version: "1", features: []

  def enabled?(nil, _feature), do: false

  def enabled?(%__MODULE__{features: nil}, _feature), do: false

  def enabled?(%__MODULE__{}, nil), do: false

  def enabled?(%__MODULE__{features: features} = state, feat)
      when is_list(features) and is_atom(feat) do
    enabled?(state, Atom.to_string(feat))
  end

  def enabled?(%__MODULE__{features: features}, feat)
      when is_list(features) and is_binary(feat) do
    features
    |> Enum.find(fn feature -> feature.name == feat end)
    |> Feature.enabled?()
  end
end
