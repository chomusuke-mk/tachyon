# Project: Tachyon Music Player

## Architecture
Tachyon is built with Flutter (Dart) using Clean Architecture and a 4-tier Provider hierarchy:
- **Core Layer**: Database (SQLite via `sqflite`/`sqflite_common_ffi`), Metadata Extractor (`ffprobe`/`ffmpeg` isolate worker), Audio Engine (`media_kit` with dual-instance `libmpv` crossfade), Theming & Layout tokens.
- **Data Layer**: Repositories for Library, Playback, Settings, Locales, and GitHub Updates.
- **Domain Layer**: Immutable entity models (`Track`, `Album`, `Artist`, `Genre`, `Playlist`, `LyricLine`, `MediaPlayerState`, `AppStringKey`).
- **Presentation Layer**: Adaptive Material 3 UI (Desktop NavigationRail + Transport Bar, Mobile NavigationBar + MiniPlayer), feature screens, and ChangeNotifier controllers.

## Code Layout
```
lib/
├── app.dart                                # MaterialApp entry (theme, locale, routes)
├── main.dart                               # 4-tier MultiProvider setup & initialization
├── core/
│   ├── constants/
│   │   └── app_constants.dart             # Storage keys, limits, defaults
│   ├── database/
│   │   └── app_database.dart              # SQLite schema, tables, indexes, migrations
│   ├── network/
│   │   └── github_client.dart             # GitHub Releases client with Dio
│   ├── services/
│   │   ├── metadata_extractor.dart        # Background ffprobe isolate runner
│   │   ├── cover_cache_service.dart       # ffmpeg cover extractor & disk cache
│   │   └── audio_engine_service.dart      # media_kit dual-instance crossfade player
│   └── theme/
│       ├── app_theme.dart                 # Material 3 light/dark/OLED theme definitions
│       ├── colors.dart                    # 5-tier surface hierarchy
│       ├── layout.dart                    # 8pt harmonic grid tokens & breakpoints
│       └── typography.dart                # M3 typography + tabular figures
├── features/
│   ├── library/
│   │   ├── data/
│   │   │   └── library_repository.dart    # SQLite queries for tracks, albums, artists, playlists
│   │   ├── domain/
│   │   │   ├── track.dart                 # Track model
│   │   │   ├── album.dart                 # Album model
│   │   │   ├── artist.dart                # Artist model
│   │   │   └── playlist.dart              # Playlist & PlaylistEntry models
│   │   └── presentation/
│   │       ├── library_controller.dart    # Scanning & library state ChangeNotifier
│   │       ├── tracks_screen.dart         # Virtualized track list with context menu
│   │       ├── albums_screen.dart         # Responsive album grid & detail
│   │       ├── artists_screen.dart        # Artist list & discography view
│   │       ├── genres_screen.dart         # Genre list & track detail
│   │       ├── folders_screen.dart        # Filesystem breadcrumb explorer
│   │       └── playlists_screen.dart      # Custom playlists view & detail
│   ├── locales/
│   │   ├── data/
│   │   │   └── locale_repository.dart     # JSONC bundle loader with jsoncDecode
│   │   ├── domain/
│   │   │   └── locale.dart                # AppStringKey typed accessors & key registry
│   │   └── presentation/
│   │       └── locale_controller.dart     # Dynamic language switching with fallback cache
│   ├── playback/
│   │   ├── data/
│   │   │   └── playback_repository.dart   # Bridge to audio engine service
│   │   ├── domain/
│   │   │   ├── playback_state.dart        # Position, duration, volume, isPlaying, rate, pitch
│   │   │   ├── queue_item.dart            # Queue item model & Loop/Shuffle enums
│   │   │   ├── crossfade_config.dart      # Duration (1s-12s), curve formulas
│   │   │   └── lyric_line.dart            # LRC timestamped lyric model
│   │   └── presentation/
│   │       ├── playback_controller.dart   # Playback state ChangeNotifier
│   │       ├── now_playing_screen.dart    # Fullscreen Now Playing view
│   │       └── widgets/
│   │           ├── lyrics_view.dart       # SplayTreeMap synchronized auto-scroll lyrics
│   │           ├── mini_player_bar.dart   # Mobile docked mini-player
│   │           ├── desktop_transport_bar.dart # Desktop bottom transport bar
│   │           └── queue_bottom_sheet.dart    # Reorderable queue modal
│   ├── search/
│   │   └── presentation/
│   │       └── search_screen.dart         # Real-time search across tracks, albums, artists
│   ├── settings/
│   │   ├── data/
│   │   │   └── settings_repository.dart   # SharedPreferences persistence
│   │   ├── domain/
│   │   │   └── app_settings.dart          # Audio settings, directories, theme, language
│   │   └── presentation/
│   │       ├── settings_controller.dart   # Settings ChangeNotifier
│   │       └── settings_screen.dart       # Modular settings with SettingRow
│   └── updates/
│       ├── domain/
│       │   └── update_info.dart           # Release version, asset URL, changelog
│       └── presentation/
│           ├── update_controller.dart     # Update checker ChangeNotifier (6h interval)
│           └── widgets/
│               └── update_dialog.dart     # Modal update dialog
└── shared/
    ├── utils/
    │   ├── changelog_utils.dart           # Bounded markdown changelog viewer
    │   └── toast_utils.dart               # User notifications
    └── widgets/
        ├── album_art_image.dart           # Cached artwork with fallback asset
        ├── lazy_dropdown.dart             # Debounced settings dropdown
        ├── lazy_text_field.dart           # Debounced settings text input
        └── settings_row.dart              # Adaptive row/column responsive setting widget
```

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Gapless Playback | Continuous playback between tracks without device sink closing | M3 | `ARQUITECTURA.md`, `reproduccion.md` |
| 2 | Dual-Instance Crossfade | Configurable 1s-12s audio fade-in/fade-out between tracks using equal-power or linear curves | M3 | `crossfade.md`, `ORIGINAL_REQUEST.md` |
| 3 | Pitch Correction | Independent speed scaling (0.5x-1.5x) using scaletempo2 | M3 | `reproduccion.md`, `efectos_audio.md` |
| 4 | Pitch Shifting | Independent pitch scaling (0.5-1.5) | M3 | `reproduccion.md`, `efectos_audio.md` |
| 5 | Volume Boost | Amplification above 100% up to 200% | M3 | `efectos_audio.md` |
| 6 | ReplayGain Normalization | Volume leveling based on track/album metadata tags | M3 | `efectos_audio.md` |
| 7 | ReplayGain Preamp | Manual dB fine-tuning offset (-15dB to +15dB) | M3 | `efectos_audio.md` |
| 8 | Windows Exclusive Audio | Bit-perfect exclusive device locking on Windows | M3 | `efectos_audio.md` |
| 9 | Custom mpv Properties | Pass arbitrary raw mpv flags to player engine | M3 | `efectos_audio.md` |
| 10 | Fisher-Yates Shuffle | Shuffles queue without immediate repetitions, keeping current track at index 0 | M3 | `reproduccion.md` |
| 11 | Repeat Modes | Repeat Off, Repeat One, Repeat All | M3 | `reproduccion.md` |
| 12 | Infinite Library Mix | Appends randomized library tracks when queue completes | M3 | `reproduccion.md` |
| 13 | Play Next / Add to Queue | Queue insertion at next index or queue end | M3 | `pantallas_ui.md`, `reproduccion.md` |
| 14 | Interactive Queue Reordering | Drag-and-drop reordering of queue items | M5 | `pantallas_ui.md` |
| 15 | Native ffprobe Extraction | Asynchronous non-blocking metadata extraction via native binary | M2 | `media_library.md`, `ORIGINAL_REQUEST.md` |
| 16 | Multi-Artist/Genre Splitting | Parses multi-value tags by common delimiters | M2 | `media_library.md` |
| 17 | Embedded Cover Extraction | Extracts MJPEG/PNG stream via ffmpeg into disk cache | M2 | `media_library.md` |
| 18 | Directory Cover Art Fallback | Checks directory for cover.jpg, folder.jpg, front.jpg | M2 | `media_library.md` |
| 19 | Worker Pool Concurrency | Concurrency-bounded background scanning isolate pool | M2 | `media_library.md` |
| 20 | Relational SQLite Schema | Normalized tables for tracks, albums, artists, genres, playlists | M1 | `media_library.md` |
| 21 | Special Playlists | Liked Songs and History auto-managed playlists | M1 | `media_library.md` |
| 22 | High-Performance Indexing | B-Tree indexes on tracks, albums, artists for instant queries | M1 | `media_library.md` |
| 23 | LRC Format Parsing | Parses timestamped lyrics with offset headers | M5 | `letras.md` |
| 24 | SplayTreeMap Lyric Search | O(log n) real-time active lyric line lookup | M5 | `letras.md` |
| 25 | Tap-to-Seek Lyrics | Seeking audio playback by tapping any lyric line | M5 | `letras.md` |
| 26 | Local Directory .lrc Lookup | Loads external <track_name>.lrc files | M5 | `letras.md` |
| 27 | Adaptive Shell | Responsive Desktop NavigationRail and Mobile NavigationBar | M4 | `pantallas_ui.md` |
| 28 | Waveform / Progress Slider | Interactive seek bar with elapsed and remaining time | M5 | `pantallas_ui.md` |
| 29 | Palette Theming | Material 3 5-tier surface theme with electric violet seed | M4 | `pantallas_ui.md` |
| 30 | Real-Time Global Search | Live search across tracks, albums, and artists | M4 | `pantallas_ui.md` |
| 31 | Multi-Selection Action Bar | Batch play, queue addition, and playlist assignment | M4 | `pantallas_ui.md` |
| 32 | Wakelock in Now Playing | Keeps display awake during active playback | M5 | `pantallas_ui.md` |
| 33 | JSONC AppStringKey Localization | Compile-time safe localization in en/es with zero hardcoded strings | M1 | `ORIGINAL_REQUEST.md`, `vidra` |
| 34 | Audio Service & Media Notification | Background playback and lockscreen media notifications | M3 | `notificaciones.md` |
| 35 | Audio Session / Becoming Noisy | Auto-pauses on headphone disconnect or incoming call | M3 | `notificaciones.md` |
| 36 | Linux MPRIS2 D-Bus | Native Linux desktop media controls integration | M3 | `notificaciones.md` |
| 37 | Windows SMTC Integration | Windows System Media Transport Controls integration | M3 | `notificaciones.md` |
| 38 | Discord Rich Presence | Shows playing track info on Discord | M3 | `notificaciones.md` |
| 39 | Last.fm Scrobbling | Submits scrobbles for tracks played >50% | M3 | `notificaciones.md` |
| 40 | GitHub Releases Update Checker | Checks latest releases with version comparison and changelog modal | M6 | `ORIGINAL_REQUEST.md`, `vidra` |
| 41 | Preferences Persistence | SharedPreferences storage for audio settings, theme, and paths | M1 | `ORIGINAL_REQUEST.md` |
| 42 | Music Folders Management | Add/remove music directories and trigger library rescan | M4 | `ORIGINAL_REQUEST.md` |
| 43 | Tracks Screen Virtualized List | Fast list view with sorting and context menu | M4 | `ORIGINAL_REQUEST.md` |
| 44 | Albums Grid & Album Detail | Responsive album card grid and track listing | M4 | `ORIGINAL_REQUEST.md` |
| 45 | Artists List & Discography Detail | Artist catalog and discography view | M4 | `ORIGINAL_REQUEST.md` |
| 46 | Genres & Folders Explorers | Categorized genre tracks and hierarchical file explorer | M4 | `ORIGINAL_REQUEST.md` |
| 47 | Playlists CRUD & Reordering | Create, edit, reorder, delete custom playlists | M4 | `ORIGINAL_REQUEST.md` |
| 48 | Settings Screen | Modular settings for audio, appearance, language, about | M4 | `ORIGINAL_REQUEST.md` |
| 49 | CI/CD GitHub Actions | Push/PR validation workflow and multi-platform release automation | M6 | `ORIGINAL_REQUEST.md` |
| 50 | Technical Documentation | Complete README, Architecture, Build, and Modules guides | M6 | `ORIGINAL_REQUEST.md` |
| 51 | Automated Unit & E2E Tests | Unit, widget, and end-to-end acceptance test suites | M7 | `ORIGINAL_REQUEST.md` |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Dependencies, Domain Models & Persistence Layer | Add dependencies (`sqflite`, `sqflite_common_ffi`), domain models, SQLite schema (`AppDatabase`), SharedPreferences repository, and i18n JSONC foundation (`AppStringKey`, `LocaleRepository`, `LocaleController`). | None | DONE |
| M2 | Metadata Extraction & Cover Art Cache Service | Native `ffprobe`/`ffmpeg` locator, background scanning isolate worker pool, JSON tag parsing, cover extraction, disk cache, batch DB ingestion. | M1 | DONE |
| M3 | Playback & Dual-Instance Crossfade Engine | `media_kit` audio player engine, dual-instance crossfade orchestration, queue management (shuffle, repeat, next/prev), reactive state streams, audio effects. | M1 | DONE |
| M4 | Adaptive Material 3 UI & Navigation Shell | Theme system (5-tier surface hierarchy, tabular figures), adaptive layout shell (Desktop/Mobile), Library screens (Tracks, Albums, Artists, Genres, Folders, Playlists), Search, Settings screen. | M1, M2, M3 | DONE |
| M5 | Now Playing View, Synchronized Lyrics & Queue Drawer | Fullscreen Now Playing view, LRC parser, SplayTreeMap O(log n) lyric synchronization, smooth auto-scroll, interactive reorderable queue drawer. | M3, M4 | IN_PROGRESS |
| M6 | Update Checker, CI/CD Workflows & Documentation | GitHub Releases update checker, GitHub Actions CI/CD workflows (`ci.yml`, `release.yml`), comprehensive Markdown documentation. | M1, M4, M5 | PLANNED |
| M7 | Final Milestone: E2E Test Suite Pass & Adversarial Hardening | Pass 100% of E2E tests (Tiers 1-4 published in `TEST_READY.md`), run Tier 5 adversarial coverage hardening with Challenger, verify `dart analyze` (0 errors, 0 warnings) and `flutter test`. | M1-M6, TEST_READY | PLANNED |

## Interface Contracts
### `AppDatabase` (Persistence) ↔ `LibraryRepository` / `MetadataExtractor`
```dart
abstract class AppDatabase {
  Future<void> init();
  Future<void> insertOrUpdateTrack(Track track);
  Future<void> batchInsertTracks(List<Track> tracks);
  Future<List<Track>> getAllTracks({String? sortBy, bool ascending = true});
  Future<List<Album>> getAllAlbums();
  Future<List<Artist>> getAllArtists();
  Future<List<Genre>> getAllGenres();
  Future<List<Playlist>> getAllPlaylists();
  Future<List<Track>> getTracksForPlaylist(int playlistId);
  Future<int> createPlaylist(String name);
  Future<void> addTrackToPlaylist(int playlistId, int trackId);
  Future<void> removeTrackFromPlaylist(int playlistId, int trackId);
  Future<void> reorderPlaylistEntries(int playlistId, int fromIndex, int toIndex);
  Future<List<Track>> searchTracks(String query);
  Future<void> close();
}
```

### `MetadataExtractor` ↔ `LibraryRepository`
```dart
abstract class MetadataExtractor {
  Future<Track?> extractMetadata(String filePath);
  Stream<ScanProgress> scanDirectories(List<String> directories);
  Future<String?> extractCoverArt(String filePath, String cacheDir);
}
```

### `AudioEngineService` ↔ `PlaybackController`
```dart
abstract class AudioEngineService {
  Stream<MediaPlayerState> get stateStream;
  MediaPlayerState get currentState;
  Future<void> open(List<Playable> playables, {int index = 0, bool play = true, bool shuffle = false});
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> next();
  Future<void> previous();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> setRate(double rate);
  Future<void> setPitch(double pitch);
  Future<void> setCrossfadeConfig(CrossfadeConfig config);
  Future<void> setLoopMode(Loop loop);
  Future<void> toggleShuffle();
  Future<void> insertNext(Playable playable);
  Future<void> append(List<Playable> playables);
  Future<void> remove(int index);
  Future<void> reorder(int from, int to);
  Future<void> dispose();
}
```

### `LocaleRepository` & `LocaleController` (i18n)
```dart
abstract class LocaleRepository {
  Future<Map<String, String>> getLocaleStrings(String localeCode);
}
```
All UI widgets access: `context.watch<LocaleController>().localeStrings.npTitle` (AppStringKey).
