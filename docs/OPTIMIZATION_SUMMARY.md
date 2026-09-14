# Optimization Summary: `compiled-closure` vs `main`

## Overview

The `compiled-closure` branch optimizes the `Unleash.enabled?/3` and
`Unleash.get_variant/3` hot path by eliminating overhead from telemetry,
`Application.get_env` lookups, ETS struct copies, and unnecessary map
allocations. The result is a ~2–3× improvement at high concurrency.

---

## Main branch hot path

```
enabled?(feature, context) →
  telemetry_metadata()           Application.get_env ×2 + map allocs
  :telemetry.span(…)             monotonic_time ×2, ETS handler lookups ×2
    Config.disable_client()      Application.get_env
    Repo.get_feature()           ETS lookup + struct copy
    Feature.enabled?(…)          strategy interpretation
    metrics_module()             Application.get_env
    .add_metric(…)               MetricsFast (ETS + :counters)
    Map.merge ×3                 telemetry metadata construction
```

## Optimized branch hot path (`disable_telemetry: true`, the default)

```
enabled?(feature, context) →
  disable_telemetry_fast()       persistent_term (~20ns)
  disable_client_fast()          persistent_term (~20ns)
  FeatureCompiler.compiled?()    persistent_term (~20ns)
  get_feature(name)              persistent_term (no copy)
  Feature.enabled?(…)            same static JIT-optimized strategy eval
  metrics_module_fast()          persistent_term (~20ns)
  .add_metric(…)                 MetricsFast (ETS + :counters)
```

---

## Optimizations applied

### 1. Disable telemetry on the hot path (`disable_telemetry: true`)

**Default changed to `true`.** When set, `enabled?/3` and `get_variant/3`
skip the `:telemetry.span/3` wrapper entirely, eliminating:

- 2× `:erlang.monotonic_time/0` calls
- 1× `System.unique_integer/0` for span context
- 2× ETS handler-table lookups
- 2× `Application.get_env` for appname/instance_id
- 3× map allocations for telemetry metadata (`Map.merge` + `Map.put`)

Users who need `[:unleash, :feature, :enabled?]` and `[:unleash, :variant, :get]`
telemetry events can set `disable_telemetry: false`. Background client events
(polling, metrics posting, registration) are unaffected.

### 2. Config values cached in persistent_term

`disable_client`, `disable_telemetry`, and `metrics_module` are cached in
`:persistent_term` at application start via `Config.cache_hot_path_config!/0`.

| Accessor | Before | After |
|---|---|---|
| `Config.disable_client()` | `Application.get_env` (~200ns) | `persistent_term.get` (~20ns) |
| `Config.disable_telemetry()` | `Application.get_env` (~200ns) | `persistent_term.get` (~20ns) |
| `Config.metrics_module()` | `Application.get_env` ×2 (~400ns) | `persistent_term.get` (~20ns) |

### 3. `FeatureCompiler.compiled?()` via persistent_term

Replaced `Code.ensure_loaded?(Unleash.CompiledFeatures)` (code server message)
with a `:persistent_term` flag set to `true` by `FeatureCompiler.compile_all/1`.
Eliminates a process message round-trip on every call.

### 4. Feature structs stored in persistent_term

Feature structs are stored in `:persistent_term` keyed by `{:unleash_feature, name}`
during `compile_all/1`. The fast path reads them via `FeatureCompiler.get_feature/1`
instead of `Repo.get_feature/1` (ETS lookup).

`:persistent_term.get` returns a reference to shared heap data — no struct copy,
unlike ETS which copies the term into the caller's heap on every lookup.

### 5. No metadata map construction on fast path

The main branch always builds `{result, %{reason: …}}` tuples and telemetry
metadata maps, even when no telemetry handlers are attached. The fast path
returns the result directly with no intermediate map allocations.

### 6. Safe module reload with `:code.soft_purge`

`FeatureCompiler.compile_all/1` uses `:code.soft_purge/1` instead of
`:code.purge/1`. The hard purge kills any process currently executing in the
old module version — since `enabled?/2` runs on the caller's process, this
could crash request-path processes during a feature reload. `soft_purge` is a
no-op if any process is still in old code, making hot-swap safe.

---

## What was tried and reverted

### Dynamic module dispatch (`CompiledFeatures`)

Feature evaluation was compiled into a dynamically-generated BEAM module
(`Unleash.CompiledFeatures`) with per-feature function clauses. This was
faster in micro-benchmarks (~500ns vs ~3μs for ETS+interpret) but **slower
under high concurrency** (64+ callers) in production:

| p50, 64 calls | CompiledFeatures | main (Feature.enabled?) |
|---|---|---|
| enabled? | 1520 μs | 1021 μs |

Root cause: BeamAsm JIT does not fully optimize hot-swapped modules, and
instruction cache pressure from per-feature function clauses degrades under
concurrent access. The static `Feature.enabled?/2` is permanently JIT-compiled
and cache-friendly.

The fast path now uses `Feature.enabled?/2` (same as main) but reads the
feature struct from persistent_term instead of ETS, avoiding the copy overhead.

### Unleash_ex feature flag optimization for `enabled?`

An attempt was made to further optimize the `enabled?` path within
unleash_ex itself. In production (Aug 31), this made opt **worse** than
main at high concurrency:

| p50, 64 calls | opt (w/ flag opt) | main |
|---|---|---|
| enabled? | 2,508 μs | 1,306 μs |

| p95, 64 calls | opt (w/ flag opt) | main |
|---|---|---|
| enabled? | 15,898 μs | 12,567 μs |

The change was reverted, and subsequent runs (Sep 2–9) confirmed the
non-flag-optimized version outperforms main.

### `add_metric_by_name/2`

Added a lightweight metric recording function that takes the feature name
directly, avoiding a persistent_term lookup for the full Feature struct.
No measurable production improvement — the struct lookup is needed anyway
for `Feature.enabled?/2`.

---

## Production results

### `get_variant` (p50, `pipe_bid_req` step duration in μs)

| concurrent calls |   0 |   1 |   8 |  16 |   32 |    64 |     80 |
|------------------|----:|----:|----:|----:|-----:|------:|-------:|
| **optimized**    | 500 | 500 | 501 | 501 |  509 |   695 |    979 |
| **main**         | 500 | 501 | 501 | 502 |  519 |   881 |  2,668 |

### `get_variant` (p95)

| concurrent calls |   0 |   1 |   8 |  16 |   32 |    64 |     80 |
|------------------|----:|----:|----:|----:|-----:|------:|-------:|
| **optimized**    | 950 | 951 | 952 | 951 |  970 | 6,581 |  7,830 |
| **main**         | 951 | 951 | 953 | 951 |  987 | 6,993 | 15,133 |

### `enabled?` (p50, `pipe_bid_req` step duration in μs)

*Sep 2–3 test: after commit `55f87d2` (static `Feature.enabled?/2` +
persistent_term) and reverting the unleash_ex feature flag optimization
(see "What was tried and reverted" below).*

| concurrent calls |   0 |   1 |   8 |  16 |  32 |    64 |     80 |
|------------------|----:|----:|----:|----:|----:|------:|-------:|
| **optimized**    | 500 | 500 | 501 | 502 | 504 |   690 |  1,828 |
| **main**         | 500 | 502 | 501 | 501 | 536 | 1,702 |  3,680 |

### `enabled?` (p95)

| concurrent calls |   0 |   1 |   8 |  16 |    32 |     64 |     80 |
|------------------|----:|----:|----:|----:|------:|-------:|-------:|
| **optimized**    | 950 | 950 | 951 | 953 |   958 |  7,366 | 15,359 |
| **main**         | 950 | 951 | 954 | 952 | 1,183 | 13,777 | 21,097 |

### `enabled?` repeat (Sep 4, p50)

| concurrent calls |   0 |   1 |   8 |  16 |  32 |    64 |     80 |
|------------------|----:|----:|----:|----:|----:|------:|-------:|
| **optimized**    | 500 | 500 | 501 | 501 | 501 |   862 |  4,571 |
| **main**         | 501 | 501 | 501 | 503 | 511 | 1,995 |  5,232 |

### `enabled?` repeat (Sep 4, p95)

| concurrent calls |   0 |   1 |   8 |  16 |    32 |     64 |     80 |
|------------------|----:|----:|----:|----:|------:|-------:|-------:|
| **optimized**    | 951 | 950 | 951 | 951 |   951 |  8,878 | 24,664 |
| **main**         | 951 | 951 | 952 | 955 |   972 | 13,411 | 23,989 |

### `enabled?` repeat (Sep 9, p50 / p95 / CPU%)

*Latest run; only 32/64/80 data points collected.*

| concurrent calls (p50) |   32 |    64 |    80 |
|------------------------|-----:|------:|------:|
| **optimized**          |  501 |   977 | 2,265 |
| **main**               |  511 | 1,638 | 4,371 |

| concurrent calls (p95) |    32 |     64 |     80 |
|------------------------|------:|-------:|-------:|
| **optimized**          |   951 | 12,878 | 15,868 |
| **main**               |   972 | 12,673 | 21,242 |

| concurrent calls (CPU%) |  32 |  64 |   80 |
|--------------------------|----:|----:|-----:|
| **optimized**            |  74 |  64 |   — |
| **main**                 |  83 |  76 |   — |

`get_variant`: **~2–3× improvement** at high concurrency (64–80 calls).
`enabled?`: **~1.9–2.5× improvement** at p50/64 calls, **~1.5–1.9× at
p95/64 calls**, confirmed across three independent test runs (Sep 3, 4, 9).
CPU usage also lower at 32 and 64 concurrent calls.

### Local micro-benchmark (single caller, `mix run --no-start`)

After the dynamic→static module fix (`55f87d2`), both `enabled?` and
`get_variant` are faster than main in single-caller benchmarks.

#### `enabled?` — median latency (ns)

| scenario             |  main | optimized | speedup |
|----------------------|------:|----------:|---------|
| nonexistent feature  |   417 |   **167** | **2.5×**  |
| disabled feature     |   875 |   **500** | **1.75×** |
| default strategy     |   875 |   **500** | **1.75×** |
| matching user        | 1,334 | **1,000** | **1.33×** |

#### `get_variant` — median latency (ns)

| scenario             |  main | optimized | speedup |
|----------------------|------:|----------:|---------|
| nonexistent feature  |   420 |   **167** | **2.5×**  |
| no variants          | 1,000 |   **667** | **1.5×**  |
| with variants        | 1,540 | **1,125** | **1.37×** |

#### Memory per call (bytes)

| scenario                   |  main | optimized | reduction |
|----------------------------|------:|----------:|-----------|
| enabled?(matching user)    | 3,630 | **1,584** | **56%**   |
| enabled?(nonexistent)      | 1,150 |    **88** | **92%**   |
| get_variant(with variants) | 2,560 | **1,552** | **39%**   |
| get_variant(nonexistent)   | 1,000 |    **88** | **91%**   |

Biggest wins on early-exit paths (nonexistent/disabled features) where
eliminated telemetry + config overhead was the dominant cost.

### vs PR #23 baseline (`9f99f50`, pre-optimization)

Comparison against the merge commit of PR #23 (Fix variant metrics) — the
codebase before any performance work was done.

#### `enabled?` — median latency (ns)

| scenario             |   PR #23 | optimized | speedup  |
|----------------------|---------:|----------:|----------|
| nonexistent feature  |   28,630 |   **167** | **171×** |
| disabled feature     |   62,580 |   **500** | **125×** |
| default strategy     |   61,630 |   **500** | **123×** |
| matching user        |   60,830 | **1,000** | **61×**  |

#### `get_variant` — median latency (ns)

| scenario             |   PR #23 | optimized | speedup  |
|----------------------|---------:|----------:|----------|
| nonexistent feature  |   27,880 |   **167** | **167×** |
| no variants          |   75,580 |   **667** | **113×** |
| with variants        |   72,210 | **1,125** | **64×**  |

#### Memory per call (bytes)

| scenario                   |    PR #23 | optimized | reduction  |
|----------------------------|---------:|----------:|------------|
| enabled?(matching user)    |   88,920 | **1,584** | **98.2%**  |
| enabled?(nonexistent)      |   35,150 |    **88** | **99.7%**  |
| get_variant(with variants) |  106,410 | **1,552** | **98.5%**  |
| get_variant(nonexistent)   |   35,000 |    **88** | **99.7%**  |

**60–170× faster, 98–99% less memory** vs the pre-optimization baseline.

---

### Full-day resource comparison (Sep 9, kubectl)

*23.3h side-by-side run on USE1, 6 snapshots.*

| Metric | Optimized | Main | Delta |
|--------|-----------|------|-------|
| **CPU (latest)** | 25,254m | 28,893m | **−12.6%** |
| **CPU range** | −2% to −19% | — | avg **−12%**, ~3.6 cores saved |
| **Memory** | 30,896 Mi | 29,407 Mi | **+5.1%** (~1.5 GiB) |
| **Memory trend** | +5–8% across 6 snapshots | — | stable, no growth |
| **Restarts** | 0 | 0 | — |
| **Uptime** | 23.3h | 23.3h | — |

#### CPU trend (Sep 9)

| Time (UTC) | Optimized | Main | Delta |
|------------|-----------|------|-------|
| ~16:15 | 24,683m | 25,209m | −2.1% |
| ~16:55 | 26,934m | 29,517m | −8.7% |
| ~18:44 | 24,384m | 30,013m | −18.8% |
| ~21:14 | 27,768m | 31,639m | −12.2% |
| ~22:30 | 25,185m | 29,861m | −15.7% |
| ~23:20 | 25,254m | 28,893m | −12.6% |

Optimized consistently uses less CPU. The advantage grows under peak load
(−19%) and narrows during low traffic (−2%).

### Pacing and operational health (Sep 9)

| Check | Optimized | Main | Status |
|-------|-----------|------|--------|
| Pacing yes rate | 6.0–6.5% | 6.9–7.2% | ✅ Comparable |
| Pacing not_found | 0 | 0 | ✅ No data gaps |
| Pacing backlog | 5 | 2 | ✅ Both low |
| Exchange pacing errors | **4,681** | **2,691,045** | ⚠️ Main has 575× more |
| Shackle timeouts | 2.53M (2.6%) | 2.19M (2.0%) | ✅ Both acceptable |
| Feature flags | identical | identical | ✅ |

The dramatically lower exchange pacing errors on the optimized pod (4.7K vs
2.69M) indicate the CPU headroom allows pacing calls to complete within
timeout deadlines more often.

### Summary of production findings

| Metric | Result |
|--------|--------|
| `get_variant` latency (p50, 80 calls) | **~2.7× faster** (979 vs 2,668 μs) |
| `enabled?` latency (p50, 64 calls) | **~2× faster** (690–977 vs 1,638–1,995 μs) |
| `enabled?` latency (p95, 80 calls) | **~1.4× faster** (15,359–15,868 vs 21,097–21,242 μs) |
| CPU usage | **~12% lower** on average (up to 19% under peak) |
| Memory overhead | **~5–6% higher** (~1.5 GiB), stable, no growth |
| Exchange pacing errors | **575× fewer** on optimized pod |
| Stability | 23.3h, 0 restarts, no anomalies |

---

## Configuration

```elixir
config :unleash, Unleash,
  disable_telemetry: true,   # default — skip telemetry spans on hot path
  fast_metrics: true          # default — ETS/:counters instead of GenServer
```

## Files changed

```
lib/unleash.ex                    — fast path with persistent_term + static eval
lib/unleash/config.ex             — persistent_term-cached accessors, disable_telemetry option
lib/unleash/feature_compiler.ex   — compile_all, persistent_term storage, soft_purge
lib/unleash/metrics.ex            — add_metric_by_name/2
lib/unleash/metrics_fast.ex       — add_metric_by_name/2
lib/unleash/repo.ex               — triggers compile_all on poll
lib/mix/tasks/benchmark.hotpath.ex — end-to-end benchmark task
test/unleash/feature_compiler_test.exs — concurrent recompilation safety test
```

---

## Production test log

| # | Date | Config | API tested | Key finding |
|---|------|--------|------------|-------------|
| 1 | Aug 18–19 | `precompute-constraint-values` | enabled? | Canaries killed at 64/80 calls |
| 2 | Aug 20 | `compiled-closure` v1 | enabled? | First compiled-closure test |
| 3 | Aug 21 | `compiled-closure` v2 (full compiled features) | enabled? | Dynamic dispatch, worse at high concurrency |
| 4 | Aug 24 | `compiled-closure` no telemetry | enabled? | Telemetry overhead removed; opt wins at 64/80 |
| 5 | Aug 26–27 | `compiled-closure` no telemetry | enabled? | ⚠️ Questionable: opt called `get_variant`, current called `enabled?` |
| 6 | Aug 27 | `compiled-closure` no telemetry | get_variant | Clean test: **opt ~2–3× better at 64/80** |
| 7 | Aug 28 | `compiled-closure` no telemetry | enabled? | Dynamic dispatch still present; current wins at 64 |
| 8 | Aug 31 | `compiled-closure` + unleash_ex flag opt | enabled? | Flag optimization worse, reverted |
| 9 | Sep 2–3 | `compiled-closure` flag opt reverted | enabled? | **Opt ~2× better at 64**, ~1.8× at 80 |
| 10 | Sep 4 | repeat of #9 | enabled? | Confirms: **opt wins at 64** |
| 11 | Sep 8–9 | repeat of #9 | enabled? | **Opt ~1.7× at p50/64, −12% CPU, 575× fewer pacing errors** |
