import 'package:flutter/foundation.dart';

/// Available lyric sources in order of standard resolution hierarchy.
enum LyricsSource {
  embedded,
  file,
  lrclib,
  lyricsOvh;

  bool get isLocal => this == embedded || this == file;
  bool get isRemote => this == lrclib || this == lyricsOvh;

  String toDbString() {
    return switch (this) {
      embedded => 'embedded',
      file => 'file',
      lrclib => 'lrclib',
      lyricsOvh => 'lyrics_ovh',
    };
  }

  static LyricsSource fromDbString(String s) {
    return switch (s.toLowerCase()) {
      'embedded' => embedded,
      'file' => file,
      'lrclib' => lrclib,
      'lyrics_ovh' || 'lyricsovh' => lyricsOvh,
      _ => throw ArgumentError('Unknown LyricsSource: $s'),
    };
  }
}

/// Per-origin fetch resolution status in persistence layer.
enum LyricsSourceState {
  found,
  notFound,
  temporaryError;

  String toDbString() {
    return switch (this) {
      found => 'FOUND',
      notFound => 'NOT_FOUND',
      temporaryError => 'TEMPORARY_ERROR',
    };
  }

  static LyricsSourceState fromDbString(String s) {
    return switch (s.toUpperCase()) {
      'FOUND' => found,
      'NOT_FOUND' => notFound,
      'TEMPORARY_ERROR' => temporaryError,
      _ => throw ArgumentError('Unknown LyricsSourceState: $s'),
    };
  }
}

/// Immutable persistence record tracking lyric content and status per source.
@immutable
class LyricsSourceEntry {
  final String keyHash;
  final LyricsSource source;
  final LyricsSourceState state;
  final String? rawLrc;
  final bool isSynced;
  final int updatedAt;

  const LyricsSourceEntry({
    required this.keyHash,
    required this.source,
    required this.state,
    this.rawLrc,
    this.isSynced = false,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'key_hash': keyHash,
      'source': source.toDbString(),
      'status': state.toDbString(),
      'raw_lrc': rawLrc,
      'is_synced': isSynced ? 1 : 0,
      'updated_at': updatedAt,
    };
  }

  factory LyricsSourceEntry.fromMap(Map<String, dynamic> map) {
    return LyricsSourceEntry(
      keyHash: map['key_hash'] as String,
      source: LyricsSource.fromDbString(map['source'] as String),
      state: LyricsSourceState.fromDbString(map['status'] as String),
      rawLrc: map['raw_lrc'] as String?,
      isSynced: (map['is_synced'] as int? ?? 0) == 1,
      updatedAt: map['updated_at'] as int,
    );
  }

  LyricsSourceEntry copyWith({
    String? keyHash,
    LyricsSource? source,
    LyricsSourceState? state,
    String? rawLrc,
    bool? isSynced,
    int? updatedAt,
  }) {
    return LyricsSourceEntry(
      keyHash: keyHash ?? this.keyHash,
      source: source ?? this.source,
      state: state ?? this.state,
      rawLrc: rawLrc ?? this.rawLrc,
      isSynced: isSynced ?? this.isSynced,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LyricsSourceEntry &&
          runtimeType == other.runtimeType &&
          keyHash == other.keyHash &&
          source == other.source &&
          state == other.state &&
          rawLrc == other.rawLrc &&
          isSynced == other.isSynced &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
        keyHash,
        source,
        state,
        rawLrc,
        isSynced,
        updatedAt,
      );

  @override
  String toString() =>
      'LyricsSourceEntry(keyHash: $keyHash, source: $source, state: $state, isSynced: $isSynced)';
}

/// Outgoing query descriptor for lrclib.net.
class LrclibQuery {
  final String trackName;
  final String artistName;
  final String? albumName;
  final int? durationSeconds;

  const LrclibQuery({
    required this.trackName,
    required this.artistName,
    this.albumName,
    this.durationSeconds,
  });

  Map<String, String> toQueryParams() {
    final params = <String, String>{
      'track_name': trackName,
      'artist_name': artistName,
    };
    if (albumName != null && albumName!.isNotEmpty) {
      params['album_name'] = albumName!;
    }
    if (durationSeconds != null) {
      params['duration'] = durationSeconds.toString();
    }
    return params;
  }
}

/// Structured response from primary API client (lrclib.net).
class LrclibResponse {
  final int? id;
  final String? trackName;
  final String? artistName;
  final String? albumName;
  final double? duration;
  final bool instrumental;
  final String? plainLyrics;
  final String? syncedLyrics;
  final int statusCode;
  final int? retryAfterSeconds;
  final Map<String, String> headers;

  const LrclibResponse({
    this.id,
    this.trackName,
    this.artistName,
    this.albumName,
    this.duration,
    this.instrumental = false,
    this.plainLyrics,
    this.syncedLyrics,
    this.statusCode = 200,
    this.retryAfterSeconds,
    this.headers = const {},
  });

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
  bool get isNotFound => statusCode == 404;
  bool get isRateLimited => statusCode == 429;
  bool get hasSyncedLyrics =>
      syncedLyrics != null && syncedLyrics!.trim().isNotEmpty;
  bool get hasPlainLyrics =>
      plainLyrics != null && plainLyrics!.trim().isNotEmpty;
}

/// Structured response from secondary API client (lyrics.ovh).
class LyricsOvhResponse {
  final String? lyrics;
  final int statusCode;
  final String? error;

  const LyricsOvhResponse({
    this.lyrics,
    this.statusCode = 200,
    this.error,
  });

  bool get isSuccess => statusCode == 200 && lyrics != null && lyrics!.trim().isNotEmpty;
  bool get isNotFound => statusCode == 404 || (statusCode == 200 && (lyrics == null || lyrics!.trim().isEmpty));
  bool get isError => statusCode != 200 && statusCode != 404;
}

/// Lyrics presentation display modes.
enum LyricsDisplayMode {
  original,
  translated,
  interleaved;
}

/// Result of lyrics translation operation.
class TranslationResult {
  final List<String> originalLines;
  final List<String> translatedLines;
  final String targetLanguage;
  final bool isSuccess;
  final String? errorMessage;

  const TranslationResult({
    required this.originalLines,
    required this.translatedLines,
    required this.targetLanguage,
    this.isSuccess = true,
    this.errorMessage,
  });
}

/// Track metadata container for test fixtures.
class TrackMetadata {
  final String uri;
  final String title;
  final String artist;
  final String? album;
  final int durationMs;
  final String? embeddedLyrics;
  final String? localLrcContent;

  const TrackMetadata({
    required this.uri,
    required this.title,
    required this.artist,
    this.album,
    required this.durationMs,
    this.embeddedLyrics,
    this.localLrcContent,
  });

  int get durationSeconds => (durationMs / 1000).round();
}
