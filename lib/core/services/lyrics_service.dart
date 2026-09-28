import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/network/lrclib_client.dart';
import 'package:tachyon/core/network/lyrics_ovh_client.dart';
import 'package:tachyon/core/network/lyrics_rate_limiter.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/playback/domain/lyric_line.dart';
import 'package:tachyon/features/playback/domain/lyric_source.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';

import 'lrc_parser.dart';

/// Structured result container returned by [LyricsService.resolveLyricsByUri].
@immutable
class LyricsResult {
  final ParsedLrc lyrics;
  final LyricsSource source;
  final LyricsSourceState state;
  final String? rawLrc;
  final bool isSynced;
  final String keyHash;

  const LyricsResult({
    required this.lyrics,
    required this.source,
    required this.state,
    this.rawLrc,
    required this.isSynced,
    required this.keyHash,
  });

  List<LyricLine> get lines => lyrics.lines;
  bool get isEmpty => lyrics.isEmpty;
  bool get isNotEmpty => lyrics.isNotEmpty;
  ParsedLrc get parsedLrc => lyrics;

  @override
  String toString() =>
      'LyricsResult(source: ${source.dbValue}, state: ${state.dbValue}, '
      'lines: ${lines.length}, isSynced: $isSynced)';
}

/// Production implementation of [LyricsService] with 4-tier resolution hierarchy:
/// 1. Embedded tags (USLT, LYRICS in audio file or tracks table)
/// 2. Contiguous local .lrc file (<track>.lrc or <track>.LRC)
/// [Visibility Gate: if !allowRemote, stops here without network calls]
/// 3. Primary API (lrclib.net) with 500ms pacing & 429 threshold handling
/// 4. Secondary fallback API (lyrics.ovh)
///
/// Features SQLite per-origin state persistence (`lyrics_source_cache`) and in-memory LRU cache.
class LyricsService {
  final AppDatabase database;
  final LrclibClient lrclibClient;
  final LyricsOvhClient lyricsOvhClient;
  final LyricsCooldownManager cooldownManager;
  final int maxMemoryEntries;

  // In-memory LRU cache: keyHash -> LyricsResult
  final LinkedHashMap<String, LyricsResult> _memoryCache =
      LinkedHashMap<String, LyricsResult>();

  LyricsService({
    required this.database,
    LrclibClient? lrclibClient,
    LyricsOvhClient? lyricsOvhClient,
    LyricsCooldownManager? cooldownManager,
    this.maxMemoryEntries = 50,
  })  : lrclibClient = lrclibClient ?? LrclibClient(),
        lyricsOvhClient = lyricsOvhClient ?? LyricsOvhClient(),
        cooldownManager = cooldownManager ?? LyricsCooldownManager();

  /// Resolves lyrics following the 4-tier hierarchy:
  /// 1. Embedded tags (USLT, LYRICS)
  /// 2. Contiguous local .lrc file
  /// [Visibility Gate: if !allowRemote, returns null without web queries]
  /// 3. Primary web API (lrclib.net) with 500ms pacing and 429 threshold handling
  /// 4. Secondary fallback web API (lyrics.ovh)
  Future<LyricsResult?> resolveLyricsByUri({
    required String uri,
    String? title,
    String? artist,
    String? album,
    int? durationMs,
    String? embeddedLyrics,
    bool allowRemote = true,
    bool forceRefresh = false,
    Set<LyricsSource>? enabledSources,
    LyricsCancellationToken? cancellationToken,
    bool Function()? isCancelled,
    void Function(int seconds)? onThresholdCountdown,
  }) async {
    bool cancelled() =>
        (cancellationToken != null && cancellationToken.isCancelled) ||
        (isCancelled != null && isCancelled());

    if (cancelled()) return null;

    final keyHash = computeLyricsKey(
      uri: uri,
      title: title,
      artist: artist,
      durationMs: durationMs,
    );

    final activeSources = enabledSources ?? LyricsSource.values.toSet();

    // Force refresh purges previous cache for this track
    if (forceRefresh) {
      _memoryCache.remove(keyHash);
      await database.clearLyricsSourceEntries(keyHash);
      cooldownManager.clearCooldown();
    }

    // 0. In-Memory LRU Cache check
    if (!forceRefresh && _memoryCache.containsKey(keyHash)) {
      final cached = _memoryCache.remove(keyHash)!;
      _memoryCache[keyHash] = cached; // refresh LRU order
      if (activeSources.contains(cached.source)) {
        return cached;
      }
    }

    // -------------------------------------------------------------------------
    // Tier 1: Embedded audio metadata tags (USLT, LYRICS)
    // -------------------------------------------------------------------------
    if (activeSources.contains(LyricsSource.embedded)) {
      String? rawLyrics = embeddedLyrics;
      if (rawLyrics == null || rawLyrics.trim().isEmpty) {
        try {
          rawLyrics = await database.getTrackLyricsByUri(uri);
        } catch (_) {}
      }

      if (rawLyrics != null && rawLyrics.trim().isNotEmpty) {
        final parsed = LrcParser.parse(rawLyrics);
        if (parsed.isNotEmpty) {
          final entry = LyricsSourceEntry.found(
            keyHash: keyHash,
            source: LyricsSource.embedded,
            rawLrc: rawLyrics,
            isSynced: parsed.isSynced,
          );
          await database.saveLyricsSourceEntry(entry);
          final result = LyricsResult(
            lyrics: parsed,
            source: LyricsSource.embedded,
            state: LyricsSourceState.found,
            rawLrc: rawLyrics,
            isSynced: parsed.isSynced,
            keyHash: keyHash,
          );
          _putInMemory(keyHash, result);
          return result;
        }
      }
    }

    // -------------------------------------------------------------------------
    // Tier 2: Contiguous local .lrc file in track folder
    // -------------------------------------------------------------------------
    if (activeSources.contains(LyricsSource.file)) {
      final externalLrc = await _checkExternalLrcFile(uri);
      if (externalLrc != null && externalLrc.trim().isNotEmpty) {
        final parsed = LrcParser.parse(externalLrc);
        if (parsed.isNotEmpty) {
          final entry = LyricsSourceEntry.found(
            keyHash: keyHash,
            source: LyricsSource.file,
            rawLrc: externalLrc,
            isSynced: parsed.isSynced,
          );
          await database.saveLyricsSourceEntry(entry);
          final result = LyricsResult(
            lyrics: parsed,
            source: LyricsSource.file,
            state: LyricsSourceState.found,
            rawLrc: externalLrc,
            isSynced: parsed.isSynced,
            keyHash: keyHash,
          );
          _putInMemory(keyHash, result);
          return result;
        }
      }
    }

    // -------------------------------------------------------------------------
    // Remote Visibility Gating:
    // If LyricsView is closed / in background, DO NOT query web APIs!
    // -------------------------------------------------------------------------
    if (cancelled()) return null;
    if (!allowRemote) {
      return null;
    }

    // -------------------------------------------------------------------------
    // SQLite Cache Lookup for Web Sources
    // -------------------------------------------------------------------------
    final entries = await database.getAllLyricsSourceEntries(keyHash);

    // -------------------------------------------------------------------------
    // Tier 3: Primary Web API (lrclib.net)
    // -------------------------------------------------------------------------
    if (activeSources.contains(LyricsSource.lrclib)) {
      final lrclibEntry = entries[LyricsSource.lrclib];
      final canQueryLrclib =
          lrclibEntry == null || lrclibEntry.state != LyricsSourceState.notFound;

      if (canQueryLrclib) {
        if (!forceRefresh &&
            lrclibEntry != null &&
            lrclibEntry.state == LyricsSourceState.found &&
            lrclibEntry.rawLrc != null &&
            lrclibEntry.rawLrc!.trim().isNotEmpty) {
          final parsed = LrcParser.parse(lrclibEntry.rawLrc!);
          final result = LyricsResult(
            lyrics: parsed,
            source: LyricsSource.lrclib,
            state: LyricsSourceState.found,
            rawLrc: lrclibEntry.rawLrc!,
            isSynced: lrclibEntry.isSynced,
            keyHash: keyHash,
          );
          _putInMemory(keyHash, result);
          return result;
        }

        // Check active in-memory cooldown
        if (cooldownManager.isCooldownActive) {
          // Cooldown active -> Skip lrclib.net and fall through to Tier 4
        } else {
          final cleanTitle = title?.trim();
          final cleanArtist = artist?.trim();

          if (cleanTitle != null &&
              cleanTitle.isNotEmpty &&
              cleanArtist != null &&
              cleanArtist.isNotEmpty) {
            final durationSeconds = durationMs != null && durationMs > 0
                ? (durationMs / 1000).round()
                : null;

            final response = await lrclibClient.getLyrics(
              trackName: cleanTitle,
              artistName: cleanArtist,
              albumName: album?.trim(),
              durationSeconds: durationSeconds,
              cancellationToken: cancellationToken,
              isCancelled: isCancelled,
            );

            if (cancelled()) return null;

            if (response.isSuccess) {
              final rawLrc = response.syncedLyrics ?? response.plainLyrics;
              if (rawLrc != null && rawLrc.trim().isNotEmpty) {
                final parsed = LrcParser.parse(rawLrc);
                final isSynced = response.hasSyncedLyrics;
                final entry = LyricsSourceEntry.found(
                  keyHash: keyHash,
                  source: LyricsSource.lrclib,
                  rawLrc: rawLrc,
                  isSynced: isSynced,
                );
                await database.saveLyricsSourceEntry(entry);
                final result = LyricsResult(
                  lyrics: parsed,
                  source: LyricsSource.lrclib,
                  state: LyricsSourceState.found,
                  rawLrc: rawLrc,
                  isSynced: isSynced,
                  keyHash: keyHash,
                );
                _putInMemory(keyHash, result);
                return result;
              }
            } else if (response.isNotFound) {
              await database.saveLyricsSourceEntry(
                LyricsSourceEntry.notFound(
                  keyHash: keyHash,
                  source: LyricsSource.lrclib,
                ),
              );
            } else if (response.isRateLimited) {
              await database.saveLyricsSourceEntry(
                LyricsSourceEntry.temporaryError(
                  keyHash: keyHash,
                  source: LyricsSource.lrclib,
                ),
              );

              final retrySeconds = response.retryAfterSeconds ?? 5;
              if (retrySeconds <= 10) {
                onThresholdCountdown?.call(retrySeconds);
                return null;
              } else {
                cooldownManager.setCooldown(Duration(seconds: retrySeconds));
              }
            } else {
              await database.saveLyricsSourceEntry(
                LyricsSourceEntry.temporaryError(
                  keyHash: keyHash,
                  source: LyricsSource.lrclib,
                ),
              );
            }
          }
        }
      }
    }

    // -------------------------------------------------------------------------
    // Tier 4: Secondary Fallback Web API (lyrics.ovh)
    // -------------------------------------------------------------------------
    if (activeSources.contains(LyricsSource.lyricsOvh)) {
      if (cancelled()) return null;

      final ovhEntry = entries[LyricsSource.lyricsOvh];
      final canQueryOvh =
          ovhEntry == null || ovhEntry.state != LyricsSourceState.notFound;

      if (canQueryOvh) {
        if (!forceRefresh &&
            ovhEntry != null &&
            ovhEntry.state == LyricsSourceState.found &&
            ovhEntry.rawLrc != null &&
            ovhEntry.rawLrc!.trim().isNotEmpty) {
          final parsed = LrcParser.parse(ovhEntry.rawLrc!);
          final result = LyricsResult(
            lyrics: parsed,
            source: LyricsSource.lyricsOvh,
            state: LyricsSourceState.found,
            rawLrc: ovhEntry.rawLrc!,
            isSynced: false,
            keyHash: keyHash,
          );
          _putInMemory(keyHash, result);
          return result;
        }

        final cleanTitle = title?.trim();
        final cleanArtist = artist?.trim();

        if (cleanTitle != null &&
            cleanTitle.isNotEmpty &&
            cleanArtist != null &&
            cleanArtist.isNotEmpty) {
          final ovhResponse = await lyricsOvhClient.getLyrics(
            artist: cleanArtist,
            title: cleanTitle,
          );

          if (cancelled()) return null;

          if (ovhResponse.isSuccess) {
            final ovhLyrics = ovhResponse.lyrics;
            if (ovhLyrics != null && ovhLyrics.trim().isNotEmpty) {
              final parsed = LrcParser.parse(ovhLyrics);
              final entry = LyricsSourceEntry.found(
                keyHash: keyHash,
                source: LyricsSource.lyricsOvh,
                rawLrc: ovhLyrics,
                isSynced: false,
              );
              await database.saveLyricsSourceEntry(entry);
              final result = LyricsResult(
                lyrics: parsed,
                source: LyricsSource.lyricsOvh,
                state: LyricsSourceState.found,
                rawLrc: ovhLyrics,
                isSynced: false,
                keyHash: keyHash,
              );
              _putInMemory(keyHash, result);
              return result;
            }
          } else if (ovhResponse.isNotFound) {
            await database.saveLyricsSourceEntry(
              LyricsSourceEntry.notFound(
                keyHash: keyHash,
                source: LyricsSource.lyricsOvh,
              ),
            );
          } else {
            await database.saveLyricsSourceEntry(
              LyricsSourceEntry.temporaryError(
                keyHash: keyHash,
                source: LyricsSource.lyricsOvh,
              ),
            );
          }
        }
      }
    }

    return null;
  }

  Future<LyricsResult?> resolveLyricsForTrack(
    Track track, {
    bool allowRemote = true,
    bool forceRefresh = false,
    Set<LyricsSource>? enabledSources,
    LyricsCancellationToken? cancellationToken,
    bool Function()? isCancelled,
    void Function(int seconds)? onThresholdCountdown,
  }) {
    return resolveLyricsByUri(
      uri: track.uri,
      title: track.title,
      artist: track.artist,
      album: track.album,
      durationMs: track.durationMs,
      embeddedLyrics: track.lyrics,
      allowRemote: allowRemote,
      forceRefresh: forceRefresh,
      enabledSources: enabledSources,
      cancellationToken: cancellationToken,
      isCancelled: isCancelled,
      onThresholdCountdown: onThresholdCountdown,
    );
  }

  Future<LyricsResult?> resolveLyricsForQueueItem(
    QueueItem item, {
    bool allowRemote = true,
    bool forceRefresh = false,
    Set<LyricsSource>? enabledSources,
    LyricsCancellationToken? cancellationToken,
    bool Function()? isCancelled,
    void Function(int seconds)? onThresholdCountdown,
    bool? enableLocal,
    bool? enableLrclib,
    bool? enableLyricsOvh,
  }) {
    final embedded = item.extras['lyrics'] as String?;
    Set<LyricsSource>? effectiveSources = enabledSources;
    if (effectiveSources == null &&
        (enableLocal != null || enableLrclib != null || enableLyricsOvh != null)) {
      effectiveSources = <LyricsSource>{
        if (enableLocal ?? true) ...[LyricsSource.embedded, LyricsSource.file],
        if (enableLrclib ?? true) LyricsSource.lrclib,
        if (enableLyricsOvh ?? true) LyricsSource.lyricsOvh,
      };
    }

    return resolveLyricsByUri(
      uri: item.uri,
      title: item.title,
      artist: item.artist,
      album: item.album,
      durationMs: item.duration.inMilliseconds,
      embeddedLyrics: embedded,
      allowRemote: allowRemote,
      forceRefresh: forceRefresh,
      enabledSources: effectiveSources,
      cancellationToken: cancellationToken,
      isCancelled: isCancelled,
      onThresholdCountdown: onThresholdCountdown,
    );
  }

  /// Convenience method accepting either a [QueueItem] or [Track].
  Future<LyricsResult?> resolveLyrics({
    dynamic track,
    QueueItem? queueItem,
    Track? trackItem,
    bool allowRemote = true,
    bool forceRefresh = false,
    Set<LyricsSource>? enabledSources,
    LyricsCancellationToken? cancellationToken,
    bool Function()? isCancelled,
    void Function(int seconds)? onThresholdCountdown,
    bool? enableLocal,
    bool? enableLrclib,
    bool? enableLyricsOvh,
  }) {
    if (queueItem != null) {
      return resolveLyricsForQueueItem(
        queueItem,
        allowRemote: allowRemote,
        forceRefresh: forceRefresh,
        enabledSources: enabledSources,
        cancellationToken: cancellationToken,
        isCancelled: isCancelled,
        onThresholdCountdown: onThresholdCountdown,
        enableLocal: enableLocal,
        enableLrclib: enableLrclib,
        enableLyricsOvh: enableLyricsOvh,
      );
    }
    if (trackItem != null) {
      return resolveLyricsForTrack(
        trackItem,
        allowRemote: allowRemote,
        forceRefresh: forceRefresh,
        enabledSources: enabledSources,
        cancellationToken: cancellationToken,
        isCancelled: isCancelled,
        onThresholdCountdown: onThresholdCountdown,
      );
    }
    if (track is QueueItem) {
      return resolveLyricsForQueueItem(
        track,
        allowRemote: allowRemote,
        forceRefresh: forceRefresh,
        enabledSources: enabledSources,
        cancellationToken: cancellationToken,
        isCancelled: isCancelled,
        onThresholdCountdown: onThresholdCountdown,
        enableLocal: enableLocal,
        enableLrclib: enableLrclib,
        enableLyricsOvh: enableLyricsOvh,
      );
    }
    if (track is Track) {
      return resolveLyricsForTrack(
        track,
        allowRemote: allowRemote,
        forceRefresh: forceRefresh,
        enabledSources: enabledSources,
        cancellationToken: cancellationToken,
        isCancelled: isCancelled,
        onThresholdCountdown: onThresholdCountdown,
      );
    }
    return Future.value(null);
  }

  /// Resolves only local sources (embedded tags and local .lrc files) without remote network calls.
  Future<LyricsResult?> resolveLocalLyricsOnly(dynamic item) {
    if (item is QueueItem) {
      return resolveLyricsForQueueItem(
        item,
        allowRemote: false,
        enabledSources: {LyricsSource.embedded, LyricsSource.file},
      );
    }
    if (item is Track) {
      return resolveLyricsForTrack(
        item,
        allowRemote: false,
        enabledSources: {LyricsSource.embedded, LyricsSource.file},
      );
    }
    return Future.value(null);
  }

  // ---------------------------------------------------------------------------
  // Backward-Compatible Convenience Methods
  // ---------------------------------------------------------------------------

  Future<ParsedLrc?> getLyricsForTrack(
    Track track, {
    bool forceRefresh = false,
    bool allowRemote = true,
    Set<LyricsSource>? enabledSources,
  }) async {
    final res = await resolveLyricsForTrack(
      track,
      forceRefresh: forceRefresh,
      allowRemote: allowRemote,
      enabledSources: enabledSources,
    );
    return res?.lyrics;
  }

  Future<ParsedLrc?> getLyricsForQueueItem(
    QueueItem item, {
    bool forceRefresh = false,
    bool allowRemote = true,
    Set<LyricsSource>? enabledSources,
    LyricsCancellationToken? cancellationToken,
    bool? enableLocal,
    bool? enableLrclib,
    bool? enableLyricsOvh,
  }) async {
    final res = await resolveLyricsForQueueItem(
      item,
      forceRefresh: forceRefresh,
      allowRemote: allowRemote,
      enabledSources: enabledSources,
      cancellationToken: cancellationToken,
      enableLocal: enableLocal,
      enableLrclib: enableLrclib,
      enableLyricsOvh: enableLyricsOvh,
    );
    return res?.lyrics;
  }

  Future<ParsedLrc?> getLyricsByUri({
    required String uri,
    String? title,
    String? artist,
    int? durationMs,
    String? embeddedLyrics,
    bool forceRefresh = false,
    bool allowRemote = true,
    Set<LyricsSource>? enabledSources,
  }) async {
    final res = await resolveLyricsByUri(
      uri: uri,
      title: title,
      artist: artist,
      durationMs: durationMs,
      embeddedLyrics: embeddedLyrics,
      forceRefresh: forceRefresh,
      allowRemote: allowRemote,
      enabledSources: enabledSources,
    );
    return res?.lyrics;
  }

  /// Inspects directory of [uri] for `<track_name>.lrc` or `<track_name>.LRC`
  Future<String?> _checkExternalLrcFile(String uri) async {
    try {
      String filePath = uri;
      if (filePath.startsWith('file://')) {
        filePath = Uri.parse(filePath).toFilePath();
      }

      final file = File(filePath);
      if (!await file.exists()) return null;

      final dir = p.dirname(filePath);
      final baseName = p.basenameWithoutExtension(filePath);

      final candidates = [
        File(p.join(dir, '$baseName.lrc')),
        File(p.join(dir, '$baseName.LRC')),
      ];

      for (final candidate in candidates) {
        if (await candidate.exists()) {
          final bytes = await candidate.readAsBytes();
          return utf8.decode(bytes, allowMalformed: true);
        }
      }
    } catch (_) {}
    return null;
  }

  void _putInMemory(String key, LyricsResult result) {
    if (_memoryCache.length >= maxMemoryEntries) {
      _memoryCache.remove(_memoryCache.keys.first); // Evict oldest LRU
    }
    _memoryCache[key] = result;
  }

  Future<void> saveLyrics({
    required String keyHash,
    required String rawLrc,
    required String source,
  }) async {
    await database.saveLyrics(keyHash, rawLrc, source);
    final parsed = LrcParser.parse(rawLrc);
    final lyricsSource = LyricsSource.fromDbString(source);
    final result = LyricsResult(
      lyrics: parsed,
      source: lyricsSource,
      state: LyricsSourceState.found,
      rawLrc: rawLrc,
      isSynced: parsed.isSynced,
      keyHash: keyHash,
    );
    _putInMemory(keyHash, result);
  }

  void clearMemoryCache() {
    _memoryCache.clear();
  }

  /// Computes a canonical SHA-256 hash for lyrics identification.
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
}
