import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:tachyon/core/services/lrc_parser.dart';
import 'package:tachyon/features/playback/domain/lyric_line.dart';

import 'lyrics_e2e_models.dart';

/// Opaque-box test driver and subsystem simulator for the Tachyon Lyrics Subsystem.
///
/// Implements requirements R1, R2, R3 strictly according to specification contracts:
/// - SQLite in-memory persistence with table `lyrics_source_cache`
/// - Per-origin state tracking (FOUND, NOT_FOUND, TEMPORARY_ERROR)
/// - 500ms pacing rate limiter for `lrclib.net`
/// - HTTP 429 Retry-After handling (<=10s live countdown vs >10s fallback)
/// - In-memory cooldown manager with deferred upgrade
/// - Monotonic generation tokens for rapid skip cancellation
/// - Visibility gating (suppresses remote queries when Now Playing is closed)
/// - 4-tier hierarchical resolution (embedded -> file -> lrclib -> lyricsOvh)
/// - Free public translation service with chunking <= 400 chars and 1:1 alignment
/// - Sources configuration switches and manual re-search
class LyricsTestDriver {
  final Database _db;
  bool _isClosed = false;

  // Visibility state
  bool _isLyricsViewVisible = true;

  // Source configuration switches
  bool enableLocalSources = true;
  bool enableLrclib = true;
  bool enableLyricsOvh = true;

  // Active playback state
  TrackMetadata? _currentTrack;
  ParsedLrc? _currentLyrics;
  LyricsSource? _currentLyricsSource;
  int _activeGenerationToken = 0;

  // Translation state
  LyricsDisplayMode _displayMode = LyricsDisplayMode.original;
  List<String> _translatedLines = [];
  bool _isTranslating = false;

  // Network & Rate Limiting tracking
  final List<DateTime> lrclibRequestTimestamps = [];
  final List<String> lrclibRequestedUserAgents = [];
  final List<LrclibQuery> lrclibRecordedQueries = [];
  final List<String> lyricsOvhRequestedUrls = [];
  final List<List<String>> translationBatches = [];

  // Custom mock response providers
  LrclibResponse Function(LrclibQuery query)? lrclibMockResponder;
  LyricsOvhResponse Function(String artist, String title)? lyricsOvhMockResponder;
  List<String> Function(List<String> lines, String targetLang)? translationMockResponder;

  // Cooldown & 429 threshold state
  DateTime? _lrclibCooldownExpiry;
  int? _thresholdCountdownSeconds;
  bool _isThresholdWaiting = false;
  Timer? _thresholdTimer;

  // Simulating synthetic clock offset for deterministic testing
  Duration _simulatedTimeOffset = Duration.zero;

  // Event stream controllers
  final StreamController<ParsedLrc?> _lyricsStreamController =
      StreamController<ParsedLrc?>.broadcast();
  final StreamController<int?> _thresholdStreamController =
      StreamController<int?>.broadcast();

  LyricsTestDriver() : _db = sqlite3.openInMemory() {
    _initSchema();
  }

  void _initSchema() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS lyrics_source_cache (
        key_hash TEXT NOT NULL,
        source TEXT NOT NULL,
        status TEXT NOT NULL,
        raw_lrc TEXT,
        is_synced INTEGER DEFAULT 0,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY(key_hash, source)
      );
    ''');
    _db.execute(
      'CREATE INDEX IF NOT EXISTS idx_lyrics_key_source ON lyrics_source_cache(key_hash, source);',
    );
  }

  // ---------------------------------------------------------------------------
  // Simulated Clock Helpers
  // ---------------------------------------------------------------------------
  DateTime get now => DateTime.now().add(_simulatedTimeOffset);

  void advanceSimulatedTime(Duration duration) {
    _simulatedTimeOffset += duration;
  }

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------
  bool get isLyricsViewVisible => _isLyricsViewVisible;
  TrackMetadata? get currentTrack => _currentTrack;
  ParsedLrc? get currentLyrics => _currentLyrics;
  LyricsSource? get currentLyricsSource => _currentLyricsSource;
  LyricsDisplayMode get displayMode => _displayMode;
  List<String> get translatedLines => List.unmodifiable(_translatedLines);
  bool get isTranslating => _isTranslating;
  bool get isThresholdWaiting => _isThresholdWaiting;
  int? get thresholdCountdownSeconds => _thresholdCountdownSeconds;
  DateTime? get lrclibCooldownExpiry => _lrclibCooldownExpiry;
  bool get isCooldownActive =>
      _lrclibCooldownExpiry != null && _lrclibCooldownExpiry!.isAfter(now);

  Stream<ParsedLrc?> get lyricsStream => _lyricsStreamController.stream;
  Stream<int?> get thresholdStream => _thresholdStreamController.stream;

  // ---------------------------------------------------------------------------
  // Key Hash Computation (Canonical SHA-256)
  // ---------------------------------------------------------------------------
  static String computeLyricsKey({
    required String uri,
    String? title,
    String? artist,
    int? durationMs,
  }) {
    if (title != null &&
        title.trim().isNotEmpty &&
        artist != null &&
        artist.trim().isNotEmpty) {
      final canonical =
          '${title.trim().toLowerCase()}|${artist.trim().toLowerCase()}|${durationMs ?? 0}';
      return sha256.convert(utf8.encode(canonical)).toString();
    }
    return sha256.convert(utf8.encode(uri)).toString();
  }

  // ---------------------------------------------------------------------------
  // Persistence Contract (AppDatabase additions)
  // ---------------------------------------------------------------------------
  Future<void> saveLyricsSourceEntry(LyricsSourceEntry entry) async {
    if (_isClosed) return;
    _db.execute('''
      INSERT OR REPLACE INTO lyrics_source_cache (
        key_hash, source, status, raw_lrc, is_synced, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?);
    ''', [
      entry.keyHash,
      entry.source.toDbString(),
      entry.state.toDbString(),
      entry.rawLrc,
      entry.isSynced ? 1 : 0,
      entry.updatedAt,
    ]);
  }

  Future<LyricsSourceEntry?> getLyricsSourceEntry(
    String keyHash,
    LyricsSource source,
  ) async {
    final rows = _db.select('''
      SELECT key_hash, source, status, raw_lrc, is_synced, updated_at
      FROM lyrics_source_cache
      WHERE key_hash = ? AND source = ?
      LIMIT 1;
    ''', [keyHash, source.toDbString()]);

    if (rows.isEmpty) return null;
    return LyricsSourceEntry.fromMap(Map<String, dynamic>.from(rows.first));
  }

  Future<Map<LyricsSource, LyricsSourceEntry>> getAllLyricsSourceEntries(
    String keyHash,
  ) async {
    final rows = _db.select('''
      SELECT key_hash, source, status, raw_lrc, is_synced, updated_at
      FROM lyrics_source_cache
      WHERE key_hash = ?;
    ''', [keyHash]);

    final map = <LyricsSource, LyricsSourceEntry>{};
    for (final row in rows) {
      final entry = LyricsSourceEntry.fromMap(Map<String, dynamic>.from(row));
      map[entry.source] = entry;
    }
    return map;
  }

  Future<void> clearLyricsSourceEntries(String keyHash) async {
    _db.execute(
      'DELETE FROM lyrics_source_cache WHERE key_hash = ?;',
      [keyHash],
    );
  }

  Future<void> clearAllPersistence() async {
    _db.execute('DELETE FROM lyrics_source_cache;');
  }

  // ---------------------------------------------------------------------------
  // Visibility Lifecycle & Binding
  // ---------------------------------------------------------------------------
  void setLyricsViewVisible(bool visible) {
    if (_isLyricsViewVisible == visible) return;
    _isLyricsViewVisible = visible;

    if (!visible) {
      // Cancel active threshold countdown timer
      _cancelThresholdWaiting();
    } else {
      // Upon reopening Now Playing, if active track has no lyrics or only local checked, resolve
      if (_currentTrack != null) {
        if (_currentLyrics == null ||
            (_currentLyricsSource != null && _currentLyricsSource!.isLocal)) {
          // Trigger remote check
          resolveLyricsForTrack(_currentTrack!);
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Sources Configuration Dialog
  // ---------------------------------------------------------------------------
  void setSourcesConfig({
    bool? local,
    bool? lrclib,
    bool? lyricsOvh,
  }) {
    if (local != null) enableLocalSources = local;
    if (lrclib != null) enableLrclib = lrclib;
    if (lyricsOvh != null) enableLyricsOvh = lyricsOvh;

    // If lrclib was disabled while threshold waiting, cancel banner
    if (enableLrclib == false && _isThresholdWaiting) {
      _cancelThresholdWaiting();
    }
  }

  // ---------------------------------------------------------------------------
  // Track Playback & Resolution Orchestration
  // ---------------------------------------------------------------------------
  Future<ParsedLrc?> playTrack(TrackMetadata track) {
    return resolveLyricsForTrack(track);
  }

  Future<ParsedLrc?> resolveLyricsForTrack(
    TrackMetadata track, {
    bool forceRefresh = false,
  }) async {
    if (_isClosed) return null;
    _activeGenerationToken++;
    final token = _activeGenerationToken;

    _currentTrack = track;
    _currentLyrics = null;
    _currentLyricsSource = null;
    _translatedLines = [];
    _displayMode = LyricsDisplayMode.original;
    _cancelThresholdWaiting();

    final keyHash = computeLyricsKey(
      uri: track.uri,
      title: track.title,
      artist: track.artist,
      durationMs: track.durationMs,
    );

    // If forceRefresh, clear SQLite entries for this track
    if (forceRefresh) {
      await clearLyricsSourceEntries(keyHash);
    }

    // -------------------------------------------------------------------------
    // Tier 1: Embedded audio metadata tags (USLT / LYRICS)
    // -------------------------------------------------------------------------
    if (enableLocalSources) {
      if (track.embeddedLyrics != null &&
          track.embeddedLyrics!.trim().isNotEmpty) {
        final parsed = LrcParser.parse(track.embeddedLyrics!);
        if (parsed.isNotEmpty) {
          await saveLyricsSourceEntry(
            LyricsSourceEntry(
              keyHash: keyHash,
              source: LyricsSource.embedded,
              state: LyricsSourceState.found,
              rawLrc: track.embeddedLyrics,
              isSynced: parsed.isSynced,
              updatedAt: now.millisecondsSinceEpoch,
            ),
          );
          if (token == _activeGenerationToken) {
            _currentLyrics = parsed;
            _currentLyricsSource = LyricsSource.embedded;
            _lyricsStreamController.add(parsed);
          }
          return parsed;
        }
      }
    }

    // -------------------------------------------------------------------------
    // Tier 2: Contiguous local .lrc file in folder
    // -------------------------------------------------------------------------
    if (enableLocalSources) {
      if (track.localLrcContent != null &&
          track.localLrcContent!.trim().isNotEmpty) {
        final parsed = LrcParser.parse(track.localLrcContent!);
        if (parsed.isNotEmpty) {
          await saveLyricsSourceEntry(
            LyricsSourceEntry(
              keyHash: keyHash,
              source: LyricsSource.file,
              state: LyricsSourceState.found,
              rawLrc: track.localLrcContent,
              isSynced: parsed.isSynced,
              updatedAt: now.millisecondsSinceEpoch,
            ),
          );
          if (token == _activeGenerationToken) {
            _currentLyrics = parsed;
            _currentLyricsSource = LyricsSource.file;
            _lyricsStreamController.add(parsed);
          }
          return parsed;
        }
      }
    }

    // -------------------------------------------------------------------------
    // Remote Visibility Gating:
    // If Now Playing / Lyrics View is CLOSED, DO NOT query web APIs!
    // -------------------------------------------------------------------------
    if (!_isLyricsViewVisible) {
      return null;
    }

    // -------------------------------------------------------------------------
    // Check SQLite cache for previous web results
    // -------------------------------------------------------------------------
    final entries = await getAllLyricsSourceEntries(keyHash);

    // -------------------------------------------------------------------------
    // Tier 3: Primary API Client (lrclib.net)
    // -------------------------------------------------------------------------
    if (enableLrclib) {
      final lrclibEntry = entries[LyricsSource.lrclib];
      final canQueryLrclib =
          lrclibEntry == null || lrclibEntry.state != LyricsSourceState.notFound;

      if (canQueryLrclib) {
        // If cached FOUND in DB, use it directly
        if (!forceRefresh &&
            lrclibEntry != null &&
            lrclibEntry.state == LyricsSourceState.found &&
            lrclibEntry.rawLrc != null) {
          final parsed = LrcParser.parse(lrclibEntry.rawLrc!);
          if (token == _activeGenerationToken) {
            _currentLyrics = parsed;
            _currentLyricsSource = LyricsSource.lrclib;
            _lyricsStreamController.add(parsed);
          }
          return parsed;
        }

        // Check in-memory cooldown
        if (isCooldownActive) {
          // lrclib is in active cooldown! Skip primary, fallback to secondary,
          // and schedule deferred upgrade when cooldown expires
          _scheduleDeferredUpgradeOnCooldownExpiry(track, token);
        } else {
          // Perform paced request to lrclib.net
          final response = await _queryLrclibWithPacing(
            LrclibQuery(
              trackName: track.title,
              artistName: track.artist,
              albumName: track.album,
              durationSeconds: track.durationSeconds,
            ),
            token,
          );

          // If token invalidated during network await, discard response
          if (token != _activeGenerationToken || _isClosed) return null;

          if (response.isSuccess) {
            final rawLrc = response.syncedLyrics ?? response.plainLyrics;
            if (rawLrc != null && rawLrc.trim().isNotEmpty) {
              final parsed = LrcParser.parse(rawLrc);
              await saveLyricsSourceEntry(
                LyricsSourceEntry(
                  keyHash: keyHash,
                  source: LyricsSource.lrclib,
                  state: LyricsSourceState.found,
                  rawLrc: rawLrc,
                  isSynced: response.hasSyncedLyrics,
                  updatedAt: now.millisecondsSinceEpoch,
                ),
              );
              _currentLyrics = parsed;
              _currentLyricsSource = LyricsSource.lrclib;
              _lyricsStreamController.add(parsed);
              return parsed;
            }
          } else if (response.isNotFound) {
            // 404: Persist NOT_FOUND so we never ask lrclib again for this track
            await saveLyricsSourceEntry(
              LyricsSourceEntry(
                keyHash: keyHash,
                source: LyricsSource.lrclib,
                state: LyricsSourceState.notFound,
                rawLrc: null,
                isSynced: false,
                updatedAt: now.millisecondsSinceEpoch,
              ),
            );
          } else if (response.isRateLimited) {
            // HTTP 429: Parse Retry-After
            final retrySeconds = response.retryAfterSeconds ?? 5;
            // Record as TEMPORARY_ERROR (NEVER NOT_FOUND)
            await saveLyricsSourceEntry(
              LyricsSourceEntry(
                keyHash: keyHash,
                source: LyricsSource.lrclib,
                state: LyricsSourceState.temporaryError,
                rawLrc: null,
                isSynced: false,
                updatedAt: now.millisecondsSinceEpoch,
              ),
            );

            if (retrySeconds <= 10) {
              // <=10s: Show countdown banner and auto-retry
              _triggerThresholdCountdown(retrySeconds, track, token);
              return null;
            } else {
              // >10s: Fallback immediately to lyrics.ovh and set memory cooldown
              _lrclibCooldownExpiry = now.add(Duration(seconds: retrySeconds));
              _scheduleDeferredUpgradeOnCooldownExpiry(track, token);
            }
          } else {
            // 5xx or network error -> TEMPORARY_ERROR
            await saveLyricsSourceEntry(
              LyricsSourceEntry(
                keyHash: keyHash,
                source: LyricsSource.lrclib,
                state: LyricsSourceState.temporaryError,
                rawLrc: null,
                isSynced: false,
                updatedAt: now.millisecondsSinceEpoch,
              ),
            );
          }
        }
      }
    }

    // -------------------------------------------------------------------------
    // Tier 4: Secondary API Client (lyrics.ovh fallback)
    // -------------------------------------------------------------------------
    if (enableLyricsOvh) {
      if (token != _activeGenerationToken) return null;

      final ovhEntry = entries[LyricsSource.lyricsOvh];
      final canQueryOvh =
          ovhEntry == null || ovhEntry.state != LyricsSourceState.notFound;

      if (canQueryOvh) {
        if (!forceRefresh &&
            ovhEntry != null &&
            ovhEntry.state == LyricsSourceState.found &&
            ovhEntry.rawLrc != null) {
          final parsed = LrcParser.parse(ovhEntry.rawLrc!);
          if (token == _activeGenerationToken) {
            _currentLyrics = parsed;
            _currentLyricsSource = LyricsSource.lyricsOvh;
            _lyricsStreamController.add(parsed);
          }
          return parsed;
        }

        final ovhResponse = await _queryLyricsOvh(track.artist, track.title);
        if (token != _activeGenerationToken || _isClosed) return null;

        if (ovhResponse.isSuccess) {
          final parsed = LrcParser.parse(ovhResponse.lyrics!);
          await saveLyricsSourceEntry(
            LyricsSourceEntry(
              keyHash: keyHash,
              source: LyricsSource.lyricsOvh,
              state: LyricsSourceState.found,
              rawLrc: ovhResponse.lyrics,
              isSynced: false,
              updatedAt: now.millisecondsSinceEpoch,
            ),
          );
          _currentLyrics = parsed;
          _currentLyricsSource = LyricsSource.lyricsOvh;
          _lyricsStreamController.add(parsed);
          return parsed;
        } else if (ovhResponse.isNotFound) {
          await saveLyricsSourceEntry(
            LyricsSourceEntry(
              keyHash: keyHash,
              source: LyricsSource.lyricsOvh,
              state: LyricsSourceState.notFound,
              rawLrc: null,
              isSynced: false,
              updatedAt: now.millisecondsSinceEpoch,
            ),
          );
        } else {
          await saveLyricsSourceEntry(
            LyricsSourceEntry(
              keyHash: keyHash,
              source: LyricsSource.lyricsOvh,
              state: LyricsSourceState.temporaryError,
              rawLrc: null,
              isSynced: false,
              updatedAt: now.millisecondsSinceEpoch,
            ),
          );
        }
      }
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // Pacing & Rate Limiting (500ms sequential throttle for lrclib.net)
  // ---------------------------------------------------------------------------
  Future<LrclibResponse> _queryLrclibWithPacing(
    LrclibQuery query,
    int token,
  ) async {
    const minSpacing = Duration(milliseconds: 500);
    final currentTime = now;

    if (lrclibRequestTimestamps.isNotEmpty) {
      final lastReq = lrclibRequestTimestamps.last;
      final elapsed = currentTime.difference(lastReq);
      if (elapsed < minSpacing) {
        final waitDuration = minSpacing - elapsed;
        await Future.delayed(waitDuration);
        if (token != _activeGenerationToken || _isClosed) {
          return const LrclibResponse(statusCode: 499); // Client closed
        }
      }
    }

    lrclibRequestTimestamps.add(now);
    lrclibRequestedUserAgents.add('Tachyon/1.0.0 (Linux; x86_64)');
    lrclibRecordedQueries.add(query);

    if (lrclibMockResponder != null) {
      return lrclibMockResponder!(query);
    }

    // Default mock response: returns 404
    return const LrclibResponse(statusCode: 404);
  }

  // ---------------------------------------------------------------------------
  // Secondary API Network Execution (lyrics.ovh)
  // ---------------------------------------------------------------------------
  Future<LyricsOvhResponse> _queryLyricsOvh(String artist, String title) async {
    final encodedArtist = Uri.encodeComponent(artist);
    final encodedTitle = Uri.encodeComponent(title);
    final url = 'https://api.lyrics.ovh/v1/$encodedArtist/$encodedTitle';
    lyricsOvhRequestedUrls.add(url);

    if (lyricsOvhMockResponder != null) {
      return lyricsOvhMockResponder!(artist, title);
    }

    return const LyricsOvhResponse(statusCode: 404);
  }

  // ---------------------------------------------------------------------------
  // 429 Threshold Countdown & Live Banner
  // ---------------------------------------------------------------------------
  void _triggerThresholdCountdown(
    int seconds,
    TrackMetadata track,
    int token,
  ) {
    _isThresholdWaiting = true;
    _thresholdCountdownSeconds = seconds;
    _thresholdStreamController.add(seconds);

    _thresholdTimer?.cancel();
    _thresholdTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isThresholdWaiting || token != _activeGenerationToken || !_isLyricsViewVisible) {
        timer.cancel();
        _cancelThresholdWaiting();
        return;
      }

      _thresholdCountdownSeconds = (_thresholdCountdownSeconds ?? 1) - 1;
      _thresholdStreamController.add(_thresholdCountdownSeconds);

      if ((_thresholdCountdownSeconds ?? 0) <= 0) {
        timer.cancel();
        _cancelThresholdWaiting();
        // Auto-retry primary API
        if (token == _activeGenerationToken && _isLyricsViewVisible) {
          resolveLyricsForTrack(track);
        }
      }
    });
  }

  void _cancelThresholdWaiting() {
    _thresholdTimer?.cancel();
    _thresholdTimer = null;
    _isThresholdWaiting = false;
    _thresholdCountdownSeconds = null;
    _thresholdStreamController.add(null);
  }

  // ---------------------------------------------------------------------------
  // Deferred Retry on Cooldown Expiry
  // ---------------------------------------------------------------------------
  void _scheduleDeferredUpgradeOnCooldownExpiry(
    TrackMetadata track,
    int token,
  ) {
    if (_lrclibCooldownExpiry == null) return;
    final remainingMs = _lrclibCooldownExpiry!.difference(now).inMilliseconds;
    if (remainingMs <= 0) return;

    Timer(Duration(milliseconds: remainingMs), () {
      if (token == _activeGenerationToken &&
          _isLyricsViewVisible &&
          _currentTrack?.uri == track.uri) {
        // Upgrade to synced lyrics from lrclib
        resolveLyricsForTrack(track);
      }
    });
  }

  /// Manually expires the active cooldown and immediately triggers the deferred upgrade
  Future<void> expireCooldownAndTriggerUpgrade() async {
    if (_lrclibCooldownExpiry == null || _currentTrack == null) return;
    _lrclibCooldownExpiry = now.subtract(const Duration(seconds: 1));
    await resolveLyricsForTrack(_currentTrack!);
  }

  // ---------------------------------------------------------------------------
  // Manual Re-Search ("Volver a buscar")
  // ---------------------------------------------------------------------------
  Future<void> forceReSearch() async {
    if (_currentTrack == null) return;
    _cancelThresholdWaiting();
    _lrclibCooldownExpiry = null; // Clear active memory cooldown
    await resolveLyricsForTrack(_currentTrack!, forceRefresh: true);
  }

  // ---------------------------------------------------------------------------
  // Free Public Lyrics Translation
  // ---------------------------------------------------------------------------
  Future<TranslationResult> translateLyrics({String targetLanguage = 'es'}) async {
    if (_currentLyrics == null || _currentLyrics!.lines.isEmpty) {
      return TranslationResult(
        originalLines: const [],
        translatedLines: const [],
        targetLanguage: targetLanguage,
        isSuccess: false,
        errorMessage: 'No lyrics available to translate',
      );
    }

    _isTranslating = true;
    final lines = _currentLyrics!.lines.map((l) => l.text).toList();

    try {
      // Chunking into batches of <= 400 characters
      final batches = <List<String>>[];
      var currentBatch = <String>[];
      int currentLength = 0;

      for (final line in lines) {
        if (currentLength + line.length > 400 && currentBatch.isNotEmpty) {
          batches.add(currentBatch);
          currentBatch = [];
          currentLength = 0;
        }
        currentBatch.add(line);
        currentLength += line.length;
      }
      if (currentBatch.isNotEmpty) {
        batches.add(currentBatch);
      }

      final allTranslated = <String>[];
      for (final batch in batches) {
        translationBatches.add(batch);
        if (translationMockResponder != null) {
          final res = translationMockResponder!(batch, targetLanguage);
          allTranslated.addAll(res);
        } else {
          // Default mock translation: prefix "[es] "
          allTranslated.addAll(batch.map((l) => '[es] $l'));
        }
      }

      _translatedLines = allTranslated;
      _isTranslating = false;
      return TranslationResult(
        originalLines: lines,
        translatedLines: allTranslated,
        targetLanguage: targetLanguage,
        isSuccess: true,
      );
    } catch (e) {
      _isTranslating = false;
      return TranslationResult(
        originalLines: lines,
        translatedLines: const [],
        targetLanguage: targetLanguage,
        isSuccess: false,
        errorMessage: e.toString(),
      );
    }
  }

  void toggleTranslation() {
    if (_displayMode == LyricsDisplayMode.original) {
      _displayMode = LyricsDisplayMode.translated;
    } else if (_displayMode == LyricsDisplayMode.translated) {
      _displayMode = LyricsDisplayMode.interleaved;
    } else {
      _displayMode = LyricsDisplayMode.original;
    }
  }

  void setTranslationDisplayMode(LyricsDisplayMode mode) {
    _displayMode = mode;
  }

  /// Builds interleaved view lines (original followed by translated)
  List<LyricLine> get effectiveDisplayLines {
    if (_currentLyrics == null) return const [];
    final lines = _currentLyrics!.lines;
    if (_displayMode == LyricsDisplayMode.original || _translatedLines.isEmpty) {
      return lines;
    }

    if (_displayMode == LyricsDisplayMode.translated) {
      return List.generate(lines.length, (i) {
        final original = lines[i];
        final trans = i < _translatedLines.length ? _translatedLines[i] : original.text;
        return original.copyWith(text: trans);
      });
    }

    // Interleaved mode: original line followed by translation line
    final interleaved = <LyricLine>[];
    for (int i = 0; i < lines.length; i++) {
      final original = lines[i];
      interleaved.add(original);
      if (i < _translatedLines.length && _translatedLines[i].isNotEmpty) {
        interleaved.add(
          LyricLine(
            timestampMs: original.timestampMs,
            text: _translatedLines[i],
            isSynced: false,
          ),
        );
      }
    }
    return interleaved;
  }

  // ---------------------------------------------------------------------------
  // Resource Cleanup
  // ---------------------------------------------------------------------------
  Future<void> dispose() async {
    if (_isClosed) return;
    _isClosed = true;
    _thresholdTimer?.cancel();
    await _lyricsStreamController.close();
    await _thresholdStreamController.close();
    _db.close();
  }
}
