# Project: Tachyon Linux Performance Optimization

## Architecture
Tachyon is an audio player built with Flutter (Dart) and backed by `just_audio` / `just_audio_media_kit` (`libmpv` on Linux desktop) and SQLite (`sqflite_common_ffi`).
The performance architecture decomposes the optimization across three decoupled layers:
1. **Memory & Resource Management Layer**: Hard-caps raster memory in `PaintingBinding.instance.imageCache`, enforces decode-time downsampling (`cacheWidth`/`cacheHeight`) in `AlbumArtImage`, trims native `libmpv` demuxer/buffers to 1–2MB, streams file discovery in `scan_isolate.dart`, and projects lightweight catalog queries omitting heavy text blobs (`t.lyrics`).
2. **Rendering & Compositing Layer**: Decouples high-frequency position ticks (20–50Hz) from `PlaybackController.notifyListeners()`, uses scoped `ValueListenableBuilder` / `StreamBuilder` for time and seekbars, converts library screen listeners to `context.select`, wraps animated components (`WaveformSlider`, ambient backdrop, hero art, mini player) in `RepaintBoundary`, and throttles disk persistence of playhead position.
3. **Linux GTK Embedding Layer**: Eliminates window resize flickering by matching the GTK `FlView` background color to `#0E0B16` (dark canvas), injecting a GTK CSS provider with identical background, adding window geometry hints, calling `XInitThreads()`, and removing `AnimatedSize` layout thrashing during interactive resizing.
4. **Testing & Benchmark Track (Parallel)**: Establishes a zero-dependency automated Linux benchmark harness (`benchmark/linux_benchmark.py`), a 4-tier regression suite covering unit tests for uncovered components (`AudioEngineService`, `WaveformSlider`, `NowPlayingScreen`), stress tests, invariant gating, and release performance verification.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---|---|---|---|
| 1 | Constrain ImageCache | Set `PaintingBinding.instance.imageCache` maximumSize to 60 and maximumSizeBytes to 15MB | M1 | survey_1 |
| 2 | Decode-Time Image Downsampling | Add `cacheWidth` and `cacheHeight` with DPR scaling to `AlbumArtImage` | M1 | survey_1, survey_2 |
| 3 | Memory-Cached Cover Existence | Replace `FutureBuilder(coverFile.exists())` with an in-memory set in `AlbumArtImage` | M1 | survey_2 |
| 4 | Downsize Player Buffers | Reduce `bufferSize` from 8MB to 1MB in `TachyonAudioPlatform` | M1 | survey_1 |
| 5 | Constrain MPV Demuxer Caches | Set `demuxer-max-bytes=2MB`, `demuxer-max-back-bytes=512KB`, `demuxer-readahead-secs=10` on native MPV player | M1 | survey_1 |
| 6 | Catalog Query Projection Trimming | Remove `t.lyrics` from `getAllTracks` and `searchTracks`; add dedicated `getTrackLyricsByUri` in SQLite | M1 | survey_1 |
| 7 | Eliminate Duplicate Catalog Lists | Avoid redundant `List.from(_tracks)` cloning when no filters are active in `LibraryController` | M1 | survey_1 |
| 8 | Lightweight Liked Tracks Query | Query `playlist_tracks` track_id column directly instead of full Track materialization in `PlaylistsController` | M1 | survey_1 |
| 9 | Streamed Scan Discovery & Worker Limiting | Process audio files as a stream in `scan_isolate.dart` without accumulating all Futures in heap | M1 | survey_1 |
| 10 | Explicit Scan Isolate Termination | Call `kill(priority: immediate)` on isolate completion in `MetadataExtractor` | M1 | survey_1 |
| 11 | Decouple Position Stream from notifyListeners | Stop calling `notifyListeners()` on pure position ticks in `PlaybackController`; expose scoped `ValueNotifier<Duration>` | M2 | survey_1, survey_2 |
| 12 | Throttle SharedPreferences Disk Writes | Throttle `setLastPlayed` to once every 5-10s and on pause/stop/track change in `PlaybackController` | M2 | survey_2, survey_3 |
| 13 | Targeted Library Listeners | Replace `context.watch<PlaybackController>()` with `context.select` across all 9 library and search screens | M2 | survey_1, survey_2 |
| 14 | RepaintBoundary Isolation | Add `RepaintBoundary` around `WaveformSlider`, `_buildAmbientBackdrop`, `_buildHeroCoverArt`, and `MiniPlayerBar` | M2 | survey_2, survey_3 |
| 15 | WaveformSlider Painter Optimization | Precompute 55 bar geometries, batch draw calls into 2 Paths, reuse Paint instances, quantize `shouldRepaint` | M2 | survey_2 |
| 16 | Ambient Backdrop Downsampling | Pass 128x128 thumbnail bounds to ambient backdrop `AlbumArtImage` in `NowPlayingScreen` | M2 | survey_2 |
| 17 | GTK FlView Background Color Sync | Set `fl_view_set_background_color` and GTK window CSS background to `#0E0B16` in `my_application.cc` | M3 | survey_2, survey_3 |
| 18 | Linux Window Geometry Hints | Set minimum window geometry hints (min_width: 480, min_height: 360) in `my_application.cc` | M3 | survey_2 |
| 19 | Linux Thread Synchronization | Add `XInitThreads()` before GTK initialization in `linux/runner/main.cc` | M3 | survey_2 |
| 20 | Eliminate Resize Layout Thrashing | Remove `AnimatedSize` inside `_buildPlayer` in `now_playing_screen.dart` | M3 | survey_2 |
| 21 | Automated Linux Benchmark Harness | Zero-dependency Python profiler reading `/proc/<pid>/status`, `smaps_rollup`, `/proc/<pid>/stat`, and `nvidia-smi` | E2E | survey_3 |
| 22 | Coverage Gap Unit Tests | Add unit tests for `AudioEngineService`, `WaveformSlider`, and `NowPlayingScreen` | E2E | survey_3 |
| 23 | AST i18n & Zero Hardcoded Strings Linter | Unit test scanning AST to assert 0 hardcoded strings in widgets and 100% key symmetry | E2E | survey_3 |
| 24 | Stress & Invariant Test Suites | Verify crossfade rapid skipping, SQLite single-writer concurrency, lyrics visibility gating, and disk write throttling | E2E | survey_3 |
| 25 | Release Performance Verification (Final Gate) | Verify release binary meets RSS <= 50-75MB, CPU < 2%, GPU < 5%, 0 resize flicker, 0 lints, 100% tests pass | M4 | survey_3 |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|---|---|---|---|
| E2E | E2E & Benchmark Testing Track | Automated Linux benchmark harness (`benchmark/linux_benchmark.py`), Tier 1-4 test suites, `TEST_INFRA.md`, publish `TEST_READY.md` | none | DONE |
| M1 | RAM & Buffer Optimization | Features 1–10: ImageCache cap, AlbumArtImage downsampling, MPV buffer & demuxer limits, catalog query trimming, isolate streaming | none | IN_PROGRESS |
| M2 | CPU/GPU Optimization & Layer Isolation | Features 11–16: Position stream decoupling, setLastPlayed throttling, context.select in screens, RepaintBoundaries, WaveformSlider optimization | M1 contract | PLANNED |
| M3 | Linux Window Resize & Flickering Elimination | Features 17–20: FlView background color, GTK CSS provider, XInitThreads, geometry hints, AnimatedSize removal | M2 contract | PLANNED |
| M4 | Final Milestone: Full E2E Pass & Release Verification | Feature 25: Phase 1 pass 100% E2E tests and release benchmarks; Phase 2 adversarial coverage hardening | M1, M2, M3, E2E | PLANNED |

## Interface Contracts

### PlaybackController ↔ UI Widgets (Position Decoupling)
- `PlaybackController` maintains low-frequency state updates through `notifyListeners()` (e.g. `currentTrack`, `isPlaying`, `isBuffering`, `loopMode`, `isShuffled`, `volume`, `rate`, `pitch`).
- High-frequency playback progress is exposed via `ValueListenable<Duration> get positionListenable` (or `Stream<Duration> get positionStream`).
- Progress widgets (`WaveformSlider`, time labels in `NowPlayingScreen`, progress bar in `MiniPlayerBar`) consume `positionListenable` using `ValueListenableBuilder<Duration>`, isolating repaints from the parent screens.
- Library and list screens select only `currentTrack?.uri` or boolean `isPlayingCurrent` via `context.select<PlaybackController, T>()`.

### SQLite AppDatabase ↔ LyricsService & Catalog Queries
- `getAllTracks()` and `searchTracks()` project `NULL AS lyrics`, returning `Track` instances without embedded lyric text blobs.
- Dedicated query `Future<String?> getTrackLyricsByUri(String uri)` or `getTrackLyrics(int trackId)` retrieves raw lyric text on-demand when `LyricsService` needs it.

### AlbumArtImage ↔ Display Callers
- `AlbumArtImage` signature accepts optional `cacheWidth` and `cacheHeight`.
- If omitted, default target decode dimension is calculated as `(width ?? 150) * devicePixelRatio`, capped at maximum bounding box, preventing uncompressed multi-megapixel decodes.

## Code Layout
- `lib/main.dart` — App entrypoint and global `ImageCache` configuration [M1]
- `lib/shared/widgets/album_art_image.dart` — Cover image widget with decode-time downsampling [M1]
- `lib/shared/widgets/track_tile.dart` — List item with bounded thumbnail sizing [M1]
- `lib/core/services/tachyon_audio_platform.dart` — `PlayerConfiguration` and MPV demuxer properties [M1]
- `lib/core/services/audio_engine_service.dart` — Dual player lifecycle & crossfade engine [M1]
- `lib/core/database/app_database.dart` — Relational schema & catalog query projections [M1]
- `lib/core/services/lyrics_service.dart` — On-demand lyrics resolution [M1]
- `lib/features/library/presentation/library_controller.dart` — In-memory catalog management [M1]
- `lib/features/playlists/presentation/playlists_controller.dart` — Lightweight liked track queries [M1]
- `lib/core/services/scan_isolate.dart` & `metadata_extractor.dart` — Streaming file scan & lifecycle [M1]
- `lib/features/playback/presentation/playback_controller.dart` — Playback state & position decoupling [M2]
- `lib/features/playback/presentation/waveform_slider.dart` — Waveform slider with RepaintBoundary & cached geometry [M2]
- `lib/features/playback/presentation/now_playing_screen.dart` — Isolated ambient backdrop & controls [M2, M3]
- `lib/features/shell/mini_player_bar.dart` — Mini player with RepaintBoundary [M2]
- `lib/features/library/presentation/*` — Library screens converted to `context.select` [M2]
- `linux/runner/my_application.cc` — Linux GTK FlView background color, CSS provider, geometry hints [M3]
- `linux/runner/main.cc` — `XInitThreads` initialization [M3]
- `benchmark/linux_benchmark.py` — Automated performance profiler [E2E]
- `test/` — Unit, widget, and regression test suites [E2E]
