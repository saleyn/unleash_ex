# Unleash Metrics Performance Benchmark Report

## Overview

This report documents the performance analysis and optimization of the metrics collection system in the Unleash Elixir client. The goal was to profile the existing `handle_metric` and `add_metric` functions and explore optimizations for high-throughput scenarios.

## Test Environment

- **OS**: macOS Darwin 25.5.0
- **CPU**: Apple M2 Pro (12 cores)
- **Memory**: 16 GB
- **Elixir**: 1.20.2
- **Erlang/OTP**: 29.0.2
- **JIT**: Enabled

> Note: numbers below were re-run from scratch and are not directly comparable to any prior run of
> this report on different hardware/Elixir versions — re-run `mix benchmark.metrics` on your own
> target environment before making capacity decisions.

## Benchmark Results

### 1. handle_metric Function (Internal)

The `handle_metric` function is the core logic that updates the metrics state map.

#### Single Call Performance

| Operation | Throughput | Avg Time | Memory |
|-----------|-----------|----------|--------|
| Non-feature (early return) | 123.48 M/s | 8.10 ns | 0 B |
| Enabled: true | 16.68 M/s | 59.95 ns | 88 B |
| Enabled: false | 17.45 M/s | 57.31 ns | 88 B |

#### Map Size Impact

| State Size | Throughput | Avg Time | Memory |
|------------|-----------|----------|--------|
| 1 toggle | 11.44 M/s | 87.40 ns | 112 B |
| 100 toggles | 7.55 M/s | 132.49 ns | 336 B |

**Finding**: Map size has minimal impact (~1.5x slower) due to Elixir's efficient persistent data structures.

---

### 2. add_metric Function (GenServer-based)

The `Unleash.Metrics` module uses `GenServer.cast` for async metric recording.

#### Single Call Performance

| Operation | Throughput | Avg Time | Memory |
|-----------|-----------|----------|--------|
| add_metric (enabled: true) | 69.55 K/s | 14.38 μs | 1.70 KB |
| add_metric (enabled: false) | 69.31 K/s | 14.43 μs | 1.70 KB |
| add_metric (non-feature) | 68.90 K/s | 14.51 μs | 1.70 KB |

#### Stress Test - 100K Calls

| Scenario | Time per 100K | Memory | Per-call |
|----------|---------------|--------|----------|
| Single feature | 1.53 s | 3.08 GB | 15.3 μs |
| Round-robin (10 features) | 1.55 s | 3.08 GB | 15.5 μs |
| Random feature | 1.56 s | 3.09 GB | 15.6 μs |

**Finding**: GenServer cast overhead (~14 μs) dominates performance. Memory usage is high due to message queue buildup.

---

### 3. Optimized Implementation (MetricsFast)

`Unleash.MetricsFast` is an ETS-based implementation using `:counters` for lock-free atomic updates.
It is now the **default** metrics module (`fast_metrics: true`, see `lib/unleash/config.ex`).

#### Single Call Performance

| Implementation | Throughput | Avg Time | Memory |
|----------------|-----------|----------|--------|
| **MetricsFast** | **6.88 M/s** | **0.145 μs** | **0.156 KB** |
| Metrics (GenServer) | 68.8 K/s | 14.54 μs | 1.70 KB |

#### Stress Test - 100K Calls

| Implementation | Time per 100K | Memory | Per-call |
|----------------|---------------|--------|----------|
| **MetricsFast** | **16.1 ms** | **20.1 MB** | **0.161 μs** |
| Metrics (GenServer) | 1.64 s | 3.08 GB | 16.4 μs |

#### Direct Counter Comparison (no Config/Enum overhead)

An additional micro-benchmark isolates the raw `:counters.add/3` call from the rest of
`MetricsFast`'s hot path (ETS lookup, config check, feature struct pattern match) against the raw
`handle_metric` map-update logic used internally by `Unleash.Metrics`:

| Implementation | Throughput | Avg Time (100K) | Memory |
|----------------|-----------|------------------|--------|
| Direct `:counters.add/3` | 653.57/s | 1.53 ms | 1.53 MB |
| Direct `handle_metric` (map update) | 71.10/s | 14.06 ms | 19.04 MB |

This isolates *why* `MetricsFast` is fast: the atomic counter increment itself is ~9x cheaper than
the map-rebuild `handle_metric` does per call, before any GenServer messaging is even considered.

---

## Performance Comparison Summary

| Metric | GenServer (Legacy) | MetricsFast (Default) | Improvement |
|--------|---------------------|-------------------------|-------------|
| Single call latency | 14.54 μs | 0.145 μs | **~100x faster** |
| 100K calls duration | 1.64 s | 16.1 ms | **~102x faster** |
| Memory (100K calls) | 3.08 GB | 20.1 MB | **~153x less** |
| Throughput | 68.8 K/s | 6.88 M/s | **~100x higher** |

---

## Bottleneck Analysis

### GenServer Implementation Bottlenecks

1. **Message Passing Overhead**: Each `GenServer.cast` requires message serialization and copying between processes (~14 μs overhead on this hardware)

2. **Single Process Serialization**: All metrics flow through one GenServer, creating a serialization point

3. **Memory Pressure**: Message queue growth under high load causes significant memory allocation

4. **Config Check**: `Config.disable_metrics()` is called on every invocation

### Optimizations Applied in MetricsFast

| Optimization | Impact |
|--------------|--------|
| ETS `:counters` | Lock-free atomic updates, no message passing |
| Cached `disable_metrics` flag | Eliminates runtime config lookup |
| Pre-registered features | Avoids counter creation in hot path |
| `write_concurrency` + `read_concurrency` | Optimized concurrent ETS access |
| Direct function calls | No GenServer overhead |

---

## Implementation Details

### MetricsFast Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    MetricsFast                          │
├─────────────────────────────────────────────────────────┤
│  ETS Tables (public, concurrent access)                 │
│  ┌─────────────────┐  ┌─────────────────┐              │
│  │ :counters table │  │ :variants table │              │
│  │ feature -> ref  │  │ {feat,var}->ref │              │
│  └────────┬────────┘  └────────┬────────┘              │
│           │                    │                        │
│           ▼                    ▼                        │
│  ┌─────────────────────────────────────────┐           │
│  │     :counters (atomics-based)           │           │
│  │     Lock-free increment operations      │           │
│  └─────────────────────────────────────────┘           │
├─────────────────────────────────────────────────────────┤
│  GenServer (only for periodic sending)                  │
│  - Collects metrics from ETS                           │
│  - Sends to Unleash server                             │
│  - Resets counters                                     │
└─────────────────────────────────────────────────────────┘
```

### Key Design Decisions

1. **Separation of Concerns**: Hot path (counter updates) is decoupled from cold path (sending metrics)

2. **Pre-registration**: Features are registered when loaded from server (`Unleash.Repo` calls
   `MetricsFast.register_features/1` after every features refresh, gated on `Config.fast_metrics()`),
   avoiding runtime counter creation

3. **Atomic Counters**: Uses Erlang's `:counters` module for lock-free concurrent updates

4. **Minimal Allocations**: Each `add_metric` call allocates only ~156 bytes vs 1.70 KB for GenServer

---

## Usage

### Default Configuration

`fast_metrics: true` is the **default** setting (`lib/unleash/config.ex`). No configuration change
is needed to use the optimized implementation; `Unleash.start/2` picks the child spec
(`Unleash.MetricsFast` vs `Unleash.Metrics`) accordingly.

### Disable Fast Metrics (if needed)

```elixir
# config/config.exs - to use the original GenServer-based implementation
config :unleash,
  fast_metrics: false
```

### Run Benchmarks

```bash
# Full comparison benchmark
mix benchmark.metrics --compare

# Quick benchmark
mix benchmark.metrics --compare --quick

# Stress test only
mix benchmark.metrics --stress

# Profile add_metric specifically
mix benchmark.metrics --add-metric --stress
```

> `MIX_ENV=dev` is required (the task calls `Mix.Task.run("app.start")`). `config/runtime.exs`
> unconditionally requires an `UNLEASH_AUTH_TOKEN` env var to boot in this environment — set it to
> any placeholder value when benchmarking locally, e.g. `UNLEASH_AUTH_TOKEN=dummy mix benchmark.metrics --compare`.
> No real Unleash server is contacted by the benchmark itself, so the value doesn't matter; you may
> see harmless `Failed to register unleash client` warnings in the log from the app's own background
> registration attempts against `config/dev.exs`'s `http://localhost:4242/api/`.

---

## Recommendations

| Traffic Level | Recommendation | Config |
|---------------|----------------|--------|
| Any | MetricsFast (default) | `fast_metrics: true` (default) |
| Legacy/compatibility | GenServer | `fast_metrics: false` |

### When to Use Default (MetricsFast)

- All new deployments (recommended)
- High-frequency feature flag checks (> 10K/s)
- Latency-sensitive applications
- Memory-constrained environments
- Applications with many concurrent requests

### When to Disable Fast Metrics

- If you experience issues with the new implementation
- For backward compatibility with custom metrics integrations
- When debugging metrics-related issues

---

## Files Changed (this benchmarking pass)

| File | Change |
|------|--------|
| `lib/mix/tasks/benchmark.metrics.ex` | Fixed `--compare` crash: the task assumed both `Unleash.Metrics` and `Unleash.MetricsFast` are started by the application, but `Unleash.start/2` only supervises one (chosen by `fast_metrics`). Now explicitly starts whichever of the two isn't already running, tolerating `{:already_started, _}`. |
| `BENCHMARK_REPORT.md` | Re-ran and refreshed all figures on current hardware/Elixir/OTP. |

Files from the original optimization work (unchanged by this pass, listed for reference):

| File | Change |
|------|--------|
| `lib/unleash/metrics_fast.ex` | Optimized metrics module |
| `lib/unleash/config.ex` | `fast_metrics` config option |
| `lib/unleash.ex` | Configurable metrics module selection |
| `lib/unleash/repo.ex` | Auto-registers features with MetricsFast |
| `mix.exs` | Benchee dependency |

---

## Conclusion

The optimized `MetricsFast` implementation provides **~100x better throughput** and **~150x lower
memory usage** compared to the default GenServer-based approach, consistent with the original
findings and reproduced independently on different hardware (Apple M2 Pro, Elixir 1.20.2,
Erlang/OTP 29). This makes the Unleash client suitable for high-performance, high-throughput
applications where feature flag checks occur at very high rates.

The optimization is backward-compatible and can be disabled via a simple configuration change
without any code modifications to existing applications.
