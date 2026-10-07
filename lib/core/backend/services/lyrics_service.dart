import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/network/lrclib_client.dart';
import 'package:tachyon/core/network/lyrics_ovh_client.dart';
import 'package:tachyon/core/network/lyrics_rate_limiter.dart';
import 'package:tachyon/core/network/lyrics_translation_client.dart';
import 'package:tachyon/features/playback/domain/lyric_line.dart';
import 'package:tachyon/features/playback/domain/lyric_source.dart';

import 'lrc_parser.dart';

/// Phase 1 result returned by [LyricsService.resolveLyrics].
///
/// [lyricsId] is the `lyrics.id` row used to request Phase 2 translations.
@immutable
class LyricsResult {
  final int? lyricsId;
  final ParsedLrc lyrics;
  final LyricsSource source;
  final LyricsSourceState state;
  final String? rawLrc;
  final bool isSynced;
  final String? lang;

  const LyricsResult({
    this.lyricsId,
    required this.lyrics,
    required this.source,
    required this.state,
    this.rawLrc,
    required this.isSynced,
    this.lang,
  });

  List<LyricLine> get lines => lyrics.lines;
  bool get isEmpty => lyrics.isEmpty;
  bool get isNotEmpty => lyrics.isNotEmpty;

  Map<String, dynamic> toMap() => {
    'lyricsId': lyricsId,
    'source': source.dbValue,
    'state': state.dbValue,
    'rawLrc': rawLrc,
    'isSynced': isSynced,
    'lang': lang,
  };

  static LyricsResult fromMap(Map<String, dynamic> map) {
    final rawLrc = map['rawLrc'] as String?;
    final parsed = rawLrc != null && rawLrc.trim().isNotEmpty
        ? LrcParser.parse(rawLrc)
        : ParsedLrc.empty();
    return LyricsResult(
      lyricsId: map['lyricsId'] as int?,
      lyrics: parsed,
      source: LyricsSource.fromDbString(map['source'] as String),
      state: LyricsSourceState.fromDbString(map['state'] as String),
      rawLrc: rawLrc,
      isSynced: map['isSynced'] as bool? ?? parsed.isSynced,
      lang: map['lang'] as String?,
    );
  }

  @override
  String toString() =>
      'LyricsResult(lyricsId: $lyricsId, source: ${source.dbValue}, state: ${state.dbValue}, '
      'lines: ${lines.length}, isSynced: $isSynced)';
}

/// Backend lyrics resolver persisting one row per `(track_id, source)` in `lyrics`.
///
/// Resolution order: `embedded` → `file` → `lrclib` → `lyrics_ovh`.
/// - `embedded` rows are written exclusively by the folder scan (`AppDatabase.upsertTracks`).
/// - `file` rows mirror the contiguous `<track>.lrc` / `<track>.LRC` on every request.
/// - Remote sources are only queried when `allowRemote` is true (LyricsView visible).
/// - `NOT_FOUND` is persisted to avoid re-querying; transient failures are never persisted
///   and never overwrite an existing `FOUND` row.
/// - Updating a row's content purges its translations (see `AppDatabase.saveLyricsEntry`).
class LyricsService {
  final AppDatabase database;
  final LrclibClient lrclibClient;
  final LyricsOvhClient lyricsOvhClient;
  final LyricsCooldownManager cooldownManager;
  final LyricsTranslationClient translationClient;

  final Map<String, Future<LyricsResult?>> _inFlightResolutions = {};

  LyricsService({
    required this.database,
    LrclibClient? lrclibClient,
    LyricsOvhClient? lyricsOvhClient,
    LyricsCooldownManager? cooldownManager,
    LyricsTranslationClient? translationClient,
  }) : lrclibClient = lrclibClient ?? LrclibClient(),
       lyricsOvhClient = lyricsOvhClient ?? LyricsOvhClient(),
       cooldownManager = cooldownManager ?? LyricsCooldownManager(),
       translationClient = translationClient ?? LyricsTranslationClient();

  /// Phase 1: resolves the best lyrics for [trackId].
  ///
  /// [bypassCache] forces a remote re-search, ignoring persisted remote rows
  /// (including `NOT_FOUND`). Local rows (embedded/file) still win by priority.
  /// When lrclib answers HTTP 429 with `Retry-After <= 10s`, [onThresholdCountdown]
  /// is invoked and `null` is returned so the caller can retry automatically.
  Future<LyricsResult?> resolveLyrics({
    required int trackId,
    required String filePath,
    String? title,
    String? artist,
    String? album,
    int? durationMs,
    bool allowRemote = true,
    bool bypassCache = false,
    Set<LyricsSource>? allowedSources,
    LyricsCancellationToken? cancellationToken,
    void Function(int seconds)? onThresholdCountdown,
  }) async {
    bool cancelled() => cancellationToken?.isCancelled ?? false;
    if (trackId <= 0 || cancelled()) return null;

    final flightKey = '$trackId-$allowRemote';
    if (!bypassCache && _inFlightResolutions.containsKey(flightKey)) {
      final res = await _inFlightResolutions[flightKey];
      if (cancelled()) return null;
      return res;
    }

    final future = _resolveLyricsInternal(
      trackId: trackId,
      filePath: filePath,
      title: title,
      artist: artist,
      album: album,
      durationMs: durationMs,
      allowRemote: allowRemote,
      bypassCache: bypassCache,
      allowedSources: allowedSources,
      cancellationToken: cancellationToken,
      onThresholdCountdown: onThresholdCountdown,
    );

    if (!bypassCache) {
      _inFlightResolutions[flightKey] = future;
      future.whenComplete(() {
        _inFlightResolutions.remove(flightKey);
      });
    }

    final res = await future;
    if (cancelled()) return null;
    return res;
  }

  Future<LyricsResult?> _resolveLyricsInternal({
    required int trackId,
    required String filePath,
    String? title,
    String? artist,
    String? album,
    int? durationMs,
    required bool allowRemote,
    required bool bypassCache,
    Set<LyricsSource>? allowedSources,
    LyricsCancellationToken? cancellationToken,
    void Function(int seconds)? onThresholdCountdown,
  }) async {
    bool cancelled() => cancellationToken?.isCancelled ?? false;
    if (trackId <= 0 || cancelled()) return null;

    final sources = allowedSources ?? LyricsSource.values.toSet();

    // Keep the `file` row in sync with the contiguous .lrc on disk.
    if (sources.contains(LyricsSource.file)) {
      await _syncFileLyrics(trackId, filePath);
      if (cancelled()) return null;
    }

    // Local sources always win by priority, even on a forced re-search.
    final local = _bestPersisted(trackId, sources.where((s) => s.isLocal));
    if (local != null) return local;

    if (!bypassCache) {
      final remote = _bestPersisted(trackId, sources.where((s) => s.isRemote));
      if (remote != null) return remote;
    }

    if (!allowRemote) return null;
    if (bypassCache) cooldownManager.clearCooldown();

    final cleanTitle = title?.trim() ?? '';
    final cleanArtist = artist?.trim() ?? '';
    final canQueryRemote = cleanTitle.isNotEmpty && cleanArtist.isNotEmpty;

    // Tier 3: lrclib.net (synced + plain).
    if (canQueryRemote &&
        sources.contains(LyricsSource.lrclib) &&
        !cooldownManager.isCooldownActive &&
        _mayQuery(trackId, LyricsSource.lrclib, bypassCache)) {
      final response = await lrclibClient.getLyrics(
        trackName: cleanTitle,
        artistName: cleanArtist,
        albumName: album?.trim(),
        durationSeconds: durationMs != null && durationMs > 0
            ? (durationMs / 1000).round()
            : null,
        cancellationToken: cancellationToken,
      );
      if (cancelled()) return null;

      final raw = response.syncedLyrics ?? response.plainLyrics;
      if (response.isSuccess && raw != null && raw.trim().isNotEmpty) {
        return _storeFound(
          trackId,
          LyricsSource.lrclib,
          raw,
          response.hasSyncedLyrics,
        );
      }
      if (response.isNotFound) {
        _storeNotFound(trackId, LyricsSource.lrclib);
      } else if (response.isRateLimited) {
        final retrySeconds = response.retryAfterSeconds ?? 5;
        if (retrySeconds <= 10) {
          onThresholdCountdown?.call(retrySeconds);
          return null;
        }
        cooldownManager.setCooldown(Duration(seconds: retrySeconds));
      }
    }

    // Tier 4: lyrics.ovh (plain text fallback).
    if (canQueryRemote &&
        sources.contains(LyricsSource.lyricsOvh) &&
        _mayQuery(trackId, LyricsSource.lyricsOvh, bypassCache)) {
      final response = await lyricsOvhClient.getLyrics(
        artist: cleanArtist,
        title: cleanTitle,
      );
      if (cancelled()) return null;

      final raw = response.lyrics;
      if (response.isSuccess && raw != null && raw.trim().isNotEmpty) {
        return _storeFound(trackId, LyricsSource.lyricsOvh, raw, false);
      }
      if (response.isNotFound) _storeNotFound(trackId, LyricsSource.lyricsOvh);
    }

    // A failed re-search keeps whatever remote lyrics were already stored.
    return bypassCache
        ? _bestPersisted(trackId, sources.where((s) => s.isRemote))
        : null;
  }

  /// Phase 2: returns the translation of [lyricsId] into [targetLang], fetching
  /// and persisting it in `lyrics_translations` on cache miss.
  Future<List<String>?> translateLyrics({
    required int lyricsId,
    required String targetLang,
    String? sourceLang,
    required List<String> rawLines,
  }) async {
    if (kDebugMode) {
      debugPrint(
        'Translating lyrics $lyricsId from ${sourceLang ?? 'autodetect'} into $targetLang...',
      );
    }
    if (rawLines.isEmpty) return const [];

    final storedLang = database.getLyricsLang(lyricsId);
    final isExplicitSame =
        sourceLang != null && sourceLang != 'autodetect' && sourceLang == targetLang;

    // If lyrics are already known to be in targetLang, or if source and target match:
    if (storedLang == targetLang || isExplicitSame) {
      if (storedLang != targetLang) {
        database.updateLyricsLang(lyricsId, targetLang);
      }
      return rawLines;
    }

    final cached = database.getLyricsTranslation(
      lyricsId: lyricsId,
      lang: targetLang,
    );
    if (cached != null && cached.isNotEmpty) return cached;

    if (kDebugMode) {
      debugPrint(
        'No stored translation found for lyrics $lyricsId into $targetLang, requesting remote translation...',
      );
    }

    final result = await translationClient.translate(
      rawLines,
      targetLanguage: targetLang,
      sourceLanguage: sourceLang,
    );
    if (kDebugMode) {
      debugPrint(
        'Translation result: ${result.isSuccess ? 'success' : 'failure'} (sameLanguage: ${result.isSameLanguage})',
      );
      if (!result.isSuccess && result.errorMessage != null) {
        debugPrint('Error: ${result.errorMessage}');
      }
    }
    if (!result.isSuccess) {
      if (result.isRateLimited) {
        throw LyricsTranslationException(
          'Rate limit exceeded (Too many requests)',
          statusCode: 429,
        );
      }
      return null;
    }

    if (result.isSameLanguage) {
      database.updateLyricsLang(lyricsId, targetLang);
    } else if (sourceLang != null && sourceLang != 'autodetect') {
      database.updateLyricsLang(lyricsId, sourceLang);
    }

    database.saveLyricsTranslation(
      lyricsId: lyricsId,
      lang: targetLang,
      translatedLines: result.translatedLines,
    );
    return result.translatedLines;
  }

  LyricsResult? _bestPersisted(int trackId, Iterable<LyricsSource> candidates) {
    final ordered = candidates.toList()
      ..sort((a, b) => a.priority.compareTo(b.priority));
    for (final source in ordered) {
      final row = database.getLyricsEntry(
        trackId: trackId,
        source: source.dbValue,
      );
      final raw = row?['raw_lrc'] as String?;
      if (row == null ||
          row['state'] != LyricsSourceState.found.dbValue ||
          raw == null ||
          raw.trim().isEmpty) {
        continue;
      }
      return LyricsResult(
        lyricsId: row['id'] as int,
        lyrics: LrcParser.parse(raw),
        source: source,
        state: LyricsSourceState.found,
        rawLrc: raw,
        isSynced: (row['is_synced'] as int? ?? 0) == 1,
        lang: row['lang'] as String?,
      );
    }
    return null;
  }

  bool _mayQuery(int trackId, LyricsSource source, bool bypassCache) {
    if (bypassCache) return true;
    final row = database.getLyricsEntry(
      trackId: trackId,
      source: source.dbValue,
    );
    return row == null || row['state'] != LyricsSourceState.notFound.dbValue;
  }

  /// Persists a `FOUND` row. Unchanged content keeps the row (and its translations) intact.
  LyricsResult _storeFound(
    int trackId,
    LyricsSource source,
    String raw,
    bool isSynced, {
    String? lang,
  }) {
    int? lyricsId;
    String? finalLang = lang;
    try {
      final existing = database.getLyricsEntry(
        trackId: trackId,
        source: source.dbValue,
      );
      final unchanged =
          existing != null &&
          existing['state'] == LyricsSourceState.found.dbValue &&
          existing['raw_lrc'] == raw;
      lyricsId = unchanged
          ? existing['id'] as int
          : database.saveLyricsEntry(
              trackId: trackId,
              source: source.dbValue,
              state: LyricsSourceState.found.dbValue,
              rawLrc: raw,
              isSynced: isSynced,
              lang: lang,
            );
      if (unchanged) {
        finalLang = existing['lang'] as String?;
      }
    } catch (e) {
      debugPrint(
        '[LyricsService] Error storing found lyrics for track $trackId: $e',
      );
    }
    return LyricsResult(
      lyricsId: lyricsId,
      lyrics: LrcParser.parse(raw),
      source: source,
      state: LyricsSourceState.found,
      rawLrc: raw,
      isSynced: isSynced,
      lang: finalLang,
    );
  }

  /// Persists `NOT_FOUND` unless a `FOUND` row already exists for that source.
  void _storeNotFound(int trackId, LyricsSource source) {
    try {
      final existing = database.getLyricsEntry(
        trackId: trackId,
        source: source.dbValue,
      );
      if (existing?['state'] == LyricsSourceState.found.dbValue) return;
      database.saveLyricsEntry(
        trackId: trackId,
        source: source.dbValue,
        state: LyricsSourceState.notFound.dbValue,
      );
    } catch (e) {
      debugPrint(
        '[LyricsService] Error storing not-found for track $trackId: $e',
      );
    }
  }

  /// Mirrors `<track>.lrc` / `<track>.LRC` into the `file` row (insert, update or delete).
  Future<void> _syncFileLyrics(int trackId, String filePath) async {
    try {
      final raw = await _readContiguousLrc(filePath);
      final existing = database.getLyricsEntry(
        trackId: trackId,
        source: LyricsSource.file.dbValue,
      );
      if (raw == null || raw.trim().isEmpty) {
        if (existing != null) database.deleteLyrics(existing['id'] as int);
        return;
      }
      _storeFound(
        trackId,
        LyricsSource.file,
        raw,
        LrcParser.parse(raw).isSynced,
      );
    } catch (e) {
      debugPrint(
        '[LyricsService] Error in _syncFileLyrics for track $trackId: $e',
      );
    }
  }

  Future<String?> _readContiguousLrc(String filePath) async {
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
}
