defmodule Unleash.Cache do
  @moduledoc """
  This module is a cache backed by an ETS table. We use it to allow for multiple
  threads to read the feature flag values concurrently on top of minimizing
  network calls
  """

  @cache_table_name :unleash_cache

  def cache_table_name, do: @cache_table_name

  @doc """
  Will create a new ETS table named `:unleash_cache`
  """
  def init(existing_features \\ [], table_name \\ @cache_table_name) do
    :ets.new(table_name, [:named_table, read_concurrency: true])

    upsert_features(existing_features, table_name)
  end

  @doc """
  Will return all values currently stored in the cache
  """
  def get_all_feature_names(table_name \\ @cache_table_name) do
    features = :ets.tab2list(table_name)

    Enum.map(features, fn {name, _feature} ->
      name
    end)
  end

  @doc """
  Will return all features stored in the cache
  """
  def get_features(table_name \\ @cache_table_name) do
    features = :ets.tab2list(table_name)

    Enum.map(features, fn {_name, feature} ->
      feature
    end)
  end

  @doc """
  Will return the feature for the given name stored in the cache
  """
  def get_feature(name, table_name \\ @cache_table_name)

  def get_feature(name, table_name) when is_binary(name) do
    case :ets.lookup(table_name, name) do
      [{^name, feature}] -> feature
      [] -> nil
    end
  end

  def get_feature(name, table_name) when is_atom(name),
    do: get_feature(Atom.to_string(name), table_name)

  @doc """
  Will upsert (create or update) the given features in the cache

  This will clear the existing peristed features to prevent stale reads
  """
  def upsert_features(features, table_name \\ @cache_table_name) do
    :ets.delete_all_objects(table_name)

    Enum.each(features, fn feature ->
      upsert_feature(feature.name, feature, table_name)
    end)
  end

  defp upsert_feature(name, value, table_name) when is_binary(name) do
    :ets.insert(table_name, {name, value})
  end

  defp upsert_feature(name, value, table_name) when is_atom(name) do
    upsert_feature(Atom.to_string(name), value, table_name)
  end
end
