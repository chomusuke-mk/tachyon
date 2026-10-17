<p align="center">
 <img src="assets/icon/icon.webp" alt="Tachyon" width="256" />
</p>
<h1 align="center">Tachyon Music Player 🎵⚡</h1>

**Tachyon** is a modern, refined, lightweight, and 100% free open-source cross-platform (Linux, Windows, macOS, Android, iOS) music player built with **Flutter (Dart)**. Engineered with a high-performance decoupled architecture (**UI Isolate vs. Backend Host Isolate**), a low-latency native audio engine delivering **continuous 25ms real crossfade**, a complete suite of **studio-grade DSP audio effects**, ultra-fast background library scanning with zero external CLI dependencies, and an intelligent synchronized lyrics subsystem with automatic fallback to remote APIs.

---

## ✨ Key Features

### 🎧 High-Fidelity Audio Engine & Studio DSP Suite

- **Custom Native C/FFI Audio Engine ([`miniaudio_player`](https://pub.dev/packages/miniaudio_player)):** Purpose-built companion library for Tachyon ([GitHub](https://github.com/chomusuke-mk/miniaudio_player)), embedding `miniaudio` via FFI for native sample-level control, zero overhead, and ultra-low latency.
- **Continuous 25ms Real Crossfade:** Seamless audio transitions between consecutive songs with customizable duration (up to 20s auto, 5s manual) using _Equal-Power_ or _Linear_ volume curves powered by an autonomous 25ms high-precision ticker.
- **True Gapless Playback:** Instant track transitions with zero clicks, pops, or silence.
- **Bauer Crossfeed (`bs2b`):** Acoustic speaker simulation for headphones (_Chu Moy_ 700Hz/6dB and _Default_ 700Hz/4.5dB profiles) engineered to eliminate headphone listening fatigue.
- **10-Band Graphic Equalizer:** Precision tonal shaping with genre presets (Rock, Pop, Jazz, Classical, Bass Boost) and manual band calibration (-24 dB to +24 dB).
- **Stereo Spatializer:** Dynamic stereo field expansion and narrowing (0.0x to 2.0x width).
- **Algorithmic Reverb (_Freeverb_):** Acoustic space processor with presets (_Small Room_, _Studio_, _Concert Hall_, _Cathedral_, _Plate_, _Ambient_) and fine-tuned control over _Room Size_, _Damping_, _Width_, and _Wet/Dry_ mix.
- **True-Peak Limiter:** Active distortion and clipping prevention at elevated volume levels.
- **Pitch, Speed & Volume Controls:** Independent playback rate (0.5x–1.5x) and pitch shifting (-12 to +12 semitones), ReplayGain volume normalization, stereo balance, mono downmix, preamp, and volume boost up to 200%.
- **Advanced Queue Management:** Loop modes (`Off`, `One`, `All`), Fisher-Yates shuffle pinning the active track at index 0, un-shuffle restoring the exact original order, and dynamic queue insertion (_Play Next_ / _Add to Queue_).
- **Infinite Library Mix:** Proactive background track prefetching that keeps playback flowing infinitely with random library tracks when the active queue finishes.

### ⚡ Extreme Performance & Minimized Mode

- **Decoupled Dual-Isolate Architecture:** The visual Flutter thread (UI Isolate) is dedicated exclusively to rendering 60/120 FPS fluid animations (_zero jank_), while a dedicated background isolate (`CoreBackendHost`) centralizes SQLite persistence, audio engine orchestration, and metadata processing.
- **Unified In-Memory Graph (`LibraryStore`):** Entire music catalog hydrated in linear $O(N)$ time into RAM with 100% direct memory pointer identity. Instantaneous $O(1)$ navigation (`album.tracks`, `artist.albums`, `track.album?.name`) with zero redundant SQL lookups.
- **Native Minimized Mode:** Automatic detection across Linux (GTK headerbar minimize button and `window-state-event`), Windows (Win32 window message hooks), and Android (`AppLifecycleListener`):
  - Suspends complex visual layers (`AppBackground`) and visualizers.
  - Purges Skia and GPU texture caches (`PaintingBinding.instance.imageCache.clear()`, `Skia.setResourceCacheMaxBytes(0)`).
  - Throttles IPC position stream from 25 Hz (40 ms) down to 0.2 Hz (5,000 ms), eliminating 125 CPU wakeups every 5 seconds.
  - Reclaims physical memory via low-level native hooks (`malloc_trim` and `madvise` on Linux/Android; `HeapCompact` and `SetProcessWorkingSetSize` on Windows).
  - Verified performance: **< 0.8% CPU and < 10 MB RAM** on Windows during active playback; **0.0% CPU at idle** on Linux.

### ⚡ 100% Native Metadata Extraction (Zero External FFmpeg)

- **Zero CLI Dependencies:** Does not require `ffmpeg` or `ffprobe` installed on the host system.
- **Concurrent Isolate Pool (`Isolate.spawn`):** Recursive tag scanning (ID3v1, ID3v2, FLAC Vorbis, MP4/M4A, OGG) via `haudiotagger` distributed across persistent worker isolates proportional to CPU cores (`Platform.numberOfProcessors`), cancelable instantly via scan tokens.
- **Triple-Resolution PNG Cover Cache (`MetadataUtils`):** Lossless PNG format with native Skia compression cached by SHA-256 hash:
  - **HQ (800x800):** Now Playing view.
  - **MQ (250x250):** Grid views and OS system notifications.
  - **LQ (50x50):** Dense track rows and mosaic covers.

### 📜 Intelligent Synchronized Lyrics Subsystem

- **4-Tier Search Hierarchy:**
  1. Embedded audio file tags (USLT/LYRICS).
  2. Contiguous local `.lrc` / `.LRC` files.
  3. Primary API: **`lrclib.net`** (synchronized & plain text, duration match $\pm 2$ s).
  4. Secondary Backup API: **`lyrics.ovh`** (plain text fallback).
- **Strictly On-Demand:** Remote queries only trigger when the lyrics view is mounted or made visible (`_showLyrics == true`).
- **Real-Time $O(\log n)$ Syncing:** Smooth auto-scrolling with interactive tap-to-seek.
- **Defensive API Rate Limiting:**
  - 500ms request spacing and identifying `User-Agent`.
  - HTTP 429 (`Retry-After`) handling: live countdown with automatic retry for $\le 10$s, instant fallback to plain text for $> 10$s.
  - Immediate cancellation of intermediate requests when rapidly skipping tracks in the queue.
- **Multi-Language Translation:** Two-phase translation caching with relational SQLite persistence (`lyrics_translations`).

### 🎨 Design, UX & Native OS Integration

- **Adaptive Material 3:** `NavigationRail` on desktop (>=720dp) and `NavigationBar` on mobile, bottom transport bar, persistent mini-player, and comprehensive desktop keyboard shortcuts (Space for play/pause, 0–9 for percentage seek, ESC / Alt+Left to navigate back).
- **Dynamic Color Schemes & OLED Pure Black:** Surface tone hierarchy supporting light, dark, and true OLED black modes.
- **Operating System Media Transport:**
  - **Linux:** Native MPRIS v2 over D-Bus (`package:dbus`).
  - **Windows:** System Media Transport Controls over WinRT SMTC (`package:smtc_windows`).
  - **Android:** Foreground Service with interactive notifications and lock screen media controls (`package:audio_service`).
- **Complete Internationalization (i18n):** Zero hardcoded strings. Dynamic JSONC dictionaries (`i18n/*.jsonc`), English canonical fallback, live runtime locale switching, and automated translation tools (`tools/auto_translate_locales.py`).

---

## 🏗️ Architecture & Technology Stack

| Layer                    | Technologies                                                            | Description                                                                                                          |
| ------------------------ | ----------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| **UI & Presentation**    | Flutter (Material 3), `provider`                                        | Responsive shell, adaptive navigation, virtualized lists, immersive Now Playing, waveform slider                     |
| **State Management**     | `ChangeNotifier`, `Provider`                                            | Decoupled reactive controllers (`PlaybackController`, `LibraryController`, `LyricsController`, `SettingsController`) |
| **In-Memory Graph**      | `LibraryStore` (Pure Dart)                                              | Unified catalog with direct memory pointers ($O(1)$) and pointer identity guarantees                                 |
| **Audio Engine**         | [`miniaudio_player`](https://pub.dev/packages/miniaudio_player) (C FFI) | Native audio engine companion built for Tachyon with 25ms dual crossfade ticker and real-time DSP                    |
| **DSP Suite**            | `miniaudio` DSP filters                                                 | Bauer crossfeed (bs2b), 10-band EQ, Freeverb reverb, stereo spatializer, limiter, speed, and pitch                   |
| **Metadata & Tags**      | `haudiotagger`, Dart `Isolate.spawn`                                    | Concurrent native metadata extraction without external CLI binaries or subprocesses                                  |
| **Persistence**          | Direct `sqlite3` FFI, `shared_preferences`                              | Transactional relational database (B-Tree indexes, WAL mode, `PRAGMA shrink_memory`)                                 |
| **OS Media Integration** | `audio_service`, `smtc_windows`, `dbus`                                 | Native system transport controls on Linux (MPRIS), Windows (SMTC), and Android (MediaSession)                        |
| **Lyrics Subsystem**     | `http`, Relational SQLite                                               | Defensive client for LRCLIB and Lyrics.ovh, $O(\log n)$ line syncing, cached translations                            |
| **Internationalization** | `jsonc`, `AppStringKey`, `LocaleController`                             | Reactive JSONC dictionary engine with English fallback and hot-reloading                                             |

For in-depth architectural and developer documentation:

- 📖 [AGENTS.md](AGENTS.md): Developer standards, AI agent guidelines, and anti-regression policies.
- 📐 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): Comprehensive architectural specification and subsystem breakdown.
- 📊 [docs/PERFORMANCE.md](docs/PERFORMANCE.md): Complete performance audit, heap profile, and memory benchmarks.

---

## 🚀 Quick Start & Development

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart 3.x+)
- Native desktop toolchains:
  - **Linux:** `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`
  - **Windows:** Visual Studio with C++ Desktop Development workload
  - **macOS:** Xcode and Command Line Tools

### Execution Commands

```bash
# 1. Fetch dependencies
flutter pub get

# 2. Verify static analysis (0 errors, 0 warnings required)
dart analyze .

# 3. Run test suite (420+ automated tests)
flutter test

# 4. Launch application in development mode
flutter run -d linux      # Linux Desktop
flutter run -d windows    # Windows Desktop
flutter run -d macos      # macOS Desktop
flutter run -d android    # Android Device / Emulator
```

---

## 📄 License

This project is licensed under the terms of the [GNU General Public License v3.0](LICENSE).
