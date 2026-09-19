import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';

import 'lrc_parser.dart';

/// Production implementation of [LyricsService] with 3-tier fallback and in-memory LRU cache.
class LyricsService {
  final AppDatabase database;
  final int maxMemoryEntries;

  // In-memory LRU cache: keyHash -> ParsedLrc
  final LinkedHashMap<String, ParsedLrc> _memoryCache =
      LinkedHashMap<String, ParsedLrc>();

  LyricsService({required this.database, this.maxMemoryEntries = 50});

  Future<ParsedLrc?> getLyricsForTrack(
    Track track, {
    bool forceRefresh = false,
  }) {
    return getLyricsByUri(
      uri: track.uri,
      title: track.title,
      artist: track.artist,
      durationMs: track.durationMs,
      embeddedLyrics: track.lyrics,
      forceRefresh: forceRefresh,
    );
  }

  Future<ParsedLrc?> getLyricsForQueueItem(
    QueueItem item, {
    bool forceRefresh = false,
  }) {
    final embedded = item.extras['lyrics'] as String?;
    return getLyricsByUri(
      uri: item.uri,
      title: item.title,
      artist: item.artist,
      durationMs: item.duration.inMilliseconds,
      embeddedLyrics: embedded,
      forceRefresh: forceRefresh,
    );
  }

  Future<ParsedLrc?> getLyricsByUri({
    required String uri,
    String? title,
    String? artist,
    int? durationMs,
    String? embeddedLyrics,
    bool forceRefresh = false,
  }) async {
    final keyHash = computeLyricsKey(
      uri: uri,
      title: title,
      artist: artist,
      durationMs: durationMs,
    );

    // 0. In-Memory LRU Cache check
    if (!forceRefresh && _memoryCache.containsKey(keyHash)) {
      final cached = _memoryCache.remove(keyHash)!;
      _memoryCache[keyHash] = cached; // refresh LRU order
      return cached;
    }

    // -------------------------------------------------------------------------
    // Tier 1: Embedded lyrics in audio file (USLT, LYRICS tags)
    // -------------------------------------------------------------------------
    String? rawLyrics = embeddedLyrics;
    if (rawLyrics == null || rawLyrics.trim().isEmpty) {
      // Query SQLite tracks table for embedded lyrics if track exists in library
      try {
        final rows = await database.database.query(
          'tracks',
          columns: ['lyrics'],
          where: 'uri = ?',
          whereArgs: [uri],
          limit: 1,
        );
        if (rows.isNotEmpty) {
          rawLyrics = rows.first['lyrics'] as String?;
        }
      } catch (_) {}
    }

    if (rawLyrics != null && rawLyrics.trim().isNotEmpty) {
      final parsed = LrcParser.parse(rawLyrics);
      if (parsed.isNotEmpty) {
        await _cacheLyrics(keyHash, rawLyrics, 'embedded');
        _putInMemory(keyHash, parsed);
        return parsed;
      }
    }

    // -------------------------------------------------------------------------
    // Tier 2: External .lrc file in audio file's directory
    // -------------------------------------------------------------------------
    final externalLrc = await _checkExternalLrcFile(uri);
    if (externalLrc != null && externalLrc.trim().isNotEmpty) {
      final parsed = LrcParser.parse(externalLrc);
      if (parsed.isNotEmpty) {
        await _cacheLyrics(keyHash, externalLrc, 'file');
        _putInMemory(keyHash, parsed);
        return parsed;
      }
    }

    // -------------------------------------------------------------------------
    // Tier 3: Local SQLite database cache (AppDatabase getLyrics)
    // -------------------------------------------------------------------------
    final cachedDbLyrics = await database.getLyrics(keyHash);
    if (cachedDbLyrics != null && cachedDbLyrics.trim().isNotEmpty) {
      final parsed = LrcParser.parse(cachedDbLyrics);
      if (parsed.isNotEmpty) {
        _putInMemory(keyHash, parsed);
        return parsed;
      }
    }

    return null;
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

  Future<void> _cacheLyrics(
    String keyHash,
    String rawLrc,
    String source,
  ) async {
    try {
      await database.saveLyrics(keyHash, rawLrc, source);
    } catch (e) {
      debugPrint('Error caching lyrics in SQLite: $e');
    }
  }

  void _putInMemory(String key, ParsedLrc parsed) {
    if (_memoryCache.length >= maxMemoryEntries) {
      _memoryCache.remove(_memoryCache.keys.first); // Evict oldest
    }
    _memoryCache[key] = parsed;
  }

  Future<void> saveLyrics({
    required String keyHash,
    required String rawLrc,
    required String source,
  }) async {
    await database.saveLyrics(keyHash, rawLrc, source);
    final parsed = LrcParser.parse(rawLrc);
    _putInMemory(keyHash, parsed);
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
