# Dual-Track E2E Test Infrastructure: Tachyon Music Player

**Status**: Active  
**Specification Version**: 1.0.0  
**Target Platform**: Flutter / Dart (Desktop: Linux, Windows, macOS; Mobile: Android, iOS)  
**Authoritative Scope**: Requirements R1–R6 defined in `ORIGINAL_REQUEST.md` and `PROJECT.md`

---

## 1. Test Philosophy: Opaque-Box & Requirement-Driven

The Tachyon End-to-End (E2E) testing framework is constructed under the **Opaque-Box (Black-Box)** paradigm. Tests evaluate the system strictly through observable behaviors, public interface contracts, reactive state emissions, and persistence side-effects, rather than inspecting private implementation internals.

### Core Principles
1. **Requirement-Driven Verification**: Every test case directly traces back to an explicit requirement in `ORIGINAL_REQUEST.md` (R1 through R6) and the architectural contracts in `PROJECT.md`.
2. **Dual-Track Decoupling**: E2E acceptance tests and test harnesses operate on Track B, while implementation milestones (M1–M6) progress on Track A. The acceptance suite establishes an immutable behavioral contract and oracle against which the application is continuously validated.
3. **Deterministic Mathematical & State Machine Verification**:
   - Audio crossfade equal-power acoustic calculations ($V_A^2 + V_B^2 = V_{\text{master}}^2$) and linear volume fades are validated against exact mathematical closed forms.
   - Real-time lyrics synchronization is tested for logarithmic $O(\log n)$ temporal resolution using `SplayTreeMap`.
   - Queue mutations (Fisher-Yates shuffle, loop modes, index clamping) are validated for permutation correctness and zero immediate repetition.
4. **Resilient Isolation & Progressive Testability**: Tests set up their own state, run independently of test execution order, clean up shared resources, and operate seamlessly in headless CI environments without requiring physical audio hardware sinks or live display servers.

---

## 2. 4-Tier Test Architecture

The test suite is partitioned into four distinct tiers, progressing from fundamental feature correctness to complex real-world interaction workflows:

```
┌────────────────────────────────────────────────────────────────────────┐
│                   Tier 4: Real-World Scenarios                         │
│  Multi-step, stateful user journeys spanning all system subsystems     │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
┌───────────────────────────────────┴────────────────────────────────────┐
│              Tier 3: Cross-Feature Interactions (Pairwise)             │
│  Pairwise permutations between player, database, UI, i18n & updates    │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
┌───────────────────────────────────┴────────────────────────────────────┐
│                Tier 2: Boundary & Corner Cases (Stress)                │
│  Zero-byte inputs, corrupt tags, duration mismatches, rapid events     │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
┌───────────────────────────────────┴────────────────────────────────────┐
│                  Tier 1: Feature Coverage (Baseline)                   │
│  Direct acceptance testing of requirements R1 through R6 (>=5 each)   │
└────────────────────────────────────────────────────────────────────────┘
```

### Tier 1: Feature Coverage (Baseline)
Validates core functional happy-paths for every primary feature mandated in requirements R1 through R6:
- **R1 (Playback & Crossfade Engine)**: Multi-format support, dual-instance crossfade orchestration, repeat modes (`off`, `one`, `all`), Fisher-Yates shuffle with index preservation, and reactive state stream emissions.
- **R2 (Metadata & Cover Extraction)**: Asynchronous `ffprobe` tag parsing, case-insensitive normalization, multi-artist/genre delimiter splitting, embedded cover art caching, and directory artwork fallback.
- **R3 (Persistence & Preferences)**: SQLite relational schema (`tracks`, `albums`, `artists`, `genres`, `playlists`), B-Tree indexing, CRUD operations, special auto-managed playlists (`Liked Songs`, `History`), and `SharedPreferences` audio/theme/locale persistence.
- **R4 (Adaptive UI & Navigation Shell)**: Desktop `NavigationRail` vs. Mobile `NavigationBar` layout rules, virtualized track listing, album card grid, Now Playing controls, real-time search filtering, and modular settings.
- **R5 (Localization & Update Checker)**: Compile-time safe `AppStringKey` accessors, JSONC bundle parsing, runtime language hot-swapping without app restart, and GitHub Releases semver comparison with changelog display.
- **R6 (Automated Testing & CI Harness)**: Deterministic test execution, error-free static analysis compliance, and isolated test execution.

*Target Count*: Minimum 5 tests per requirement ($\ge 30$ tests total; implemented: 36 tests).

### Tier 2: Boundary & Corner Cases
Subjects each requirement to extreme inputs, edge conditions, invalid states, and resource constraints:
- **R1 Boundary**: Tracks shorter than the configured crossfade duration ($D_{\text{track}} \le D_{\text{crossfade}}$), manual seek during active crossfade automation, skip-to-next during active crossfade, single-track `Loop.one` self-crossfade, and volume boost clamping to $[0.0, 200.0\%]$.
- **R2 Boundary**: Corrupted ID3 tags / unparseable streams with filename fallback, empty directories, 0-byte audio files, mixed delimiter multi-artist tags (`"Artist A, Artist B / Artist C; Artist D"`), and missing covers in directories containing non-cover images.
- **R3 Boundary**: Large catalogs ($>5,000$ tracks), special playlist deduplication, cascading deletes of referenced albums/artists, illegal characters in playlist names, and uninitialized preferences default fallback.
- **R4 Boundary**: Layout breakpoint crossing (desktop $\ge 800\text{px}$ to mobile $<800\text{px}$), search queries with regex metacharacters, lyrics with negative offset headers (`[offset:-500]`), unsynchronized lyrics format graceful fallback, and drag-and-drop queue reordering with out-of-bounds indices.
- **R5 Boundary**: Incomplete locale translations falling back transparently to English, corrupted JSONC syntax recovery, malformed remote semver tags, offline network timeouts during update checks, and high-frequency locale toggling.
- **R6 Boundary**: Concurrency safety, isolate message boundary serialization, test teardown cleanup, and deterministic execution under variable platform timings.

*Target Count*: Minimum 5 tests per requirement ($\ge 30$ tests total; implemented: 36 tests).

### Tier 3: Cross-Feature Interactions (Pairwise Combinations)
Tests the emergent behaviors when two or more distinct subsystems interact simultaneously:
1. **R1 (Crossfade) + R3 (Persistence)**: Application restart restoring last played track, playback position, volume, and crossfade configuration seamlessly.
2. **R1 (Queue Shuffle) + R4 (Now Playing Queue UI)**: Shuffling a 50-track queue maintains the currently playing track at index 0 and reactively updates the UI queue order without audio interruption.
3. **R2 (Metadata Ingestion) + R3 (Relational Database)**: Mass directory scanning populates normalized relational tables (`artists`, `albums`, `genres`, `track_genres`) and verifies relational integrity.
4. **R4 (Lyrics View) + R1 (Audio Engine Seek)**: Tapping a synchronized lyric line at timestamp `01:24.50` commands the audio engine to seek, updating playback position and active lyric highlighting synchronously.
5. **R5 (Locale Switch) + R4 (UI Settings & Screens)**: Switching the active locale from English to Spanish in Settings immediately updates localized text across all views without requiring application restart.
6. **R1 (Audio Engine) + R4 (Desktop Transport Bar / MiniPlayer)**: Interactive slider seeking and transport commands smoothly govern playback state and emit reactive updates.
7. **R2 (Cover Cache) + R4 (Now Playing Artwork)**: Extracted disk cover thumbnails are loaded asynchronously; missing artwork falls back cleanly to default placeholders without UI jank.
8. **R3 (Custom Playlists) + R1 (Queue Management)**: Enqueuing a custom playlist ("Play Next") inserts items immediately after the current playing track in the active queue.
9. **R5 (Update Checker) + R4 (Update Modal Dialog)**: A newer release on GitHub triggers a non-intrusive modal dialog displaying the release changelog while audio continues playing in the background.
10. **R1 (Crossfade Automation) + R4 (Progress Slider)**: Manual slider scrub during active crossfade aborts the preloaded instance and resets volume cleanly to master levels.

*Target Count*: $\ge 10$ pairwise combination tests.

### Tier 4: Real-World Application Scenarios
Simulates complete end-user journeys from application boot to complex multitasking workflows:
- **Scenario 1: Cold Start to First Playback with Crossfade**  
  User launches Tachyon for the first time, imports a music folder, verifies relational database ingestion, searches for a track, starts playback, and observes an equal-power crossfade transition into the next track.
- **Scenario 2: Playlist Creation, Management, and Continuous Playback**  
  User builds a custom playlist, reorders tracks via drag-and-drop, adds tracks from album detail, selects "Play Next", enables "Repeat All", and confirms seamless continuous cyclic playback.
- **Scenario 3: Synchronized Lyrics Navigation and Viewport Tracking**  
  User opens Now Playing for an LRC-tagged track, observes $O(\log n)$ active line synchronization during playback, taps a distant lyric line to seek, manually scrolls the viewport (pausing auto-scroll), and verifies auto-scroll resumption.
- **Scenario 4: Audio Device Interruption and Multi-Format Transcoding**  
  User plays FLAC audio at 1.25x speed with volume boost; a system "Becoming Noisy" / headphone disconnect event triggers auto-pause; user reconnects, resumes playback, and skips into an AAC track without pops or stream sink resets.
- **Scenario 5: Dynamic System Configuration and Background Rescan**  
  During active playback, user toggles language to Spanish, adjusts crossfade duration from 5s to 8s, triggers a GitHub update check, and initiates a background library rescan without dropping audio frames or stalling the UI.

*Target Count*: $\ge 5$ end-to-end multi-step scenarios.

---

## 3. Directory Layout & File Manifest

The E2E test framework resides under `test/e2e/`:

```
test/
├── e2e/
│   ├── harness/
│   │   ├── e2e_models.dart             # Opaque-box domain entities (Track, Album, State, Config)
│   │   ├── e2e_math_utils.dart         # Equal-power & linear crossfade math validators
│   │   └── tachyon_driver.dart         # High-level opaque-box test driver & system oracle
│   ├── tier1_feature_test.dart         # Tier 1: R1–R6 Feature Coverage (36 tests)
│   ├── tier2_boundary_test.dart        # Tier 2: Boundary & Corner Cases (36 tests)
│   ├── tier3_cross_feature_test.dart   # Tier 3: Pairwise Interactions (10 tests)
│   └── tier4_real_world_test.dart      # Tier 4: Real-World Application Scenarios (5 tests)
```

---

## 4. Test Runner Commands

All E2E tests are executed via the standard Flutter test runner:

### Execute Complete E2E Test Suite
```bash
flutter test test/e2e/
```

### Execute by Individual Tier
```bash
# Tier 1: Feature Coverage
flutter test test/e2e/tier1_feature_test.dart

# Tier 2: Boundary & Corner Cases
flutter test test/e2e/tier2_boundary_test.dart

# Tier 3: Pairwise Cross-Feature Interactions
flutter test test/e2e/tier3_cross_feature_test.dart

# Tier 4: Real-World Application Scenarios
flutter test test/e2e/tier4_real_world_test.dart
```

### Execute by Requirement Filter
```bash
# Run all tests verifying R1 (Playback & Crossfade)
flutter test test/e2e/ --plain-name "[R1]"

# Run all tests verifying R2 (Metadata & Scanner)
flutter test test/e2e/ --plain-name "[R2]"

# Run all tests verifying R3 (Database & Preferences)
flutter test test/e2e/ --plain-name "[R3]"

# Run all tests verifying R4 (UI & Navigation)
flutter test test/e2e/ --plain-name "[R4]"

# Run all tests verifying R5 (i18n & Updates)
flutter test test/e2e/ --plain-name "[R5]"

# Run all tests verifying R6 (CI & Test Harness)
flutter test test/e2e/ --plain-name "[R6]"
```

### Static Analysis Verification
```bash
dart analyze test/e2e/
```

---

## 5. Traceability Matrix (Requirements R1–R6 ↔ Test Tiers)

| Requirement | Description | Tier 1 Tests | Tier 2 Tests | Tier 3 Tests | Tier 4 Scenarios |
|---|---|---|---|---|---|
| **R1** | Playback Engine, Crossfade & Queue | 6 tests | 6 tests | 6 pairwise | 4 scenarios |
| **R2** | `ffprobe` Metadata & Cover Extraction | 6 tests | 6 tests | 2 pairwise | 2 scenarios |
| **R3** | SQLite Persistence & Preferences | 6 tests | 6 tests | 3 pairwise | 3 scenarios |
| **R4** | Adaptive M3 UI, Now Playing & Lyrics | 6 tests | 6 tests | 5 pairwise | 4 scenarios |
| **R5** | Localization (i18n) & GitHub Updates | 6 tests | 6 tests | 2 pairwise | 2 scenarios |
| **R6** | Automated Tests & Verification | 6 tests | 6 tests | 2 pairwise | 1 scenario |
| **Total** | **87 Total Tests** | **36 tests** | **36 tests** | **10 tests** | **5 scenarios** |

---

## 6. Tier 5 Adversarial Hardening Guidelines (Milestone M7)

For the final milestone (M7), the suite will be augmented with adversarial testing orchestrated alongside Challenger:
1. **Fuzz Testing**: Randomized bit-flip corruptions of audio headers and LRC timestamps.
2. **Stress & Memory Leaks**: Simulating 10,000 rapid playback seeks, continuous 24-hour virtual playback loop, and verifying memory ceiling $< 200\text{MB}$.
3. **Fault Injection**: Simulating OS disk full during cover art extraction, abrupt SIGKILL recovery, and SQLite lock contention.
