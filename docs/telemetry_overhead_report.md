# Telemetry Overhead Report

**Date:** 2026-08-24  
**Branch:** `compiled-closure`  
**Scope:** `Unleash.enabled?/3` and `Unleash.get_variant/3` hot path

---

## Summary

With compiled strategy evaluation and `MetricsFast`, the `:telemetry.span/3` wrapper is the **single largest remaining cost** on the request path — accounting for an estimated **40–70%** of wall time when no handlers are attached.

---

## Hot-path breakdown

### What `:telemetry.span/3` does per call

1. Builds `start_metadata` via `Unleash.Client.telemetry_metadata/1` → `Config.telemetry_metadata/0` — two `Map.merge` allocations plus `Application.get_env` lookups for `appname` and `instance_id`.
2. Calls `:erlang.monotonic_time/0` (span start).
3. Generates a span context ID via `System.unique_integer/0`.
4. Performs an ETS handler-table lookup for the `:start` event (no-op if no handlers).
5. Executes the wrapped function (the actual evaluation).
6. Calls `:erlang.monotonic_time/0` again (span stop).
7. Performs a second ETS handler-table lookup for the `:stop` event.
8. Builds result metadata — another `Map.merge` + `Map.put`.

If handlers **are** attached, they run synchronously inside steps 4/7.

### Cost table

| Component | Approx. cost | Location |
|-----------|-------------|----------|
| Compiled strategy eval | ~50–150 ns | `Unleash.CompiledFeatures.enabled?/2` |
| Feature lookup | ~20–50 ns | `:persistent_term.get/2` in `FeatureCompiler.get_feature/1` |
| `MetricsFast.add_metric` | ~70–100 ns | ETS lookup + `:counters.add/3` |
| **Telemetry span (no handlers)** | **~500–2000 ns** | `:telemetry.span/3` in `lib/unleash.ex` |
| `Metrics.add_metric` (GenServer) | ~22 µs | `GenServer.cast/2` (message copy) |

### Variant path (`get_variant/3`)

Identical telemetry structure. Adds `Variant.select_variant/2` (weight/override logic) which is pure computation — roughly comparable to strategy eval cost.

---

## Percentage estimates

### Configuration: `fast_metrics: true` + compiled closures

| | Cost | % of total |
|---|---|---|
| Strategy eval + persistent_term + counter | ~200–300 ns | ~30–60% |
| **Telemetry span** | **~500–2000 ns** | **~40–70%** |
| **Total per call** | **~1–2.5 µs** | |

### Configuration: default GenServer metrics

| | Cost | % of total |
|---|---|---|
| Strategy eval + persistent_term | ~100–200 ns | <1% |
| Telemetry span | ~500–2000 ns | ~5–10% |
| GenServer.cast (metrics) | ~22 µs | ~85–90% |
| **Total per call** | **~22–25 µs** | |

---

## Where the telemetry cost lives in code

```
lib/unleash.ex:96-113   — enabled?/3 telemetry.span
lib/unleash.ex:163-174  — get_variant/3 telemetry.span
lib/unleash/client.ex:170-171 — telemetry_metadata/1 (map allocation)
lib/unleash/config.ex:123     — telemetry_metadata/0 (Application.get_env × 2)
```

---

## Possible optimisations

| Option | Effort | Savings |
|--------|--------|---------|
| Compile-time flag to elide telemetry spans entirely | Low | ~50% latency reduction on fast path |
| Cache `appname`/`instance_id` in persistent_term instead of `Application.get_env` per call | Low | ~100–200 ns per call |
| Replace `:telemetry.span` with bare `:telemetry.execute` (skip monotonic time if unused) | Medium | ~200–500 ns per call |
| Make telemetry opt-in at compile time (dead-code eliminate the span) | Low | Full span cost eliminated |

---

## Conclusion

For users running the optimised path (`fast_metrics: true` + compiled closures), telemetry is no longer "free instrumentation" — it's the dominant cost centre. The actual feature evaluation has been optimised to hundreds of nanoseconds, but the telemetry bookkeeping adds ~0.5–2 µs of overhead that cannot be reduced without changing the instrumentation approach.

For users on the default GenServer metrics path, telemetry overhead is negligible (~5–10%) since `GenServer.cast` dominates at ~22 µs.
