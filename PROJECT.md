# Project: Tachyon Music Player

## Architecture
Tachyon is built with Flutter (Dart) using Clean Architecture and a 4-tier Provider hierarchy:
- **Core Layer**: 
  - Database: Relational SQLite schema via `sqflite` (desktop backed by `sqflite_common_ffi` and `sqlite3`), managing tracks, albums, artists, genres, playlists, and multi-origin lyrics caching.
  - Metadata Extraction: Pure Dart tags and metadata extraction using `audio_metadata_reader` executed in a background worker `Isolate` (`scan_isolate.dart`), ensuring zero UI thread jank.
  - Cover Cache Service: In-memory image processing and direct filesystem caching for embedded and local artwork (`cover.jpg`, `folder.jpg`).
  - Audio Engine: High-fidelity audio playback orchestrator (`AudioEngineService`) managing two `AudioPlayerAdapter` instances backed by `just_audio` and `just_audio_media_kit` for continuous, customizable crossfade (Equal-Power and Linear curves with a 25ms periodic ticker), gapless playback, pitch and speed control, and queue management (`QueueManager`).
  - Lyrics Resolution Service: Multi-source hierarchical resolver (`LyricsService`) with $O(\log n)$ synchronized timestamp lookup via `LrcParser` and `SplayTreeMap`.
- **Data Layer**: Repositories for Library, Settings (`SharedPreferences`), Locales (JSONC bundles), and Playlists.
- **Domain Layer**: Immutable entity models (`Track`, `Album`, `Artist`, `Genre`, `Playlist`, `QueueItem`, `PlaybackState`, `LyricLine`, `CrossfadeConfig`, `AppStringKey`).
- **Presentation Layer**: Adaptive Material 3 UI (Desktop NavigationRail + Transport Bar, Mobile NavigationBar + MiniPlayer), feature screens (Tracks, Albums, Artists, Genres, Folders, Playlists, Search, Settings, Now Playing, LyricsView, AudioEffectsSheet), and ChangeNotifier controllers.

---

## Code Layout
```
lib/
├── app.dart                                # MaterialApp entry (theme, locale, routes)
├── main.dart                               # Service initialization & 4-tier MultiProvider setup
├── core/
│   ├── constants/
│   │   └── app_defaults.dart              # Audio constants, volume defaults, rate limits
│   ├── database/
│   │   └── app_database.dart              # SQLite schema, tables, indexes, lyrics_cache
│   └── services/
│       ├── audio_engine_service.dart      # Dual-player crossfade engine & playback coordinator
│       ├── audio_player_adapter.dart      # just_audio / just_audio_media_kit wrapper
│       ├── audio_session_manager.dart     # Audio focus, interruptions and becoming noisy handling
│       ├── cover_cache_service.dart       # Embedded & local cover art extractor and disk cache
│       ├── lrc_parser.dart                # LRC parser with SplayTreeMap O(log n) synchronization
│       ├── lyrics_service.dart            # Multi-source lyrics resolution & LRU memory cache
│       ├── metadata_extractor.dart        # Main isolate bridge to background scan isolate
│       ├── queue_manager.dart             # Queue orchestration, Fisher-Yates shuffle & loop modes
│       └── scan_isolate.dart              # Background isolate running audio_metadata_reader
├── features/
│   ├── library/
│   │   ├── domain/
│   │   │   ├── album.dart                 # Album domain entity
│   │   │   ├── artist.dart                # Artist domain entity
│   │   │   ├── genre.dart                 # Genre domain entity
│   │   │   ├── playlist.dart              # Playlist & PlaylistTrack entities
│   │   │   ├── scan_progress.dart         # Scan progress model
│   │   │   └── track.dart                 # Track domain entity
│   │   └── presentation/
│   │       ├── album_detail_screen.dart   # Album tracklist & header
│   │       ├── albums_screen.dart         # Responsive album card grid
│   │       ├── artist_detail_screen.dart  # Artist discography view
│   │       ├── artists_screen.dart        # Artist list
│   │       ├── folders_screen.dart        # Hierarchical filesystem explorer
│   │       ├── genres_screen.dart         # Categorized genre track explorer
│   │       ├── library_controller.dart    # Library scanning & metadata ChangeNotifier
│   │       └── tracks_screen.dart         # Virtualized track list with contextual actions
│   ├── locales/
│   │   ├── data/
│   │   │   └── locale_repository.dart     # JSONC bundle loader with jsonc parser
│   │   ├── domain/
│   │   │   └── locale.dart                # AppStringKey typed accessors & key registry
│   │   └── presentation/
│   │       └── locale_controller.dart     # Dynamic language switching with fallback cache
│   ├── playback/
│   │   ├── domain/
│   │   │   ├── behavior_subject.dart      # Reactive single-value stream subject
│   │   │   ├── crossfade_config.dart      # Duration, curve formulas (Equal-Power / Linear)
│   │   │   ├── lyric_line.dart            # Timestamped & plain lyric line model
│   │   │   ├── playback_state.dart        # Position, duration, volume, isPlaying, rate, pitch
│   │   │   └── queue_item.dart            # Queue item model, LoopMode & PlaybackStatus enums
│   │   └── presentation/
│   │       ├── audio_effects_sheet.dart   # Speed, pitch, volume boost & crossfade bottom sheet
│   │       ├── lyrics_controller.dart     # Synchronized lyrics state & scroll locking controller
│   │       ├── lyrics_view.dart           # SplayTreeMap synchronized auto-scroll lyrics UI
│   │       ├── now_playing_screen.dart    # Fullscreen player with album art, waveform seek & modal toggles
│   │       ├── playback_controller.dart   # Playback state ChangeNotifier
│   │       ├── queue_drawer.dart          # Reorderable queue modal drawer
│   │       └── waveform_slider.dart       # Waveform progress bar and seek slider
│   ├── playlists/
│   │   └── presentation/
│   │       ├── playlist_detail_screen.dart# Playlist tracklist & reordering
│   │       ├── playlists_controller.dart  # Playlists CRUD controller
│   │       └── playlists_screen.dart      # Playlists overview screen
│   ├── search/
│   │   └── presentation/
│   │       ├── search_screen.dart         # Real-time search UI across tracks, albums, artists
│   │       └── tachyon_search_controller.dart # Search query and filtering controller
│   ├── settings/
│   │   ├── data/
│   │   │   └── settings_repository.dart   # SharedPreferences persistence
│   │   ├── domain/
│   │   │   └── app_settings.dart          # Audio preferences, directories, theme, language
│   │   └── presentation/
│   │       ├── settings_controller.dart   # Settings ChangeNotifier
│   │       └── settings_screen.dart       # Modular settings with SettingRow
│   └── shell/
│       ├── mini_player_bar.dart           # Persistent docked mini-player
│       └── tachyon_shell.dart             # Responsive shell (Desktop Rail vs Mobile NavigationBar)
└── shared/
    ├── theme/
    │   └── app_theme.dart                 # Material 3 5-tier surface hierarchy, Dark/Light/OLED
    └── widgets/
        ├── album_art_image.dart           # Cached artwork with fallback asset
        ├── setting_row.dart               # Responsive setting row/column widget
        └── track_tile.dart                # Track item tile for lists
```

---

## Feature Inventory
| # | Feature | Description | Architecture | Source |
|---|---------|-------------|--------------|--------|
| 1 | Gapless Playback | Continuous playback between tracks without device sink closing | `just_audio` + `just_audio_media_kit` | `audio_engine_service.dart` |
| 2 | Dual-Player Crossfade | Configurable 1s–12s audio fade-in/fade-out using Equal-Power or Linear curves via 25ms ticker | `AudioEngineService` role-swapping Player A/B | `audio_engine_service.dart` |
| 3 | Pitch Correction & Shifting | Independent playback rate (0.5x–1.5x) and pitch scaling (0.5–1.5) | `AudioPlayerAdapter` | `audio_player_adapter.dart` |
| 4 | Volume Boost | Amplification above 100% up to 200% | `AudioEngineService` / `AudioEffectsSheet` | `audio_effects_sheet.dart` |
| 5 | Fisher-Yates Shuffle | Shuffles playback queue without immediate repetitions, preserving current playing track at index 0 | `QueueManager` | `queue_manager.dart` |
| 6 | Repeat Modes | Repeat Off, Repeat One, Repeat All | `QueueManager` | `queue_manager.dart` |
| 7 | Infinite Library Mix | Appends randomized library tracks when queue completes | `QueueManager` | `queue_manager.dart` |
| 8 | Play Next / Add to Queue | Queue insertion at next index or queue end | `QueueManager` | `queue_manager.dart` |
| 9 | Reorderable Queue Drawer | Drag-and-drop reordering of queue items with live visual sync | `QueueDrawer` | `queue_drawer.dart` |
| 10 | Pure Dart Metadata Extraction | Asynchronous non-blocking metadata extraction via `audio_metadata_reader` in background `Isolate` (no CLI binaries) | `scan_isolate.dart` & `MetadataExtractor` | `metadata_extractor.dart` |
| 11 | Multi-Artist/Genre Splitting | Parses multi-value tags by common delimiters (`,`, `;`, `/`) | `scan_isolate.dart` | `scan_isolate.dart` |
| 12 | Embedded Cover Art Extraction | Extracts Picture bytes directly via `audio_metadata_reader` into disk cache | `CoverCacheService` | `cover_cache_service.dart` |
| 13 | Directory Artwork Fallback | Checks parent directory for `cover.jpg`, `folder.jpg`, `front.jpg` | `CoverCacheService` | `cover_cache_service.dart` |
| 14 | Relational SQLite Schema | Normalized tables for tracks, albums, artists, genres, playlists, and lyrics cache | `AppDatabase` (`sqflite`/`sqlite3`) | `app_database.dart` |
| 15 | Special Playlists | Liked Songs and History auto-managed playlists | `AppDatabase` | `app_database.dart` |
| 16 | High-Performance Indexing | B-Tree indexes on track URI, title, artist, album for instant queries | `AppDatabase` | `app_database.dart` |
| 17 | Synchronized LRC Parsing | Parses timestamped lyrics with offset headers and multiline support | `LrcParser` | `lrc_parser.dart` |
| 18 | SplayTreeMap Lyric Lookup | $O(\log n)$ real-time active lyric line resolution based on current playback position | `LrcParser` & `LyricsController` | `lrc_parser.dart` |
| 19 | Tap-to-Seek Lyrics | Seeking audio playback position directly by tapping any timestamped lyric line | `LyricsView` & `LyricsController` | `lyrics_view.dart` |
| 20 | Hierarchical Lyrics Resolution | Embedded -> Local `.lrc` -> `lrclib.net` -> `lyrics.ovh` with SQLite origin tracking | `LyricsService` & `LyricsController` | `lyrics_service.dart` |
| 21 | Adaptive UI Shell | Responsive Desktop `NavigationRail` and Mobile `NavigationBar` + `MiniPlayerBar` | `TachyonShell` | `tachyon_shell.dart` |
| 22 | Waveform / Progress Slider | Interactive seek bar with elapsed and remaining time | `WaveformSlider` | `waveform_slider.dart` |
| 23 | Material 3 Theming | 5-tier surface hierarchy, Electric Violet seed, Light, Dark, and OLED modes | `AppTheme` | `app_theme.dart` |
| 24 | Real-Time Global Search | Live search across tracks, albums, and artists | `TachyonSearchController` | `search_screen.dart` |
| 25 | JSONC i18n Localization | Compile-time safe localization in English and Spanish with zero hardcoded strings | `AppStringKey` & `LocaleController` | `locale.dart` |
| 26 | Audio Session / Becoming Noisy | Auto-pauses on headphone disconnection or audio focus loss | `AudioSessionManager` | `audio_session_manager.dart` |
| 27 | Preferences Persistence | SharedPreferences storage for audio settings, theme, directories, and language | `SettingsRepository` | `settings_repository.dart` |
| 28 | Music Folders Management | Add/remove music directories and trigger background library rescan | `SettingsController` & `LibraryController` | `folders_screen.dart` |

---

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Persistence & Domain Models | SQLite schema (`AppDatabase`), domain models, SharedPreferences, i18n JSONC foundation (`AppStringKey`). | None | DONE |
| M2 | Pure Dart Metadata & Cover Cache | `audio_metadata_reader` in background `Isolate` (`scan_isolate.dart`), direct cover extraction, batch DB ingestion. | M1 | DONE |
| M3 | Playback & Dual-Player Crossfade Engine | `just_audio` + `just_audio_media_kit` integration, dual-player crossfade ticker, queue management, reactive state streams. | M1 | DONE |
| M4 | Adaptive Material 3 UI & Navigation Shell | Theme system, adaptive layout shell (Desktop/Mobile), Library screens (Tracks, Albums, Artists, Genres, Folders, Playlists), Search, Settings. | M1, M2, M3 | DONE |
| M5 | Now Playing View & Lyrics Subsystem | Fullscreen Now Playing, hierarchical lyrics resolver (embedded, .lrc, lrclib.net, lyrics.ovh), SQLite state tracking, rate limiting & UI controls. | M3, M4 | DONE |
| M6 | Update Checker, CI/CD Workflows & Docs | GitHub Releases update checker, GitHub Actions CI/CD workflows, comprehensive Markdown documentation and AGENTS guide. | M1, M4, M5 | IN_PROGRESS |
| M7 | Testing Infrastructure & Verification | Unit tests for pure Dart isolate scanning, AudioEngineService crossfade math, SQLite repository, LyricsService with network mocks, and widget tests (735 passing tests). | M1-M6 | DONE |

---

## Interface Contracts

### `AppDatabase` (Persistence)
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
  Future<bool> isTrackLiked(int trackId);
  Future<void> toggleLikeTrack(int trackId, String uri);
  Future<void> saveLyrics(String keyHash, String rawLrc, String source);
  Future<String?> getLyrics(String keyHash);
  Future<void> close();
}
```

### `MetadataExtractor` (Scanning Bridge)
```dart
abstract class MetadataExtractor {
  int get workerCount;
  Future<Track?> extractMetadata(String filePath);
  Stream<ScanProgress> scanDirectories(List<String> directories);
  Future<void> cancelScan();
  void dispose();
}
```

### `AudioEngineService` ↔ `PlaybackController`
```dart
abstract class AudioEngineService {
  Stream<PlaybackState> get stateStream;
  PlaybackState get currentState;
  Future<void> open(List<QueueItem> items, {int index = 0, bool play = true, bool shuffle = false});
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
  Future<void> setLoopMode(LoopMode loop);
  Future<void> toggleShuffle();
  Future<void> insertNext(QueueItem item);
  Future<void> append(List<QueueItem> items);
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
All UI widgets access: `context.watch<LocaleController>().localeStrings.<key>` (`AppStringKey`).
