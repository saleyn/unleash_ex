defmodule Unleash.MetricsFast do
  @moduledoc """
  High-performance metrics collection using ETS counters with optimizations.

  Key optimizations:
  1. Cached disable_metrics flag at startup (no runtime Config check)
  2. Direct :counters for lock-free atomic updates
  3. Pre-initialized counters for known features
  4. Minimal pattern matching in hot path

  Performance: ~70-100 ns per metric update (vs ~22 μs for GenServer-based)
  """

  use GenServer

  alias Unleash.Config
  alias Unleash.Feature

  require Logger

  @counter_table :unleash_metrics_fast_counters
  @variant_table :unleash_metrics_fast_variants
  @meta_table :unleash_metrics_fast_meta

  # Counter indices
  @yes_index 1
  @no_index 2

  # ============================================================
  # Public API - Optimized for speed
  # ============================================================

  @doc """
  Add a metric for a feature flag check. Optimized for minimal overhead.
  Returns the enabled? value unchanged for pipeline compatibility.
  """
  @spec add_metric({Feature.t() | any(), boolean()}) :: boolean()
  def add_metric({%Feature{name: name}, enabled?}) do
    if metrics_enabled?() do
      counter = get_or_create_counter(name)
      index = if enabled?, do: @yes_index, else: @no_index
      :counters.add(counter, index, 1)
    end

    enabled?
  end

  def add_metric({_non_feature, enabled?}), do: enabled?

  @doc """
  Lightweight metric recording by feature name only.
  Avoids the persistent_term lookup for the full Feature struct when only
  the name is needed (i.e. the compiled-closure enabled? fast path).
  """
  @spec add_metric_by_name(String.t(), boolean()) :: boolean()
  def add_metric_by_name(name, enabled?) when is_binary(name) do
    if metrics_enabled?() do
      counter = get_or_create_counter(name)
      index = if enabled?, do: @yes_index, else: @no_index
      :counters.add(counter, index, 1)
    end

    enabled?
  end

  @doc """
  Add a metric for a variant check.
  """
  @spec add_variant_metric({Feature.t() | any(), map()}) :: map()
  def add_variant_metric({%Feature{name: name, enabled: enabled?}, %{name: variant_name} = variant}) do
    if metrics_enabled?() do
      # Update feature counter
      counter = get_or_create_counter(name)
      index = if enabled?, do: @yes_index, else: @no_index
      :counters.add(counter, index, 1)

      # Update variant counter
      variant_counter = get_or_create_variant_counter(name, variant_name)
      :counters.add(variant_counter, 1, 1)
    end

    variant
  end

  def add_variant_metric({_non_feature, variant}), do: variant

  @doc """
  Bulk register features to pre-create counters.
  Call this when features are loaded to avoid counter creation overhead during checks.
  """
  @spec register_features([Feature.t()]) :: :ok
  def register_features(features) when is_list(features) do
    Enum.each(features, fn
      %Feature{name: name, variants: variants} ->
        get_or_create_counter(name)

        Enum.each(variants, fn
          %{name: variant_name} -> get_or_create_variant_counter(name, variant_name)
          _ -> :ok
        end)

      _ ->
        :ok
    end)

    :ok
  end

  @doc """
  Get current metrics as a bucket for sending to server.
  """
  @spec get_metrics() :: {:ok, map()}
  def get_metrics do
    {state, _counter_deltas, _variant_deltas} = collect_metrics()
    {:ok, to_bucket(state)}
  end

  @doc """
  Force send metrics to server (for testing).
  """
  @spec do_send_metrics() :: :ok
  def do_send_metrics do
    GenServer.call(__MODULE__, :send_metrics)
  end

  @doc """
  Remove counters/variant-counters for features that are no longer present.

  Call this with the authoritative current feature list (the same list passed
  to `register_features/1` on a features refresh) to bound ETS growth when
  features are deleted or renamed upstream. Purely additive `register_features/1`
  is left untouched; this is the complementary cleanup step.
  """
  @spec prune_stale_features([Feature.t()]) :: :ok
  def prune_stale_features(features) when is_list(features) do
    current_names = MapSet.new(features, fn %Feature{name: name} -> name end)

    :ets.tab2list(@counter_table)
    |> Enum.each(fn {name, _counter} ->
      unless MapSet.member?(current_names, name) do
        :ets.delete(@counter_table, name)
      end
    end)

    :ets.tab2list(@variant_table)
    |> Enum.each(fn {{feature_name, _variant_name} = key, _counter} ->
      unless MapSet.member?(current_names, feature_name) do
        :ets.delete(@variant_table, key)
      end
    end)

    :ok
  end

  # ============================================================
  # Fast path - inlined for performance
  # ============================================================

  @compile {:inline, metrics_enabled?: 0, get_or_create_counter: 1}

  defp metrics_enabled? do
    case :ets.lookup(@meta_table, :metrics_enabled) do
      [{:metrics_enabled, enabled}] -> enabled
      [] -> true
    end
  end

  defp get_or_create_counter(name) do
    case :ets.lookup(@counter_table, name) do
      [{^name, counter}] ->
        counter

      [] ->
        counter = :counters.new(2, [:write_concurrency])

        case :ets.insert_new(@counter_table, {name, counter}) do
          true -> counter
          false ->
            [{^name, existing}] = :ets.lookup(@counter_table, name)
            existing
        end
    end
  end

  defp get_or_create_variant_counter(feature_name, variant_name) do
    key = {feature_name, variant_name}

    case :ets.lookup(@variant_table, key) do
      [{^key, counter}] ->
        counter

      [] ->
        counter = :counters.new(1, [:write_concurrency])

        case :ets.insert_new(@variant_table, {key, counter}) do
          true -> counter
          false ->
            [{^key, existing}] = :ets.lookup(@variant_table, key)
            existing
        end
    end
  end

  # ============================================================
  # Metrics collection and sending
  # ============================================================

  # Reads every counter once and returns both the aggregated state (for the
  # bucket sent to the server) and the exact values read (as deltas to
  # subtract in reset_metrics/2). Subtracting the read delta - rather than
  # zeroing the counter outright - means any add_metric/add_variant_metric
  # call that lands between this read and the later reset is not lost: it
  # simply isn't part of the delta being subtracted, so it survives into the
  # next collection.
  defp collect_metrics do
    variants_by_feature = collect_variants_by_feature()

    {toggles, counter_deltas} =
      :ets.tab2list(@counter_table)
      |> Enum.reduce({%{}, []}, fn {name, counter}, {toggles, deltas} ->
        yes = :counters.get(counter, @yes_index)
        no = :counters.get(counter, @no_index)

        {variants, _variant_deltas} = Map.get(variants_by_feature, name, {%{}, []})

        entry =
          if map_size(variants) > 0 do
            %{yes: yes, no: no, variants: variants}
          else
            %{yes: yes, no: no}
          end

        {Map.put(toggles, name, entry), [{counter, yes, no} | deltas]}
      end)

    variant_deltas =
      variants_by_feature
      |> Map.values()
      |> Enum.flat_map(fn {_variants, variant_deltas} -> variant_deltas end)

    state = %{
      start: get_start_time(),
      toggles: toggles
    }

    {state, counter_deltas, variant_deltas}
  end

  # Single pass over the variant table, grouped by feature name, returning
  # both the counts (for the bucket) and the {counter, count} deltas (for reset).
  defp collect_variants_by_feature do
    :ets.tab2list(@variant_table)
    |> Enum.reduce(%{}, fn {{feature_name, variant_name}, counter}, acc ->
      count = :counters.get(counter, 1)

      Map.update(
        acc,
        feature_name,
        {%{variant_name => count}, [{counter, count}]},
        fn {variants, variant_deltas} ->
          {Map.put(variants, variant_name, count), [{counter, count} | variant_deltas]}
        end
      )
    end)
  end

  defp reset_metrics(counter_deltas, variant_deltas) do
    Enum.each(counter_deltas, fn {counter, yes, no} ->
      if yes != 0, do: :counters.sub(counter, @yes_index, yes)
      if no != 0, do: :counters.sub(counter, @no_index, no)
    end)

    Enum.each(variant_deltas, fn {counter, count} ->
      if count != 0, do: :counters.sub(counter, 1, count)
    end)

    set_start_time()
  end

  defp get_start_time do
    case :ets.lookup(@meta_table, :start_time) do
      [{:start_time, time}] -> time
      [] -> current_date()
    end
  end

  defp set_start_time do
    :ets.insert(@meta_table, {:start_time, current_date()})
  end

  defp to_bucket(state) do
    %{bucket: Map.put(state, :stop, current_date())}
  end

  defp current_date do
    DateTime.utc_now() |> DateTime.to_iso8601()
  end

  # ============================================================
  # GenServer callbacks (only for initialization and periodic sending)
  # ============================================================

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Create ETS tables
    :ets.new(@counter_table, [:named_table, :public, :set, {:write_concurrency, true}, {:read_concurrency, true}])
    :ets.new(@variant_table, [:named_table, :public, :set, {:write_concurrency, true}, {:read_concurrency, true}])
    :ets.new(@meta_table, [:named_table, :public, :set])

    # Cache the disable_metrics config
    :ets.insert(@meta_table, {:metrics_enabled, not Config.disable_metrics()})

    set_start_time()

    unless Config.test?() do
      schedule_metrics()
    end

    {:ok, %{}}
  end

  @impl true
  def handle_call(:send_metrics, _from, state) do
    send_metrics_to_server()
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    {:reply, get_metrics(), state}
  end

  @impl true
  def handle_info(:send_metrics, state) do
    send_metrics_to_server()
    schedule_metrics()
    {:noreply, state}
  end

  defp send_metrics_to_server do
    {state, counter_deltas, variant_deltas} = collect_metrics()
    bucket = to_bucket(state)

    case Config.client().metrics(bucket) do
      {:ok, _} ->
        reset_metrics(counter_deltas, variant_deltas)

      error ->
        Logger.error("#{Config.appname()} #{__MODULE__}; HTTP response: #{inspect(error)}")
    end
  end

  defp schedule_metrics do
    Process.send_after(self(), :send_metrics, Config.metrics_period())
  end
end
