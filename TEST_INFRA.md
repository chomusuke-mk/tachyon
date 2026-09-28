# Tachyon Linux Test & Performance Benchmark Infrastructure

This document specifies the end-to-end testing, static validation, and automated performance benchmarking infrastructure for **Tachyon** on Linux.

---

## 1. Architectural Overview

Tachyon's testing infrastructure enforces strict performance limits, memory budgets, zero-regression architectural contracts, and internationalization standards across four isolated tiers:

```
┌────────────────────────────────────────────────────────────────────────┐
│                   Tier 4: Release & Real-World E2E                    │
│      (Automated Linux Profiler, Full Playback Cycle, Window Resize)     │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼────────────────────────────────────┐
│              Tier 3: Cross-Feature Interactions & Invariants           │
│   (Lyrics Visibility Gating, Prefs Throttling, Crossfade Concurrency)  │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼────────────────────────────────────┐
│               Tier 2: Boundary, Stress & Resource Capping              │
│       (Rapid Skip Bursts, ImageCache Eviction, SQLite Single-Writer)   │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼────────────────────────────────────┐
│                Tier 1: Isolated Unit & Widget Verification             │
│   (AudioEngineService Dual-Player, WaveformSlider, NowPlayingScreen,   │
│                 AST i18n & Zero Hardcoded Strings Linter)              │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. 4-Tier Test Suite Specification

### Tier 1: Isolated Unit & Widget Verification
Guarantees component-level algorithmic correctness, boundary adherence, and widget composition isolation.
- **AudioEngineService Dual-Player Suite (`test/core/services/audio_engine_service_test.dart`)**:
  - Validates coordination between `Player A` and `Player B`.
  - Verifies Equal-Power volume curve formula ($V_A = \cos(\theta), V_B = \sin(\theta)$) and Linear curve transitions at 25ms ticker intervals.
  - Verifies player role swapping: outgoing player stops, incoming player assumes active role with full master volume.
  - Verifies that seeking or track jumping during an active crossfade immediately aborts the transition, silences the standby player, and restores master volume.
  - Verifies gapless transition behavior when crossfade duration is 0s.
- **WaveformSlider Isolated Widget Suite (`test/features/playback/waveform_slider_test.dart`)**:
  - Tests custom painter logic (`_WaveformSliderPainter` with 55 precomputed bars and playhead thumb circle).
  - Validates `shouldRepaint` behavior (quantized updates, no unnecessary repaints when progress is identical).
  - Validates optimistic local drag gestures: clamps drag position between `0.0` and `duration`, suppresses intermediate seeks, and dispatches `onSeek` only upon release.
  - Tests tap-to-seek and duration formatting (elapsed, remaining, toggle between total and remaining).
  - Verifies repaint boundary isolation capability.
- **NowPlayingScreen Suite (`test/features/playback/now_playing_screen_test.dart`)**:
  - Tests widget tree composition: empty queue state vs. active track layout.
  - Tests responsive reflow: horizontal split layout on wide viewports ($\ge 590$ px) vs. vertical stacked layout on narrow viewports ($< 590$ px).
  - Tests lyrics view toggle (`_showLyrics`) and queue view toggle (`_showQueue`).
  - Asserts repaint boundary presence around visual subcomponents.
- **AST i18n & Zero Hardcoded Strings Analyzer (`test/ast_i18n_test.dart`)**:
  - Scans UI Dart source files in `lib/` to assert zero hardcoded string literals are displayed in UI widgets (`Text`, `SelectableText`).
  - Verifies 100% bidirectional key symmetry between `i18n/en.jsonc` and `i18n/es.jsonc`.
  - Verifies that all JSONC keys have corresponding getters in `AppStringKey`.

### Tier 2: Boundary, Stress & Resource Capping
Validates resilience under resource constraints, rapid event bursts, and database concurrency.
- **Crossfade Rapid Skip Bursts (`test/features/playback/challenger_m3_2_skipping_stress_test.dart`)**:
  - Simulates 50+ rapid track transitions within seconds while crossfade tickers are running.
  - Asserts zero leaked timers, zero unhandled player exceptions, and clean standby player cleanup.
- **SQLite Concurrency & Single-Writer Isolation (`test/core/database/concurrency_test.dart`)**:
  - Concurrently issues 100 library read queries while a background worker executes 50 batch track writes.
  - Asserts zero `database is locked` errors and guarantees ACID consistency.
- **ImageCache & Memory Eviction**:
  - Asserts `PaintingBinding.instance.imageCache` constraints (`maximumSize: 60`, `maximumSizeBytes: 15MB`).

### Tier 3: Cross-Feature Interactions & Render Tree Gating
Enforces system-wide invariant contracts across interconnected modules.
- **Lyrics Visibility Gating Invariants (`test/features/playback/lyrics_visibility_gating_adversarial_test.dart`)**:
  - Enforces that remote APIs (`lrclib.net`, `lyrics.ovh`) receive **zero network requests** when audio is playing in standard Play View (`_showLyrics == false`).
  - Verifies requests fire only when `_showLyrics == true` and `LyricsView` mounts.
- **SharedPreferences Disk Write Throttling**:
  - Verifies that position ticks do not cause continuous synchronous disk writes, throttling `setLastPlayed` to at most once every 5–10 seconds.
- **Lyrics Rate Limiting & Cooldowns (`test/core/network/lyrics_rate_limiter_test.dart`)**:
  - Enforces minimum 500ms request spacing for `lrclib.net`.
  - Verifies HTTP 429 countdown banner for $\le 10$s cooldowns, and automatic fallback to `lyrics.ovh` for $> 10$s cooldowns.

### Tier 4: Real-World Scenarios & Release Benchmarks
Measures actual runtime metrics on native Linux binaries.
- **Launch to Steady-State Idle**:
  - Measures memory resident set size (RSS) and proportional set size (PSS) after startup stabilization.
- **Continuous Playback Load**:
  - Measures CPU% and GPU% during 30s audio playback with UI visible.
- **Interactive Window Resizing**:
  - Stress tests window resize events to verify zero black frames and smooth GTK container reflow.

---

## 3. Automated Linux Benchmark Harness (`benchmark/linux_benchmark.py`)

A zero-dependency Python 3 profiler measuring native kernel `/proc` metrics and GPU hardware counters.

### Measured Metrics
| Metric | Source | Description | Target Threshold |
| :--- | :--- | :--- | :--- |
| **VmRSS** | `/proc/<pid>/status` | Total resident physical memory | $\le 50$ MB idle, $\le 75$ MB playback |
| **RssAnon** | `/proc/<pid>/status` | Anonymous heap memory (Dart VM & app allocations) | $\le 30$ MB idle |
| **RssFile** | `/proc/<pid>/status` | File-backed mapped memory (libraries, fonts, assets) | Reference |
| **Pss** | `/proc/<pid>/smaps_rollup` | Proportional Set Size (true shared-memory footprint) | $\le 65$ MB idle |
| **Private_Dirty** | `/proc/<pid>/smaps_rollup` | Unpageable memory exclusive to the process | Reference |
| **CPU%** | `/proc/<pid>/stat` | Single-core normalized CPU utilization | $< 2.0\%$ |
| **GPU%** | `nvidia-smi` / DRM sysfs | GPU compute / shader utilization | $< 5.0\%$ |

### Execution Commands
```bash
# Run benchmark in idle mode (default: 10s)
python3 benchmark/linux_benchmark.py --mode idle --duration 10

# Run benchmark in playback mode with active audio
python3 benchmark/linux_benchmark.py --mode playback --duration 20

# Run benchmark in resize mode under X11/Xwayland
python3 benchmark/linux_benchmark.py --mode resize --duration 15

# Export benchmark results to JSON
python3 benchmark/linux_benchmark.py --mode idle --duration 10 --output benchmark_report.json
```

---

## 4. Acceptance Criteria & Performance Targets

1. **Memory Budget (Linux Release Mode)**:
   - Idle State: VmRSS $\le 50$ MB (or PSS $\le 65$ MB on systems with proprietary graphics drivers).
   - Active Playback: VmRSS $\le 75$ MB steady-state.
2. **CPU & GPU Utilization**:
   - Audio Playback with UI visible: Single-core CPU $< 2.0\%$, GPU SM $< 5.0\%$.
3. **Window Resizing**:
   - Zero black flickers or frame drops during GTK window resize.
4. **Code Quality & Regressions**:
   - `dart analyze` reports **0 errors, 0 warnings, 0 lints**.
   - `flutter test` reports **100% pass rate** across all unit, widget, and E2E suites.
   - Zero hardcoded user-facing strings in UI widgets.

---

## 5. Verification Commands

```bash
# 1. Run static analysis
dart analyze

# 2. Run the entire test suite
flutter test

# 3. Run individual tier test suites
flutter test test/core/services/audio_engine_service_test.dart
flutter test test/features/playback/waveform_slider_test.dart
flutter test test/features/playback/now_playing_screen_test.dart
flutter test test/ast_i18n_test.dart
flutter test test/core/database/concurrency_test.dart

# 4. Compile release binary and run benchmark
flutter build linux --release
python3 benchmark/linux_benchmark.py --mode idle --duration 10
```
