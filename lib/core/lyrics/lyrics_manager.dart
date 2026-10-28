import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/lyrics/domain/lyric_source.dart';
import 'package:tachyon/core/lyrics/lrc_parser.dart';
import 'package:tachyon/core/lyrics/lrclib_client.dart';
import 'package:tachyon/core/lyrics/lyrics_ovh_client.dart';
import 'package:tachyon/core/lyrics/lyrics_rate_limiter.dart';
import 'package:tachyon/core/lyrics/lyrics_translation_client.dart';
import 'package:tachyon/core/store/domain/track.dart';
import 'package:tachyon/core/store/library_store.dart';

/// Result of an on-demand lyrics resolution request.
class LyricsResult {
  final ParsedLrc lrc;
  final String? rawLrc;
  final LyricsSource? source;
  final int? lyricsId;

  /// True when `lrclib.net` returned HTTP 429 with `Retry-After <= 10s` and
  /// a live countdown + automatic retry is currently scheduled.
  final bool isThresholdWaiting;
  final int? retryAfterSeconds;

  /// True if the request was superseded/aborted by a newer request.
  final bool isCancelled;

  const LyricsResult({
    required this.lrc,
    this.rawLrc,
    this.source,
    this.lyricsId,
    this.isThresholdWaiting = false,
    this.retryAfterSeconds,
    this.isCancelled = false,
  });

  static final LyricsResult empty = LyricsResult(lrc: ParsedLrc.empty());
  static final LyricsResult cancelled = LyricsResult(
    lrc: ParsedLrc.empty(),
    isCancelled: true,
  );

  bool get isEmpty => lrc.isEmpty;
  bool get isNotEmpty => lrc.isNotEmpty;
  bool get isSynced => lrc.isSynced;
}

class _PersistedLyricsRow {
  final int id;
  final LyricsSource source;
  final LyricsSourceState state;
  final String? rawLrc;
  final bool isSynced;

  const _PersistedLyricsRow({
    required this.id,
    required this.source,
    required this.state,
    this.rawLrc,
    required this.isSynced,
  });
}

/// Pure on-demand service (Block 6: `Lyrics`) that delivers lyrics and
/// translations when requested by `trackId`.
///
/// Does NOT store UI state, active track, visibility flags, or playback
/// position synchronization. Resolves track metadata in $O(1)$ from
/// [LibraryStore] and persists/queries cached lyrics in [AppDatabase].
class LyricsManager {
  final AppDatabase database;
  final LibraryStore store;
  final LrclibClient _lrclibClient;
  final LyricsOvhClient _ovhClient;
  final LyricsTranslationClient _translationClient;
  final LyricsCooldownManager cooldownManager;
  final Duration debounceDuration;

  final LyricsGenerationTracker _generationTracker = LyricsGenerationTracker();
  final Map<int, Future<LyricsResult>> _inFlight = {};
  LyricsCancellationToken? _translationToken;
  Timer? _debounceTimer;
  Completer<LyricsResult>? _pendingDebounceCompleter;

  LyricsManager({
    required this.database,
    LibraryStore? store,
    LrclibClient? lrclibClient,
    LyricsOvhClient? ovhClient,
    LyricsTranslationClient? translationClient,
    LyricsCooldownManager? cooldownManager,
    this.debounceDuration = const Duration(milliseconds: 300),
  }) : store = store ?? LibraryStore(database),
       _lrclibClient = lrclibClient ?? LrclibClient(),
       _ovhClient = ovhClient ?? LyricsOvhClient(),
       _translationClient = translationClient ?? LyricsTranslationClient(),
       cooldownManager = cooldownManager ?? LyricsCooldownManager();

  bool get isThresholdWaiting => cooldownManager.isThresholdWaiting;
  int? get thresholdCountdownSeconds =>
      cooldownManager.thresholdCountdownSeconds;
  Stream<int?> get thresholdStream => cooldownManager.thresholdStream;

  /// Cancels any pending debounce timer, in-flight network requests, and
  /// rate-limit countdowns.
  void cancelPending() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    if (_pendingDebounceCompleter != null &&
        !_pendingDebounceCompleter!.isCompleted) {
      _pendingDebounceCompleter!.complete(LyricsResult.cancelled);
    }
    _pendingDebounceCompleter = null;
    _generationTracker.cancelCurrent();
    _translationToken?.cancel();
    _translationToken = null;
    cooldownManager.cancelThresholdCountdown();
    cooldownManager.cancelDeferredRetry();
  }

  /// Resolves lyrics for [trackId] (looking up track metadata in $O(1)$ from
  /// [store], or using [track] if provided directly).
  ///
  /// Rapid consecutive calls within [debounceDuration] automatically cancel
  /// earlier calls so only the final destination track is queried.
  Future<LyricsResult> getLyrics(
    int trackId, {
    Track? track,
    bool enableLocal = true,
    bool enableLrclib = true,
    bool enableLyricsOvh = true,
    bool forceRefresh = false,
    Duration? debounceOverride,
    LyricsCancellationToken? cancellationToken,
    void Function(LyricsResult retryResult)? onThresholdRetryResolved,
  }) async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    if (_pendingDebounceCompleter != null &&
        !_pendingDebounceCompleter!.isCompleted) {
      _pendingDebounceCompleter!.complete(LyricsResult.cancelled);
    }
    _pendingDebounceCompleter = null;
    cooldownManager.cancelDeferredRetry();

    final token = cancellationToken ?? _generationTracker.nextGeneration();
    final effectiveDebounce = debounceOverride ?? debounceDuration;

    if (!forceRefresh && effectiveDebounce > Duration.zero) {
      final completer = Completer<LyricsResult>();
      _pendingDebounceCompleter = completer;
      _debounceTimer = Timer(effectiveDebounce, () async {
        _debounceTimer = null;
        _pendingDebounceCompleter = null;
        if (token.isCancelled) {
          if (!completer.isCompleted) {
            completer.complete(LyricsResult.cancelled);
          }
          return;
        }
        try {
          final result = await _resolveLyricsInternal(
            trackId: trackId,
            track: track,
            enableLocal: enableLocal,
            enableLrclib: enableLrclib,
            enableLyricsOvh: enableLyricsOvh,
            forceRefresh: forceRefresh,
            token: token,
            onThresholdRetryResolved: onThresholdRetryResolved,
          );
          if (!completer.isCompleted) {
            completer.complete(result);
          }
        } catch (e, st) {
          if (!completer.isCompleted) {
            completer.completeError(e, st);
          }
        }
      });
      return completer.future;
    }

    return _resolveLyricsInternal(
      trackId: trackId,
      track: track,
      enableLocal: enableLocal,
      enableLrclib: enableLrclib,
      enableLyricsOvh: enableLyricsOvh,
      forceRefresh: forceRefresh,
      token: token,
      onThresholdRetryResolved: onThresholdRetryResolved,
    );
  }

  Future<LyricsResult> _resolveLyricsInternal({
    required int trackId,
    Track? track,
    required bool enableLocal,
    required bool enableLrclib,
    required bool enableLyricsOvh,
    required bool forceRefresh,
    required LyricsCancellationToken token,
    void Function(LyricsResult retryResult)? onThresholdRetryResolved,
  }) async {
    if (token.isCancelled) return LyricsResult.cancelled;

    final resolvedTrack = track ?? store.getTrackById(trackId);
    final filePath = resolvedTrack?.filePath ?? '';
    final title = resolvedTrack?.title ?? '';
    final artist = resolvedTrack != null
        ? resolvedTrack.artists.firstOrNull?.name ?? ''
        : '';
    final album = resolvedTrack?.album?.name;
    final durationSeconds = resolvedTrack != null && resolvedTrack.durationMs > 0
        ? (resolvedTrack.durationMs / 1000).round()
        : null;

    return getLyricsForTrack(
      trackId: trackId,
      filePath: filePath,
      title: title,
      artist: artist,
      album: album,
      durationSeconds: durationSeconds,
      enableLocal: enableLocal,
      enableLrclib: enableLrclib,
      enableLyricsOvh: enableLyricsOvh,
      forceRefresh: forceRefresh,
      cancellationToken: token,
      onThresholdRetryResolved: onThresholdRetryResolved,
    );
  }

  /// Resolves lyrics for the given track parameters using a single unified
  /// SQLite query for cached sources and following the 4-tier hierarchy:
  /// 1. `embedded` -> 2. `file` (`.lrc`) -> 3. `lrclib` -> 4. `lyrics_ovh`.
  Future<LyricsResult> getLyricsForTrack({
    required int? trackId,
    required String filePath,
    required String title,
    required String artist,
    String? album,
    int? durationSeconds,
    bool enableLocal = true,
    bool enableLrclib = true,
    bool enableLyricsOvh = true,
    bool forceRefresh = false,
    LyricsCancellationToken? cancellationToken,
    void Function(LyricsResult retryResult)? onThresholdRetryResolved,
  }) {
    if (trackId != null && !forceRefresh && cancellationToken == null) {
      final existing = _inFlight[trackId];
      if (existing != null) return existing;
      final future = _getLyricsForTrackImpl(
        trackId: trackId,
        filePath: filePath,
        title: title,
        artist: artist,
        album: album,
        durationSeconds: durationSeconds,
        enableLocal: enableLocal,
        enableLrclib: enableLrclib,
        enableLyricsOvh: enableLyricsOvh,
        forceRefresh: forceRefresh,
        cancellationToken: cancellationToken,
        onThresholdRetryResolved: onThresholdRetryResolved,
      );
      _inFlight[trackId] = future;
      return future.whenComplete(() {
        if (identical(_inFlight[trackId], future)) {
          _inFlight.remove(trackId);
        }
      });
    }
    return _getLyricsForTrackImpl(
      trackId: trackId,
      filePath: filePath,
      title: title,
      artist: artist,
      album: album,
      durationSeconds: durationSeconds,
      enableLocal: enableLocal,
      enableLrclib: enableLrclib,
      enableLyricsOvh: enableLyricsOvh,
      forceRefresh: forceRefresh,
      cancellationToken: cancellationToken,
      onThresholdRetryResolved: onThresholdRetryResolved,
    );
  }

  Future<LyricsResult> _getLyricsForTrackImpl({
    required int? trackId,
    required String filePath,
    required String title,
    required String artist,
    String? album,
    int? durationSeconds,
    required bool enableLocal,
    required bool enableLrclib,
    required bool enableLyricsOvh,
    required bool forceRefresh,
    LyricsCancellationToken? cancellationToken,
    void Function(LyricsResult retryResult)? onThresholdRetryResolved,
  }) async {
    bool isCancelled() => cancellationToken?.isCancelled ?? false;

    if (isCancelled()) return LyricsResult.cancelled;

    // Fetch all persisted lyrics rows for this track in 1 query.
    final Map<LyricsSource, _PersistedLyricsRow> persistedBySource = {};
    if (trackId != null) {
      final rows = await database.getLyricsForTrack(trackId);
      if (isCancelled()) return LyricsResult.cancelled;
      for (final r in rows) {
        try {
          final src = LyricsSource.fromDbString(r['source'] as String);
          final st = LyricsSourceState.fromDbString(r['state'] as String);
          persistedBySource[src] = _PersistedLyricsRow(
            id: r['id'] as int,
            source: src,
            state: st,
            rawLrc: r['raw_lrc'] as String?,
            isSynced: (r['is_synced'] as int? ?? 0) != 0,
          );
        } catch (_) {}
      }
    }

    // -------------------------------------------------------------------------
    // 1 & 2. Local Sources (`embedded` and `file`)
    // -------------------------------------------------------------------------
    if (enableLocal) {
      // 1. Embedded lyrics (saved during metadata scan in `upsertTracks`).
      if (trackId != null) {
        final embeddedRow = persistedBySource[LyricsSource.embedded];
        if (embeddedRow != null &&
            embeddedRow.state == LyricsSourceState.found) {
          final parsed = _parseRow(embeddedRow);
          if (parsed.isNotEmpty) {
            return LyricsResult(
              lrc: parsed,
              rawLrc: embeddedRow.rawLrc,
              source: LyricsSource.embedded,
              lyricsId: embeddedRow.id,
            );
          }
        }
      }

      if (isCancelled()) return LyricsResult.cancelled;

      // 2. Contiguous `.lrc` file on disk (always mirrored to SQLite).
      if (filePath.isNotEmpty) {
        final diskLrcRaw = await _readLocalLrcFileRaw(filePath);
        if (isCancelled()) return LyricsResult.cancelled;

        if (diskLrcRaw != null && diskLrcRaw.trim().isNotEmpty) {
          final parsed = LrcParser.parse(diskLrcRaw);
          if (parsed.isNotEmpty) {
            int? lyricsId;
            if (trackId != null) {
              lyricsId = await database.saveLyricsEntry(
                trackId: trackId,
                source: LyricsSource.file.dbValue,
                state: LyricsSourceState.found.dbValue,
                rawLrc: diskLrcRaw,
                isSynced: parsed.isSynced,
              );
            }
            return LyricsResult(
              lrc: parsed,
              rawLrc: diskLrcRaw,
              source: LyricsSource.file,
              lyricsId: lyricsId,
            );
          }
        }

        // File missing or empty on disk -> delete any stale `file` row in DB.
        final existingFileRow = persistedBySource[LyricsSource.file];
        if (trackId != null && existingFileRow != null) {
          await database.deleteLyrics(existingFileRow.id);
        }
      }
    }

    if (isCancelled()) return LyricsResult.cancelled;

    // -------------------------------------------------------------------------
    // 3. Primary Remote API: lrclib.net
    // -------------------------------------------------------------------------
    if (enableLrclib && title.trim().isNotEmpty) {
      final lrclibRow = persistedBySource[LyricsSource.lrclib];
      final hasExistingFound =
          lrclibRow != null && lrclibRow.state == LyricsSourceState.found;

      if (!forceRefresh && lrclibRow != null) {
        if (hasExistingFound) {
          final parsed = _parseRow(lrclibRow);
          if (parsed.isNotEmpty) {
            return LyricsResult(
              lrc: parsed,
              rawLrc: lrclibRow.rawLrc,
              source: LyricsSource.lrclib,
              lyricsId: lrclibRow.id,
            );
          }
        }
        // State is NOT_FOUND -> skip querying lrclib.net unless forceRefresh.
      } else {
        if (!cooldownManager.isCooldownActive) {
          final lrclibResult = await _fetchFromLrclibAndPersist(
            trackId: trackId,
            title: title,
            artist: artist,
            album: album,
            durationSeconds: durationSeconds,
            cancellationToken: cancellationToken,
            onThresholdRetryResolved: onThresholdRetryResolved,
            enableLyricsOvhFallback: enableLyricsOvh,
            preserveExistingFound: hasExistingFound,
            existingId: hasExistingFound ? lrclibRow.id : null,
            existingRawLrc: hasExistingFound ? lrclibRow.rawLrc : null,
          );
          if (isCancelled()) return LyricsResult.cancelled;
          if (lrclibResult != null) {
            return lrclibResult;
          }
        }
        if (hasExistingFound) {
          final parsed = _parseRow(lrclibRow);
          if (parsed.isNotEmpty) {
            return LyricsResult(
              lrc: parsed,
              rawLrc: lrclibRow.rawLrc,
              source: LyricsSource.lrclib,
              lyricsId: lrclibRow.id,
            );
          }
        }
      }
    }

    if (isCancelled()) return LyricsResult.cancelled;

    // -------------------------------------------------------------------------
    // 4. Secondary Backup API: lyrics.ovh (plain text)
    // -------------------------------------------------------------------------
    if (enableLyricsOvh &&
        title.trim().isNotEmpty &&
        artist.trim().isNotEmpty) {
      final ovhRow = persistedBySource[LyricsSource.lyricsOvh];
      final hasExistingFound =
          ovhRow != null && ovhRow.state == LyricsSourceState.found;

      if (!forceRefresh && ovhRow != null) {
        if (hasExistingFound) {
          final parsed = _parseRow(ovhRow);
          if (parsed.isNotEmpty) {
            return LyricsResult(
              lrc: parsed,
              rawLrc: ovhRow.rawLrc,
              source: LyricsSource.lyricsOvh,
              lyricsId: ovhRow.id,
            );
          }
        }
      } else {
        final ovhResult = await _fetchFromOvhAndPersist(
          trackId: trackId,
          artist: artist,
          title: title,
          cancellationToken: cancellationToken,
          preserveExistingFound: hasExistingFound,
          existingId: hasExistingFound ? ovhRow.id : null,
          existingRawLrc: hasExistingFound ? ovhRow.rawLrc : null,
        );
        if (isCancelled()) return LyricsResult.cancelled;
        if (ovhResult != null) {
          return ovhResult;
        }
        if (hasExistingFound) {
          final parsed = _parseRow(ovhRow);
          if (parsed.isNotEmpty) {
            return LyricsResult(
              lrc: parsed,
              rawLrc: ovhRow.rawLrc,
              source: LyricsSource.lyricsOvh,
              lyricsId: ovhRow.id,
            );
          }
        }
      }
    }

    return LyricsResult.empty;
  }

  /// Translates [lines] into [targetLanguage], reading and writing the SQLite
  /// `lyrics_translations` cache when [lyricsId] is available.
  Future<List<String>> translateLyrics({
    required int? lyricsId,
    required List<String> lines,
    required String targetLanguage,
    String sourceLanguage = 'autodetect',
    bool forceRefresh = false,
    LyricsCancellationToken? cancellationToken,
  }) async {
    _translationToken?.cancel();
    final token = cancellationToken ?? LyricsCancellationToken();
    _translationToken = token;

    final cleanTarget = targetLanguage.trim().toLowerCase();
    final cleanSource = sourceLanguage.trim().isEmpty
        ? 'autodetect'
        : sourceLanguage.trim().toLowerCase();
    final langKey = cleanSource == 'autodetect'
        ? cleanTarget
        : '$cleanSource->$cleanTarget';

    if (cleanSource != 'autodetect' && cleanSource == cleanTarget) {
      return List<String>.from(lines);
    }

    if (!forceRefresh && lyricsId != null) {
      final cachedLines = await database.getLyricsTranslation(
        lyricsId: lyricsId,
        lang: langKey,
      );
      if (token.isCancelled) return const [];
      if (cachedLines != null && cachedLines.length == lines.length) {
        return cachedLines;
      }
    }

    final result = await _translationClient.translate(
      lines,
      targetLanguage: cleanTarget,
      sourceLanguage: cleanSource == 'autodetect' ? null : cleanSource,
    );

    if (token.isCancelled) return const [];

    if (!result.isSuccess) {
      throw LyricsTranslationException(
        result.errorMessage ?? 'Translation failed',
        statusCode: result.statusCode,
      );
    }

    final translated = result.translatedLines;

    if (lyricsId != null && translated.length == lines.length) {
      await database.saveLyricsTranslation(
        lyricsId: lyricsId,
        lang: langKey,
        translatedLines: translated,
      );
    }

    return translated;
  }

  ParsedLrc _parseRow(_PersistedLyricsRow row) {
    if (row.rawLrc != null && row.rawLrc!.trim().isNotEmpty) {
      final parsed = LrcParser.parse(row.rawLrc!);
      if (parsed.isNotEmpty) return parsed;
    }
    return ParsedLrc.empty();
  }

  Future<LyricsResult?> _fetchFromLrclibAndPersist({
    required int? trackId,
    required String title,
    required String artist,
    String? album,
    int? durationSeconds,
    LyricsCancellationToken? cancellationToken,
    void Function(LyricsResult retryResult)? onThresholdRetryResolved,
    required bool enableLyricsOvhFallback,
    bool preserveExistingFound = false,
    int? existingId,
    String? existingRawLrc,
  }) async {
    bool isCancelled() => cancellationToken?.isCancelled ?? false;

    final response = await _lrclibClient.getLyrics(
      trackName: title,
      artistName: artist,
      albumName: album,
      durationSeconds: durationSeconds,
      cancellationToken: cancellationToken,
      isCancelled: isCancelled,
    );

    if (isCancelled()) return null;

    if (response is LrclibRateLimited) {
      final waitSec = (response.retryAfterSeconds ?? 5).clamp(1, 3600);
      if (response.shouldTriggerCountdown) {
        cooldownManager.startThresholdCountdown(
          seconds: waitSec,
          isStillValid: () => !isCancelled(),
          onAutoRetry: () async {
            if (isCancelled()) return;
            final retryRes = await _fetchFromLrclibAndPersist(
              trackId: trackId,
              title: title,
              artist: artist,
              album: album,
              durationSeconds: durationSeconds,
              cancellationToken: cancellationToken,
              enableLyricsOvhFallback: enableLyricsOvhFallback,
              preserveExistingFound: preserveExistingFound,
              existingId: existingId,
              existingRawLrc: existingRawLrc,
            );
            if (isCancelled()) return;
            if (retryRes != null && retryRes.isNotEmpty) {
              onThresholdRetryResolved?.call(retryRes);
            } else if (enableLyricsOvhFallback &&
                title.trim().isNotEmpty &&
                artist.trim().isNotEmpty) {
              final ovhFallback = await _fetchFromOvhAndPersist(
                trackId: trackId,
                artist: artist,
                title: title,
                cancellationToken: cancellationToken,
                preserveExistingFound: preserveExistingFound,
              );
              if (!isCancelled() && ovhFallback != null) {
                onThresholdRetryResolved?.call(ovhFallback);
              } else if (!isCancelled()) {
                onThresholdRetryResolved?.call(LyricsResult.empty);
              }
            } else {
              onThresholdRetryResolved?.call(LyricsResult.empty);
            }
          },
        );

        return LyricsResult(
          lrc: ParsedLrc.empty(),
          isThresholdWaiting: true,
          retryAfterSeconds: waitSec,
        );
      } else {
        cooldownManager.setCooldown(Duration(seconds: waitSec));
        return null;
      }
    }

    if (response.isTemporaryError) {
      // Transient network or 5xx error: never persist NOT_FOUND.
      return null;
    }

    if (response.isNotFound || !response.hasAnyLyrics) {
      if (trackId != null && !preserveExistingFound) {
        await database.saveLyricsEntry(
          trackId: trackId,
          source: LyricsSource.lrclib.dbValue,
          state: LyricsSourceState.notFound.dbValue,
        );
      }
      return null;
    }

    String? rawLrc;
    ParsedLrc parsed = ParsedLrc.empty();
    if (response.hasSyncedLyrics) {
      rawLrc = response.syncedLyrics!;
      parsed = LrcParser.parse(rawLrc);
    }
    if (parsed.isEmpty && response.hasPlainLyrics) {
      rawLrc = response.plainLyrics!;
      parsed = LrcParser.parse(rawLrc);
    }

    if (parsed.isEmpty || rawLrc == null) {
      if (trackId != null && !preserveExistingFound) {
        await database.saveLyricsEntry(
          trackId: trackId,
          source: LyricsSource.lrclib.dbValue,
          state: LyricsSourceState.notFound.dbValue,
        );
      }
      return null;
    }

    int? lyricsId;
    if (trackId != null) {
      if (existingId != null && existingRawLrc == rawLrc) {
        lyricsId = existingId;
      } else {
        lyricsId = await database.saveLyricsEntry(
          trackId: trackId,
          source: LyricsSource.lrclib.dbValue,
          state: LyricsSourceState.found.dbValue,
          rawLrc: rawLrc,
          isSynced: parsed.isSynced,
        );
      }
    }

    return LyricsResult(
      lrc: parsed,
      rawLrc: rawLrc,
      source: LyricsSource.lrclib,
      lyricsId: lyricsId,
    );
  }

  Future<LyricsResult?> _fetchFromOvhAndPersist({
    required int? trackId,
    required String artist,
    required String title,
    LyricsCancellationToken? cancellationToken,
    bool preserveExistingFound = false,
    int? existingId,
    String? existingRawLrc,
  }) async {
    bool isCancelled() => cancellationToken?.isCancelled ?? false;
    if (isCancelled()) return null;

    final response = await _ovhClient.getLyrics(artist: artist, title: title);

    if (isCancelled()) return null;

    if (response.isTemporaryError) {
      return null;
    }

    final plain = response.lyrics;
    if (response.isNotFound || plain == null || plain.trim().isEmpty) {
      if (trackId != null && !preserveExistingFound) {
        await database.saveLyricsEntry(
          trackId: trackId,
          source: LyricsSource.lyricsOvh.dbValue,
          state: LyricsSourceState.notFound.dbValue,
        );
      }
      return null;
    }

    final parsed = LrcParser.parse(plain);
    if (parsed.isEmpty) {
      if (trackId != null && !preserveExistingFound) {
        await database.saveLyricsEntry(
          trackId: trackId,
          source: LyricsSource.lyricsOvh.dbValue,
          state: LyricsSourceState.notFound.dbValue,
        );
      }
      return null;
    }

    int? lyricsId;
    if (trackId != null) {
      if (existingId != null && existingRawLrc == plain) {
        lyricsId = existingId;
      } else {
        lyricsId = await database.saveLyricsEntry(
          trackId: trackId,
          source: LyricsSource.lyricsOvh.dbValue,
          state: LyricsSourceState.found.dbValue,
          rawLrc: plain,
          isSynced: false,
        );
      }
    }

    return LyricsResult(
      lrc: parsed,
      rawLrc: plain,
      source: LyricsSource.lyricsOvh,
      lyricsId: lyricsId,
    );
  }

  static Future<String?> _readLocalLrcFileRaw(String filePath) async {
    try {
      final dir = p.dirname(filePath);
      final baseName = p.basenameWithoutExtension(filePath);
      for (final ext in const ['.lrc', '.LRC']) {
        final candidate = File(p.join(dir, '$baseName$ext'));
        if (await candidate.exists()) {
          return utf8.decode(
            await candidate.readAsBytes(),
            allowMalformed: true,
          );
        }
      }
    } catch (_) {}
    return null;
  }

  void dispose() {
    cancelPending();
    cooldownManager.dispose();
  }
}
