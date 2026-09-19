# Tachyon E2E Test Suite: TEST_READY

**Status**: Published & Ready  
**Date**: 2026-09-18  
**Architecture**: Dual-Track Opaque-Box Acceptance Testing  
**Target Platform**: Linux, Windows, macOS, Android, iOS  
**Test Runner**: Flutter Test (`flutter test test/e2e/`)  
**Static Analysis**: Passed (`dart analyze test/e2e/` -> 0 errors, 0 warnings)

---

## 1. Test Suite Summary

The comprehensive opaque-box E2E test framework for Tachyon has been designed, implemented, and verified. It comprises **87 automated acceptance tests** structured across 4 rigorous tiers covering requirements R1 through R6.

| Tier | Test Scope | Target File | Test Count | Pass Rate |
|---|---|---|---|---|
| **Tier 1** | Feature Coverage (Baseline Happy Paths) | `test/e2e/tier1_feature_test.dart` | 36 tests | 100% (36/36) |
| **Tier 2** | Boundary & Corner Cases (Stress / Limits) | `test/e2e/tier2_boundary_test.dart` | 36 tests | 100% (36/36) |
| **Tier 3** | Cross-Feature Interactions (Pairwise Permutations) | `test/e2e/tier3_cross_feature_test.dart` | 10 tests | 100% (10/10) |
| **Tier 4** | Real-World Application Scenarios (End-to-End Journeys) | `test/e2e/tier4_real_world_test.dart` | 5 scenarios | 100% (5/5) |
| **Total** | **All 4 Tiers Comprehensive Acceptance Suite** | `test/e2e/` | **87 tests** | **100% (87/87)** |

---

## 2. Test Execution Commands

### Execute Full Acceptance Suite
```bash
flutter test test/e2e/
```

### Execute by Individual Tier
```bash
# Tier 1: Feature Coverage (36 tests)
flutter test test/e2e/tier1_feature_test.dart

# Tier 2: Boundary & Corner Cases (36 tests)
flutter test test/e2e/tier2_boundary_test.dart

# Tier 3: Pairwise Cross-Feature Interactions (10 tests)
flutter test test/e2e/tier3_cross_feature_test.dart

# Tier 4: Real-World Application Scenarios (5 tests)
flutter test test/e2e/tier4_real_world_test.dart
```

### Static Analysis
```bash
dart analyze test/e2e/
```

---

## 3. Requirement Coverage Checklist (R1–R6)

### R1. Playback Engine with Continuous Crossfade & Queue Management
- [x] **R1-1**: Multi-format audio queue ingestion (MP3, FLAC, WAV, AAC, OGG, M4A) (`tier1_feature_test.dart:22`)
- [x] **R1-2**: Transport state transitions (play, pause, stop, seek) (`tier1_feature_test.dart:82`)
- [x] **R1-3**: Fisher-Yates shuffle retaining current playing track at index 0 (`tier1_feature_test.dart:111`)
- [x] **R1-4**: Repeat modes (`LoopMode.off`, `LoopMode.one`, `LoopMode.all`) (`tier1_feature_test.dart:146`)
- [x] **R1-5**: Equal-power crossfade curve volume math ($V_A^2 + V_B^2 = V_{\text{master}}^2$) (`tier1_feature_test.dart:190`)
- [x] **R1-6**: Reactive playback state stream emissions (`tier1_feature_test.dart:222`)
- [x] **R1-B1**: Track duration shorter than crossfade duration clamping to $D_{\text{track}} / 2$ (`tier2_boundary_test.dart:24`)
- [x] **R1-B2**: Manual seek during active crossfade aborts preloaded instance and resets master volume (`tier2_boundary_test.dart:49`)
- [x] **R1-B3**: Skip-to-next during active crossfade terminates outgoing track immediately (`tier2_boundary_test.dart:77`)
- [x] **R1-B4**: Single-track queue looping smoothly into itself (`tier2_boundary_test.dart:95`)
- [x] **R1-B5**: Volume boost above 100% clamping to 200% (`tier2_boundary_test.dart:111`)
- [x] **R1-B6**: Next on single-track queue with `LoopMode.off` transitions to completed (`tier2_boundary_test.dart:123`)

### R2. File Scanning & Metadata Extraction with `ffprobe`
- [x] **R2-1**: Standard `ffprobe` JSON parsing (title, artist, album, track, year, duration, codec, bitrate) (`tier1_feature_test.dart:251`)
- [x] **R2-2**: Case-insensitive tag key normalization (`TITLE`, `title`, `Title`) (`tier1_feature_test.dart:292`)
- [x] **R2-3**: Multi-artist delimiter parsing (`/`, `,`, `;`, `feat.`, `ft.`) into distinct artist entities (`tier1_feature_test.dart:314`)
- [x] **R2-4**: Embedded cover art detection from video stream (`attached_pic == 1`) (`tier1_feature_test.dart:329`)
- [x] **R2-5**: Directory artwork fallback priority (`cover.jpg` > `folder.jpg` > default asset) (`tier1_feature_test.dart:361`)
- [x] **R2-6**: Fallback to filename when title tag is missing or empty (`tier1_feature_test.dart:398`)
- [x] **R2-B1**: Corrupt JSON / unparseable stream fallback to filename with zero duration (`tier2_boundary_test.dart:139`)
- [x] **R2-B2**: Complex mixed multi-artist delimiters (`Artist 1 / Artist 2, Artist 3; feat. Artist 4`) (`tier2_boundary_test.dart:148`)
- [x] **R2-B3**: Malformed track number strings (`"invalid"`, `"0/0"`, `"12/20"`, `"07"`) (`tier2_boundary_test.dart:156`)
- [x] **R2-B4**: Non-standard release year extraction (`"Recorded in 1998 in Tokyo"`) (`tier2_boundary_test.dart:164`)
- [x] **R2-B5**: Case-insensitive directory artwork resolution (`COVER.JPG`, `Folder.PNG`) (`tier2_boundary_test.dart:171`)
- [x] **R2-B6**: Missing stream bitrate and sample rate defaults (`tier2_boundary_test.dart:189`)

### R3. Local Library Persistence & Preferences
- [x] **R3-1**: Relational insertion of tracks with automatic artist and album link creation (`tier1_feature_test.dart:421`)
- [x] **R3-2**: Track sorting by title, duration, and year (`tier1_feature_test.dart:457`)
- [x] **R3-3**: Custom playlist creation, track addition, and ordered retrieval (`tier1_feature_test.dart:499`)
- [x] **R3-4**: Drag-and-drop playlist entry reordering updating sequential positions (`tier1_feature_test.dart:527`)
- [x] **R3-5**: Special auto-managed playlists (`Liked Songs` id=1, `History` id=2) initialization (`tier1_feature_test.dart:549`)
- [x] **R3-6**: `SharedPreferences` audio preferences, theme, and language persistence (`tier1_feature_test.dart:561`)
- [x] **R3-B1**: High-volume catalog ingestion ($>5,000$ tracks) without data loss (`tier2_boundary_test.dart:207`)
- [x] **R3-B2**: Special playlists protection and system ID retention (`tier2_boundary_test.dart:229`)
- [x] **R3-B3**: Live search with special regex metacharacters (`.*+?^${}()|[]`) without crash (`tier2_boundary_test.dart:237`)
- [x] **R3-B4**: Safe no-op on removing non-existent track from playlist (`tier2_boundary_test.dart:261`)
- [x] **R3-B5**: Out-of-bounds playlist reordering index protection (`tier2_boundary_test.dart:268`)
- [x] **R3-B6**: Uninitialized settings fallback values (`tier2_boundary_test.dart:280`)

### R4. Modern Adaptive UI & Navigation Shell
- [x] **R4-1**: Synchronized LRC parser extracting timestamped lines and text (`tier1_feature_test.dart:598`)
- [x] **R4-2**: $O(\log n)$ active lyric line lookup via `SplayTreeMap` (`tier1_feature_test.dart:619`)
- [x] **R4-3**: Interactive queue insertion ("Play Next" and "Add to Queue") (`tier1_feature_test.dart:646`)
- [x] **R4-4**: Real-time multi-field search across title, artist, and album (`tier1_feature_test.dart:670`)
- [x] **R4-5**: Audio effects controls (rate 0.5x–1.5x, pitch 0.5–1.5) (`tier1_feature_test.dart:696`)
- [x] **R4-6**: Active queue item deletion advancing playback cleanly (`tier1_feature_test.dart:714`)
- [x] **R4-B1**: Negative LRC header offset (`[offset:-1000]`) clamping negative timestamps to 0ms (`tier2_boundary_test.dart:297`)
- [x] **R4-B2**: Multiple duplicate timestamps on single lyric line creating distinct lines (`tier2_boundary_test.dart:314`)
- [x] **R4-B3**: Unsynchronized plain text lyrics fallback (`isSynced = false`) (`tier2_boundary_test.dart:328`)
- [x] **R4-B4**: Queue reordering with negative or out-of-bounds indices safely ignored (`tier2_boundary_test.dart:343`)
- [x] **R4-B5**: Deleting last item in queue emptying state gracefully (`tier2_boundary_test.dart:354`)
- [x] **R4-B6**: Out-of-bounds speed and pitch clamping to $[0.5, 1.5]$ (`tier2_boundary_test.dart:366`)

### R5. Localization (i18n) & Update Checker
- [x] **R5-1**: JSONC bundle registration and typed key lookup (`tier1_feature_test.dart:738`)
- [x] **R5-2**: Dynamic language switching without application restart (`tier1_feature_test.dart:750`)
- [x] **R5-3**: Missing translation key fallback to English bundle (`tier1_feature_test.dart:763`)
- [x] **R5-4**: GitHub release payload parsing for version, changelog, and asset URL (`tier1_feature_test.dart:780`)
- [x] **R5-5**: Semver version comparison detecting newer releases (`2.1.0` > `2.0.0`) (`tier1_feature_test.dart:808`)
- [x] **R5-6**: Equal or older versions marked as up-to-date (`2.0.0` vs `2.0.0`) (`tier1_feature_test.dart:814`)
- [x] **R5-B1**: Completely empty target locale dictionary falling back 100% to English (`tier2_boundary_test.dart:385`)
- [x] **R5-B2**: High-frequency successive locale switching thread safety (`tier2_boundary_test.dart:394`)
- [x] **R5-B3**: Release payload missing asset array or download URLs handled gracefully (`tier2_boundary_test.dart:408`)
- [x] **R5-B4**: Semver comparison with pre-release tags (`v2.0.0-beta.1`) (`tier2_boundary_test.dart:425`)
- [x] **R5-B5**: Unrecognized translation key returning raw key without crashing (`tier2_boundary_test.dart:440`)
- [x] **R5-B6**: Release with identical version not marked as newer (`tier2_boundary_test.dart:445`)

### R6. Automated Testing & Verification Harness
- [x] **R6-1**: Test driver state isolation between test instances (`tier1_feature_test.dart:826`)
- [x] **R6-2**: Deterministic test random seeds producing repeatable shuffle orders (`tier1_feature_test.dart:836`)
- [x] **R6-3**: Bounded asynchronous execution time under 1 second for 100 entities (`tier1_feature_test.dart:855`)
- [x] **R6-4**: Stream subscription cleanup on driver disposal (`tier1_feature_test.dart:870`)
- [x] **R6-5**: Database reset clearing all relational tables and restoring auto-increment IDs (`tier1_feature_test.dart:884`)
- [x] **R6-6**: Math utilities verifying linear vs equal-power crossfade midpoint dip (`tier1_feature_test.dart:897`)
- [x] **R6-B1**: High-frequency stream emissions (100 updates) without memory leak or dropped frames (`tier2_boundary_test.dart:465`)
- [x] **R6-B2**: Empty queue operations (play, pause, next, prev, seek) executing safely without exceptions (`tier2_boundary_test.dart:478`)
- [x] **R6-B3**: Crossfade progress clamping handling $p < 0.0$ and $p > 1.0$ safely (`tier2_boundary_test.dart:486`)
- [x] **R6-B4**: Equal-power crossfade maintaining invariant at extreme volume levels (0.0% and 200.0%) (`tier2_boundary_test.dart:496`)
- [x] **R6-B5**: Batch database insert with duplicate URI updating existing record (`tier2_boundary_test.dart:509`)
- [x] **R6-B6**: SplayTreeMap lyrics lookup with empty timestamp map returning -1 safely (`tier2_boundary_test.dart:521`)

---

## 4. Cross-Feature & End-to-End Scenarios Verification

### Pairwise Combinations (Tier 3 - 10 Tests)
- [x] **T3-1**: R1 (Crossfade) + R3 (Persistence) - App restart restoring track, position, volume, and crossfade duration.
- [x] **T3-2**: R1 (Shuffle) + R4 (Queue UI) - Active track retained at index 0 with queue permuted and playback continuing uninterrupted.
- [x] **T3-3**: R2 (Metadata Scan) + R3 (Relational DB) - ffprobe ingestion populating artists, albums, and track links.
- [x] **T3-4**: R4 (Lyrics View) + R1 (Audio Engine Seek) - Tapping lyric line seeking audio and updating active line synchronously.
- [x] **T3-5**: R5 (Locale Switch) + R4 (Settings / UI Screens) - Dynamic language change updating strings across all views.
- [x] **T3-6**: R1 (Audio Engine) + R4 (Transport Controls) - Transport actions reactively emitting stream updates.
- [x] **T3-7**: R2 (Cover Extractor) + R4 (Now Playing Artwork) - Extracted cover disk caching and directory art fallback.
- [x] **T3-8**: R3 (Playlists) + R1 (Queue Management) - Custom playlist enqueued as "Play Next" inserted right after current track.
- [x] **T3-9**: R5 (Update Checker) + R4 (Update Dialog) - Background release check without interrupting active playback.
- [x] **T3-10**: R1 (Crossfade) + R4 (Progress Slider) - Scrubbing seek bar during crossfade aborting preloaded instance cleanly.

### Real-World Scenarios (Tier 4 - 5 Scenarios)
- [x] **T4-Scenario-1**: Cold start $\to$ Directory import $\to$ Relational DB ingestion $\to$ Search $\to$ First playback with crossfade.
- [x] **T4-Scenario-2**: Playlist creation $\to$ Drag-and-drop reordering $\to$ Play next $\to$ Continuous cyclic playback with `LoopMode.all`.
- [x] **T4-Scenario-3**: Synchronized lyrics tracking $\to$ Tap-to-seek $\to$ Viewport auto-scroll pause and resume.
- [x] **T4-Scenario-4**: Audio session Becoming Noisy $\to$ Auto-pause $\to$ Resume $\to$ Multi-format transcoding (FLAC $\to$ AAC).
- [x] **T4-Scenario-5**: Dynamic settings configuration $\to$ Language hot-swap $\to$ Update detection during active playback.
