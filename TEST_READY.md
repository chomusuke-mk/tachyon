# Tachyon Test Suite Readiness: TEST_READY

**Status:** PUBLISHED & READY (Tachyon Lyrics Subsystem Opaque-Box E2E Acceptance Suite)  
**Date:** 2026-09-23  
**Framework:** Flutter Test (`flutter test`) & Dart Pure Test Harness  
**Platforms:** Linux, Windows, macOS, Android, iOS  
**Static Analysis:** `dart analyze` (0 errors, 0 warnings)  
**Test Suite Pass Rate:** 100% (208 / 208 passed)

---

## 1. Executive Summary

The comprehensive opaque-box End-to-End (E2E) Acceptance Test Suite for the **Tachyon Lyrics Subsystem** is fully implemented, verified, and published. 

Derived strictly from authoritative requirements in `ORIGINAL_REQUEST.md` (`## 2026-09-23T05:37:55Z`) and interface contracts in `PROJECT.md` & `TEST_INFRA.md`, the suite exercises all 18 architectural features across 4 rigorous testing tiers and 10 real-world end-to-end user scenarios.

### Test Suite Structure
| Tier | Description | Files | Test Count | Pass Rate |
|---|---|---|:---:|:---:|
| **Tier 1** | Isolated Feature Verification (F1 - F18, 5 tests each) | `test/lyrics_e2e/tier1_feature_test.dart` | 90 | 100% |
| **Tier 2** | Boundary, Corner Cases & Error-Prone Inputs (F1 - F18, 5 tests each) | `test/lyrics_e2e/tier2_boundary_test.dart` | 90 | 100% |
| **Tier 3** | Cross-Feature Interaction Verification (Pairwise interactions) | `test/lyrics_e2e/tier3_cross_feature_test.dart` | 18 | 100% |
| **Tier 4** | Real-World Application Scenarios | `test/lyrics_e2e/tier4_real_world_test.dart` | 10 | 100% |
| **Master** | Master Acceptance Runner (Combines Tiers 1 - 4) | `test/features/playback/lyrics_e2e_test.dart` | 208 | 100% |

---

## 2. Requirement & Feature Coverage Matrix

### Feature Verification Checklist (Tiers 1 & 2: 10 tests each)
- [x] **F1: SQLite Per-Origin Persistence**: Table `lyrics_source_cache` schema with composite primary key `(key_hash, source)`, status, raw_lrc, sync flag, updated_at timestamp.
- [x] **F2: Per-Origin State Tracking**: Records `FOUND`, `NOT_FOUND`, and `TEMPORARY_ERROR`. Skips querying sources previously confirmed as `NOT_FOUND`. Allows retrying sources in `TEMPORARY_ERROR`.
- [x] **F3: Domain Models & Source Enums**: Type-safe `LyricsSource` (`embedded`, `file`, `lrclib`, `lyricsOvh`), `LyricsSourceState` (`found`, `notFound`, `temporaryError`), and immutable `LyricsSourceEntry`.
- [x] **F4: Primary API Client (`lrclib.net`)**: `GET /api/get` with track, artist, album, duration with $\pm 2$s tolerance, client `User-Agent` header, instrumental flag, and 404 handling.
- [x] **F5: Secondary API Client (`lyrics.ovh`)**: `GET /v1/{artist}/{title}` URL-encoded fallback for plain text lyrics without timestamps.
- [x] **F6: Rate Limiting (500ms Pacing)**: Enforces minimum 500 ms spacing between consecutive outgoing requests to `lrclib.net`.
- [x] **F7: HTTP 429 Retry-After Handling**:
  - `Retry-After <= 10s`: Live threshold countdown banner and automated retry upon timer completion.
  - `Retry-After > 10s`: Immediate fallback to `lyrics.ovh` and in-memory cooldown.
- [x] **F8: In-Memory Cooldown & Deferred Retry**: Tracks active memory cooldown; active track re-queries primary upon cooldown expiry; track changes skip primary during cooldown.
- [x] **F9: Free Public Lyrics Translation**: Translates lyrics via public endpoint without API keys, batching $\le 400$ chars, preserving newlines and 1:1 timestamps.
- [x] **F10: Rapid Track Skip Concurrency Cancellation**: Monotonic generation tokens cancel in-flight HTTP requests and discard intermediate songs ($1 \to 2 \to 3 \to 4 \to 5 \implies$ only track 5 displayed).
- [x] **F11: Remote Web Query Visibility Gating**: Suppresses web API calls when Now Playing / Lyrics view is closed; background playback only accesses local sources.
- [x] **F12: 4-Tier Hierarchical LyricsService**: Strict resolution order: 1. Embedded tags $\to$ 2. Local contiguous `.lrc` $\to$ 3. `lrclib.net` $\to$ 4. `lyrics.ovh`.
- [x] **F13: Now Playing Visibility Binding**: Binds Now Playing lifecycle and sheet visibility to `LyricsController.setLyricsViewVisible`.
- [x] **F14: UI Translation Button & Display Modes**: Cycles through Original, Translated, and Interleaved display modes.
- [x] **F15: UI Sources Configuration Dialog**: Floating dialog with switches for Local files, `lrclib.net`, `lyrics.ovh`, and re-search action.
- [x] **F16: UI Manual Re-search Button**: "Volver a buscar" button forces fresh search across enabled sources, bypassing memory cache and SQLite `NOT_FOUND`.
- [x] **F17: Non-Invasive 429 Countdown Banner**: Real-time live countdown banner for thresholds $\le 10$ seconds.
- [x] **F18: Complete i18n Localization**: Zero hardcoded strings rule. Validates `en.jsonc`, `es.jsonc`, and `AppStringKey` getters.

---

## 3. Real-World Application Scenarios (Tier 4)

- [x] **Scenario 1: Full Happy Path**: Track plays with open Now Playing $\to$ fetched from `lrclib.net` $\to$ synced lyrics displayed, verified on UI stream and persisted in SQLite.
- [x] **Scenario 2: Offline/Local First**: Track with embedded USLT tag plays $\to$ instant display without web calls, verified that 0 HTTP requests are made.
- [x] **Scenario 3: Contiguous .lrc Fallback**: External `.lrc` file in folder loaded before web APIs, verified precedence over `lrclib.net`.
- [x] **Scenario 4: 404 Caching**: `lrclib` returns 404 $\to$ `lyrics.ovh` returns plain lyrics $\to$ next play skips `lrclib` and loads cached lyrics from SQLite.
- [x] **Scenario 5: Short 429 Threshold**: `lrclib` returns 429 `Retry-After: 3s` $\to$ countdown banner displays live timer $\to$ auto-retry succeeds upon timer reaching 0.
- [x] **Scenario 6: Long 429 Fallback & Deferred Upgrade**: 429 `Retry-After: 60s` $\to$ fallback to `lyrics.ovh` $\to$ in-memory cooldown active $\to$ cooldown expires $\to$ auto-upgrades to `lrclib` synced lyrics without user intervention.
- [x] **Scenario 7: Rapid Skip Burst**: User jumps $1 \to 2 \to 3 \to 4 \to 5$ in quick succession $\to$ intermediate tracks 2, 3, 4 are discarded/cancelled; only track 5 queries network; no 429 rate limit errors or stale lyrics.
- [x] **Scenario 8: Background Playback Suppression**: Track plays while Now Playing is closed $\to$ web APIs never queried; user then opens Now Playing $\to$ lyrics fetched and displayed.
- [x] **Scenario 9: Translation Flow**: User clicks translate $\to$ fetched via free endpoint with $\le 400$ char chunking $\to$ interleaved display mode presents synchronized original and translation lines.
- [x] **Scenario 10: Source Disabling & Re-search**: User opens Sources dialog $\to$ disables web sources (`lrclib` and `lyrics.ovh`) $\to$ clicks "Volver a buscar" $\to$ only local sources checked; web APIs never touched.

---

## 4. Test Runner & Verification Commands

### 1. Run Complete Master Acceptance Suite (208 tests)
```bash
flutter test test/features/playback/lyrics_e2e_test.dart
```

### 2. Run Individual Tiers
```bash
# Tier 1: Isolated Feature Verification (90 tests)
flutter test test/lyrics_e2e/tier1_feature_test.dart

# Tier 2: Boundary, Corner Cases & Error-Prone Inputs (90 tests)
flutter test test/lyrics_e2e/tier2_boundary_test.dart

# Tier 3: Cross-Feature Interaction Verification (18 tests)
flutter test test/lyrics_e2e/tier3_cross_feature_test.dart

# Tier 4: Real-World Application Scenarios (10 scenarios)
flutter test test/lyrics_e2e/tier4_real_world_test.dart
```

### 3. Run Static Analysis (0 issues required)
```bash
dart analyze test/
dart analyze
```
