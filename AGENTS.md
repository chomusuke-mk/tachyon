# 🤖 AI Agent Normative Guidelines for Tachyon

Welcome! You are an artificial intelligence (AI) agent or code assistant collaborating on the **Tachyon** project. This guide contains the normative instructions, architectural conventions, coding rules, feature design patterns, and critical constraints of the project to ensure maximum precision, security, and architectural coherence.

---

## 🛑 GOLDEN RULE: ABSOLUTE PROHIBITION OF MUTATING GIT COMMANDS

> [!CAUTION]
> **AI AGENTS ARE STRICTLY FORBIDDEN FROM RUNNING GIT COMMANDS THAT MUTATE THE REPOSITORY STATE: `git add`, `git commit`, `git push`, `git pull`, `git checkout`, `git reset`, `git rebase`, `git merge`, `git cherry-pick`, `git stash`, ETC.**

- Version control, staging (`git add`), commit authoring (`git commit`), remote synchronization (`git push`, `git pull`), branch switching, and conflict resolution are the **exclusive responsibility and authority of the human developer**.
- AI agents must **NEVER** run commands that modify git history, the git index, or the repository working tree state.
- Read-only diagnostics commands such as `git status` or `git diff` are permitted only when strictly necessary to inspect working changes, though standard filesystem inspection is preferred.

---

## 🎯 Project Overview & Mission

**Tachyon** is a modern, refined, cross-platform (Linux, Windows, macOS, Android, iOS), 100% free, and open-source music player built with **Flutter (Dart)**. Its mission is to deliver an uncompromising audio playback experience: an elegant Material 3 interface with dynamic color schemes and pure OLED black mode, native continuous 25ms crossfade, a complete studio-grade DSP audio suite (Bauer Crossfeed bs2b, 10-band graphic EQ, Freeverb algorithmic reverb, stereo spatializer, True-Peak limiter, pitch, and playback speed), an ultra-optimized Minimized Mode with negligible CPU and RAM footprint, an ultra-fast local library backed by an in-memory relational graph, extensible multi-language internationalization (i18n), and synchronized lyrics with intelligent remote API fallback.

---

## 🏛️ Decoupled Architecture: UI Isolate vs. Backend Host Isolate

Tachyon enforces a strict separation of concerns between the visual presentation thread and the background services layer, bridged by an **In-Memory Relational Graph (`LibraryStore`)**:

```raw
┌──────────────────────────────────────────────────────────┐
│                   MAIN ISOLATE (UI)                      │
│  - Material 3 Widgets, Themes, Animations                │
│  - ChangeNotifier Controllers (Library, Playback, etc.)  │
│  - Unified In-Memory Relational Graph (LibraryStore)     │
│  - ZERO duplicate instances (100% Direct Memory Pointers)│
│  - ZERO direct SQLite queries, ZERO audio player FFI     │
│  - ZERO image decoding or ID3 metadata parsing           │
└──────────────────────────┬───────────────────────────────┘
                           │  TachyonBackendClient
                           │  - Startup: getCatalogSnapshot() [Flat DTOs strictly without lyrics]
                           │  - Runtime: RPC Commands & Mutation Events
                           ▼
┌──────────────────────────────────────────────────────────┐
│              CORE BACKEND HOST (ISOLATE)                 │
│  - CoreBackendHost (RPC dispatch & event broadcaster)    │
│  - AppDatabase (Direct SQLite via pure sqlite3 FFI)      │
│  - AudioEngineService (25ms crossfade + miniaudio DSP)   │
│  - MetadataService (Worker Isolate.spawn + haudiotagger) │
│  - MetadataUtils (Lossless PNG LQ/MQ/HQ cover cache)     │
│  - QueueManager (Minimal RAM: active queue & state)      │
│  - LyricsService (On-demand resolution & cache)          │
└──────────────────────────────────────────────────────────┘
```

### 1. Main Isolate (UI Thread)

- **Exclusively visual and reactive:** Renders the user interface, observes state changes, and processes user interactions.
- **In-Memory Relational Graph (`LibraryStore`):**
  - Maintains the entire music catalog in RAM using **direct memory pointers**.
  - If the library has 1,000 tracks and 200 artists, there exist **exactly 1,000 `Track` instances and 200 `Artist` instances**.
  - Multiple tracks by the same artist point to the **exact same memory address** (`identical(trackA.artists[0], trackB.artists[0]) == true`).
  - Instantaneous $O(1)$ navigation: `album.tracks`, `artist.albums`, `artist.tracks`, `track.album?.name`. Zero repeated SQL queries or linear `.where()` searches for standard navigation.
- **Strict UI Isolate Invariants:**
  - **Zero Database Access:** Never instantiate or query `AppDatabase` directly from the UI isolate.
  - **Zero Audio Player FFI:** Do not interact with audio player native handles or FFI bindings in the UI.
  - **Zero Heavy Image/Metadata Processing:** Do not decode raw images with `package:image` or parse audio tags in the UI.
  - **Zero Jank (60/120 FPS):** Keep `build()` methods pure. High-frequency position updates are consumed via `playbackController.positionListenable` (`ValueNotifier<Duration>`) to prevent rebuilding entire widget trees.
- **Backend Communication:** Executed solely through `TachyonBackendClient` (using `TachyonIsolateBackendClient` for production runtime and `DirectTachyonBackendClient` for unit and widget testing).

### 2. Core Backend Host (Service Isolate)

- Runs in a dedicated background isolate (`Isolate.spawn`), centralizing all heavy logic:
  1. **Concise, Centralized SQLite Persistence (`AppDatabase` < 650 lines):** All relational reads and writes execute in this isolate via direct `package:sqlite3` FFI (zero `sqflite`) in transactions. It does not maintain redundant UI view queries (search, sorting, or filtering), which are solved instantly in RAM by `LibraryStore`.
  2. **Low-Level Audio Engine & DSP Suite (`AudioEngineService`):** Coordinates two native audio players via [`miniaudio_player`](https://pub.dev/packages/miniaudio_player) (custom native C FFI wrapper over `miniaudio`, repository: [chomusuke-mk/miniaudio_player](https://github.com/chomusuke-mk/miniaudio_player)) with a 25ms timer ticker for continuous Equal-Power or Linear crossfade. Real-time DSP suite: Bauer Crossfeed (`bs2b` Chu Moy & Default), 10-band graphic EQ, Freeverb algorithmic reverb, stereo spatializer, True-Peak limiter, playback speed, and pitch.
  3. **Unified Metadata Service (`MetadataService`):**
     - Orchestrates audio tag extraction and thumbnail caching via `haudiotagger` and `MetadataUtils`.
     - Executes concurrent folder scanning using a pool of persistent worker isolates (`Isolate.spawn`) proportional to system CPU cores (`Platform.numberOfProcessors`), communicating over ports and cancelable via tokens.
     - **ZERO `Isolate.run`:** Never invoke `Isolate.run` anywhere in the codebase; all concurrency uses managed persistent worker isolates.
     - **Lightweight Transfer Rule:** Isolates transmit only disk paths (`String`) or numerical/text DTOs, **NEVER** large raw byte buffers (`Uint8List`).
  4. **Cover Art & Thumbnail Management (`MetadataUtils`):**
     - Extracts embedded tags via `haudiotagger` or contiguous local files (`cover.jpg`, `folder.jpg`).
     - Generates SHA-256 hashed disk cache in lossless PNG format (`.png`) using Skia native downsampling in three resolutions (`AppDefaults`):
       - **HQ (High Quality):** 800x800 px for _Now Playing_.
       - **MQ (Medium Quality):** 250x250 px for grids and OS media notifications.
       - **LQ (Low Quality):** 50x50 px for dense lists and mosaic tiles.
  5. **Queue Manager (`QueueManager`):** Single source of truth for playback sequence: history, active track, queue, Fisher-Yates shuffle (pinning current track at index 0), un-shuffle (restoring original order), loop modes, and Infinite Library Mix prefetching.
  6. **Lyrics Service (`LyricsService`):** 4-tier on-demand lyrics resolution with persistent SQLite cache, HTTP 429 rate limit management, and multi-language translation.

---

## 🧠 In-Memory Unified Relational Graph

To eradicate memory duplication and reduce code complexity, Tachyon models its entire catalog in the UI Isolate as an in-memory graph:

1. **Instance Uniqueness (100% Direct Pointers):**
   - Each `Track`, `Album`, `Artist`, `Genre`, and `Playlist` exists exactly **ONCE** in memory.
   - Entities reference other entities directly:
     - `track.album` points to the `Album` instance.
     - `track.artists` contains direct references to `List<Artist>`.
     - `album.tracks` contains direct references to `List<Track>`.
     - `artist.albums` and `artist.tracks` contain direct entity lists.
     - `playlistEntry.track` points to the existing `Track` instance.
2. **Lightweight Isolate Transfer (`CatalogSnapshot`):**
   - On startup, the UI Isolate calls `backendClient.getCatalogSnapshot()`.
   - The backend isolate transfers flat relational tables of numbers and base strings (no nesting, no duplicate entities).
   - **STRICT PROHIBITION OF LYRICS IN CATALOG:** `CatalogSnapshot` **NEVER** includes lyrics. Lyrics are queried strictly on-demand when `LyricsView` mounts.
3. **Linear-Time $O(N)$ Hydration (`LibraryStore`):**
   - `LibraryStore` in the UI Isolate reconstructs all bidirectional references in a single $O(N)$ pass.
   - Verified via pointer assertions (`identical(track.album!.tracks.first, track)`).
4. **Instant $O(1)$ Navigation:**
   - The UI never runs SQLite queries or linear `.where()` searches to get tracks for an album or artist; it reads `album.tracks` or `artist.tracks` directly.

---

## 🛑 STRICT MIGRATION RULES & ZERO-REGRESSION POLICY

> [!CAUTION]
> **ZERO-REGRESSION POLICY**
> When fixing compilation errors, warnings, or refactoring screens, AI agents are strictly forbidden from taking shortcuts that revert the domain model to flat string fields.

### 1. Immutability of the Reference-Oriented Domain Model

- **FORBIDDEN:** Reintroducing flat string fields or IDs into domain entities to "quickly fix" errors.
- In `Track`, **NEVER** reintroduce: `String? artist`, `String? album`, `String? albumArtist`, `int? artistId`, `int? albumId`, `List<String> artists`, `List<String> genres`, `String? lyrics`, `String get artistName`, etc.
- In `Album`, **NEVER** reintroduce: `String? artistName`, `int? artistId`.
- In `PlaylistEntry`, **NEVER** duplicate `title`, `artist`, `album`, `durationMs`. Only keep a reference to `Track? track`.

### 2. UI Adapts to the Domain, NEVER Domain to UI (Anti-Reverse-Adaptation)

- If a screen or widget (`tracks_screen.dart`, `album_detail_screen.dart`, `track_tile.dart`, etc.) does not compile because it expected old properties like `track.artistName`, **the screen MUST be refactored** to consume graph references (`track.artists.map((a) => a.name).join(', ')`, `track.album?.name`, `album.tracks`, etc.).
- Modifying a domain class to satisfy an obsolete screen is considered an unacceptable regression.

### 3. Pointer Identity Guarantee (`identical() == true`)

- Any code manipulating catalog entities must preserve shared pointer identity.
- `identical(trackA.artists[0], trackB.artists[0])` must evaluate to `true` if both tracks belong to the same artist.

---

## 🎵 Lyrics Subsystem

### 1. Strict Search Hierarchy

1. **Embedded Lyrics:** Tags extracted by `haudiotagger` (USLT, LYRICS).
2. **Contiguous `.lrc` File:** Local `.lrc` or `.LRC` file located alongside the track (`<filename>.lrc`).
3. **Primary Remote API (`lrclib.net`):** Synchronized and plain-text lyrics via `GET /api/get` (title, artist, album, duration $\pm 2$ s).
4. **Secondary Backup API (`lyrics.ovh`):** Plain-text lyrics without timestamps via `GET https://api.lyrics.ovh/v1/{artist}/{title}`.

### 2. Strictly On-Demand Lifecycle Trigger

- Lyrics resolution is **gated entirely by the rendering lifecycle of `LyricsView`** (when mounted/visible via `_showLyrics == true` in `NowPlayingScreen`).
- `LyricsController` must **never** pre-fetch or search lyrics in the background simply because a track starts playing in standard view (`_showLyrics == false`).
- Rapid-skip safety: If the user skips through multiple tracks quickly, intermediate requests are immediately aborted to process only the destination track.

### 3. Relational SQLite Persistence (`lyrics` and `lyrics_translations`)

- `lyrics`: One row per `(track_id, source)` with `ON DELETE CASCADE`. Sources: `embedded`, `file`, `lrclib`, `lyrics_ovh`.
  - `embedded` is written **only** during folder metadata scanning (`upsertTracks`).
  - `file` mirrors the adjacent `.lrc` on every request.
- `lyrics_translations`: One row per `(lyrics_id, lang)` with `ON DELETE CASCADE`. Updating lyric text purges its translations.
- States per source: `FOUND`, `NOT_FOUND` (cached to avoid re-querying 404s). Transient network or 5xx errors are never persisted.
- **FORBIDDEN:** Reintroducing `tracks.lyrics`, `Track.lyrics`, `keyHash`, `lyrics_cache`, or `lyrics_source_cache`.

### 4. Rate Limiting & HTTP 429 Handling

- **lrclib.net:** Minimum 500ms interval between requests with identifying `User-Agent`.
- **HTTP 429 (`Retry-After`):**
  - If wait time $\le 10$ seconds: Display live countdown banner on screen and retry automatically when the timer expires.
  - If wait time $> 10$ seconds: Fall back immediately to plain-text backup (`lyrics.ovh`).

---

## 🛠️ Feature Implementation Workflow (By Layers)

Follow this bottom-up architectural sequence when adding or modifying features:

### 1. Data Layer (SQLite)

- Modify `AppDatabase` (`lib/core/database/app_database.dart`). Keep it strictly concise (**< 650 lines**).
- Add migrations, indexes, and transactions. Never add UI-specific queries that duplicate `LibraryStore`.

### 2. Backend Services Layer

- Place business logic in `lib/core/backend/services/`.
- Decouple completely from Flutter UI packages and visual widgets.

### 3. Protocol & Client Layer

- Declare RPC command names and event topics in `backend_protocol.dart`.
- Implement handlers in `TachyonBackendHost._dispatch` (`backend_host.dart`).
- Expose methods on `TachyonBackendClient` (`backend_client.dart`) and implement them in `TachyonIsolateBackendClient` and `DirectTachyonBackendClient`.

### 4. Presentation Layer (Controllers & UI)

- **Constructor Invariant:** **DO NOT alter existing controller constructor signatures** in `lib/features/*/presentation/` to avoid breaking dependency injection in `main.dart` or tests.
- Controllers extend `ChangeNotifier` and consume `TachyonBackendClient`.
- For position streaming, subscribe directly to `playbackController.positionListenable` (`ValueNotifier<Duration>`).
- Keep `build()` methods pure: zero disk or network I/O during widget builds.

---

## 🌐 Mandatory Internationalization (i18n)

> [!IMPORTANT]
> **STRICT RULE: ZERO hardcoded strings in widgets, dialogs, screens, tooltips, or user-facing messages.**

1. Register new text first in English canonical fallback: `i18n/en.jsonc`.
2. Add corresponding translation in Spanish: `i18n/es.jsonc`.
3. Add strongly-typed getter in `AppStringKey` (`lib/features/locales/domain/locale.dart`).
4. Register the key in `_allAppStrings` inside `AppStringKey`.
5. Consume reactively in UI:

   ```dart
   context.watch<LocaleController>().localeStrings.<getterName>
   ```

---

## ⚡ Performance, Platforms & Extreme Minimized Mode

1. **Zero External CLI Binaries:**
   - **STRICTLY FORBIDDEN:** Invoking `ffmpeg`, `ffprobe`, or external CLI binaries via `Process.run`.
   - Audio metadata extraction is performed natively via `haudiotagger`.
   - Low-level playback uses [`miniaudio_player`](https://pub.dev/packages/miniaudio_player) via C FFI.

2. **Native Multiplatform & OS Integration:**
   - Multiplatform: Linux, Windows, macOS, Android, iOS.
   - OS Media Transport: Linux MPRIS v2 (`package:dbus`), Windows SMTC (`package:smtc_windows`), Android MediaSession and Foreground Service (`package:audio_service`).
   - OS-agnostic paths normalized via `package:path`.

3. **Extreme Minimized Mode Architecture:**
   - **Native Detection:** GTK3 headerbar minimize button and `window-state-event` on Linux (`my_application.cc`), Win32 hooks on Windows (`flutter_window.cpp`), and `AppLifecycleListener` on Android.
   - **Graphics Suspension & Cache Purge:** Hides `AppBackground`, clears Skia image cache (`PaintingBinding.instance.imageCache.clear()`, `Skia.setResourceCacheMaxBytes(0)`), suspends lyrics and visualizers.
   - **IPC Throttling:** Slows position stream from 25 Hz (40 ms) down to 0.2 Hz (5,000 ms), eliminating 125 unnecessary isolate wakeups every 5 seconds.
   - **Low-Level Memory Trimming (`MemoryOptimizer`):** `malloc_trim(0)` and `madvise` on Linux/Android; `HeapCompact` and `SetProcessWorkingSetSize` on Windows.
   - **Verified Performance:** On Windows during active playback: **< 0.8% CPU and < 10 MB RAM**. On Linux: **0.0% CPU at idle**.

4. **Cover Art & RAM Optimization:**
   - Never retain unconstrained decoded image buffers in memory.
   - Use LQ (50x50 PNG) for lists and mosaics.
   - Use MQ (250x250 PNG) for grids and OS notifications.
   - Use HQ (800x800 PNG) solely for active _Now Playing_.

---

## 🚀 Key CLI Verification Commands

- **Fetch dependencies:**

  ```bash
  flutter pub get
  ```

- **Run static analysis (must remain at 0 errors, 0 warnings at all times):**

  ```bash
  dart analyze .
  ```

- **Run test suites (420+ tests must pass 100%):**

  ```bash
  flutter test
  ```

- **Run application in development mode:**

  ```bash
  flutter run -d linux   # or -d windows, -d android, -d macos
  ```

---

## 📋 Summary of AI Agent Behavioral Rules

1. **PROHIBITION OF GIT MUTATIONS:** Never run `git add`, `git commit`, `git push`, `git pull`, `git checkout`, or any repository-altering commands.
2. **IMAGE CACHE INTEGRITY:** In `MetadataUtils`, extract embedded tags (`haudiotagger`) and maintain the triple PNG disk cache (LQ, MQ, HQ). Never pass byte arrays (`Uint8List`) across isolates.
3. **RESPECT ISOLATE DECOUPLING:** UI interacts with backend solely via `TachyonBackendClient`. Never instantiate `AppDatabase` or audio players in the UI.
4. **TRANSFER PATHS, NOT BYTES:** Isolates communicate with disk paths (`String`) and flat DTOs.
5. **STATIC ANALYSIS & TESTS:** After any change, verify with `dart analyze .` (0 errors, 0 warnings) and validate with `flutter test`.
6. **NO HARDCODED STRINGS (i18n):** Always register keys in `en.jsonc`, `es.jsonc`, and `AppStringKey`.
7. **CONSTRUCTOR INVARIANT:** Never modify constructor signatures of UI controllers in `lib/`.
8. **IN-MEMORY GRAPH (100% POINTERS):** The entire catalog in the UI Isolate operates through `LibraryStore`. Maintain pointer identity (`identical() == true`).
9. **ANTI-REGRESSION POLICY:** Prohibited from reintroducing flat string fields to domain classes. The UI adapts to the Domain, NEVER the Domain to the UI.
10. **ZERO LYRICS IN CATALOG:** `CatalogSnapshot` never includes lyrics. Lyrics are queried strictly on-demand.
11. **CONCISE DATABASE (< 650 LINES):** `AppDatabase` uses direct `package:sqlite3` FFI (zero `sqflite`) for transactional persistence and bulk snapshots. Zero duplicate UI view queries.
