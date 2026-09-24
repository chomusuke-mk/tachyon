import 'package:flutter/foundation.dart';
import 'package:tachyon/features/playback/domain/lyric_source.dart';

/// Represents the query resolution state of lyrics from a specific [LyricsSource].
enum LyricsSourceState {
  /// Lyrics were successfully fetched or extracted from this source.
  found('FOUND'),

  /// The source confirmed that lyrics do not exist (e.g. HTTP 404).
  /// Future queries to this source for this track must be skipped.
  notFound('NOT_FOUND'),

  /// The query failed due to a transient issue (network drop, HTTP 5xx, HTTP 429).
  /// Must NOT prevent future retries.
  temporaryError('TEMPORARY_ERROR');

  const LyricsSourceState(this.dbValue);

  /// String value stored in SQLite `lyrics_source_cache.state`.
  final String dbValue;

  /// Parses a string into a [LyricsSourceState].
  static LyricsSourceState fromString(String value) {
    return switch (value.trim().toUpperCase()) {
      'FOUND' => LyricsSourceState.found,
      'NOT_FOUND' || 'NOTFOUND' => LyricsSourceState.notFound,
      'TEMPORARY_ERROR' || 'TEMPORARYERROR' => LyricsSourceState.temporaryError,
      _ => throw ArgumentError.value(
          value,
          'value',
          'Unknown LyricsSourceState value',
        ),
    };
  }

  /// Parses a database string value into a [LyricsSourceState].
  static LyricsSourceState fromDbString(String value) => fromString(value);

  /// Safe parse that returns [defaultValue] (or `null`) instead of throwing on unknown values.
  static LyricsSourceState? tryParse(
    String? value, {
    LyricsSourceState? defaultValue,
  }) {
    if (value == null) return defaultValue;
    try {
      return fromString(value);
    } catch (_) {
      return defaultValue;
    }
  }
}

/// Backward compatibility typedef alias.
typedef LyricSourceState = LyricsSourceState;

/// Immutable model representing an entry in `lyrics_source_cache`.
///
/// Tracks the resolution state, raw LRC content, synchronization flag, and
/// update timestamp for a specific [LyricsSource] and track [keyHash].
@immutable
class LyricsSourceEntry {
  /// SHA-256 hash uniquely identifying the track canonical attributes or URI.
  final String keyHash;

  /// The source origin (embedded, file, lrclib, lyricsOvh).
  final LyricsSource source;

  /// Resolution state: found, notFound, or temporaryError.
  final LyricsSourceState state;

  /// Raw LRC or plain text lyrics content if [state] is [LyricsSourceState.found].
  /// Null if notFound or temporaryError.
  final String? rawLrc;

  /// Whether the lyrics contain synchronized timestamps.
  final bool isSynced;

  /// Milliseconds since epoch when this entry was created or updated.
  final int updatedAt;

  const LyricsSourceEntry({
    required this.keyHash,
    required this.source,
    required this.state,
    this.rawLrc,
    this.isSynced = false,
    required this.updatedAt,
  });

  /// Convenience factory for a successful lyrics resolution.
  factory LyricsSourceEntry.found({
    required String keyHash,
    required LyricsSource source,
    required String rawLrc,
    bool? isSynced,
    int? updatedAt,
  }) {
    final effectiveSynced = isSynced ?? _detectIsSynced(rawLrc);
    return LyricsSourceEntry(
      keyHash: keyHash,
      source: source,
      state: LyricsSourceState.found,
      rawLrc: rawLrc,
      isSynced: effectiveSynced,
      updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Convenience factory for a confirmed absent lyrics resolution (e.g. 404).
  factory LyricsSourceEntry.notFound({
    required String keyHash,
    required LyricsSource source,
    int? updatedAt,
  }) {
    return LyricsSourceEntry(
      keyHash: keyHash,
      source: source,
      state: LyricsSourceState.notFound,
      rawLrc: null,
      isSynced: false,
      updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Convenience factory for a transient error (e.g. network timeout or 429).
  factory LyricsSourceEntry.temporaryError({
    required String keyHash,
    required LyricsSource source,
    int? updatedAt,
  }) {
    return LyricsSourceEntry(
      keyHash: keyHash,
      source: source,
      state: LyricsSourceState.temporaryError,
      rawLrc: null,
      isSynced: false,
      updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Deserializes an entry from a SQLite database row map.
  factory LyricsSourceEntry.fromDbMap(Map<String, dynamic> map) {
    final rawSync = map['is_synced'];
    final isSynced = rawSync is bool
        ? rawSync
        : (rawSync is num ? rawSync.toInt() == 1 : false);

    final rawSource = map['source'] as String? ?? '';
    final rawState = map['state'] as String? ?? '';

    return LyricsSourceEntry(
      keyHash: map['key_hash']! as String,
      source: LyricsSource.tryParse(rawSource) ?? LyricsSource.fromString(rawSource),
      state: LyricsSourceState.tryParse(rawState) ?? LyricsSourceState.fromString(rawState),
      rawLrc: map['raw_lrc'] as String?,
      isSynced: isSynced,
      updatedAt: (map['updated_at'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Serializes the entry to a SQLite row map matching `lyrics_source_cache`.
  Map<String, Object?> toDbMap() {
    return {
      'key_hash': keyHash,
      'source': source.dbValue,
      'state': state.dbValue,
      'raw_lrc': rawLrc,
      'is_synced': isSynced ? 1 : 0,
      'updated_at': updatedAt > 0 ? updatedAt : DateTime.now().millisecondsSinceEpoch,
    };
  }

  /// Serializes to JSON.
  Map<String, dynamic> toJson() {
    return {
      'keyHash': keyHash,
      'source': source.name,
      'state': state.name,
      'rawLrc': rawLrc,
      'isSynced': isSynced,
      'updatedAt': updatedAt,
    };
  }

  /// Deserializes from JSON.
  factory LyricsSourceEntry.fromJson(Map<String, dynamic> json) {
    final rawSource = (json['source'] ?? json['sourceName']) as String? ?? '';
    final rawState = (json['state'] ?? json['stateName']) as String? ?? '';
    final rawSync = json['isSynced'] ?? json['is_synced'];
    final isSynced = rawSync is bool
        ? rawSync
        : (rawSync is num ? rawSync.toInt() == 1 : false);

    return LyricsSourceEntry(
      keyHash: ((json['keyHash'] ?? json['key_hash']) as String?) ?? '',
      source: LyricsSource.tryParse(rawSource) ?? LyricsSource.fromString(rawSource),
      state: LyricsSourceState.tryParse(rawState) ?? LyricsSourceState.fromString(rawState),
      rawLrc: (json['rawLrc'] ?? json['raw_lrc']) as String?,
      isSynced: isSynced,
      updatedAt: ((json['updatedAt'] ?? json['updated_at']) as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
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

  bool get isFound => state == LyricsSourceState.found;
  bool get isNotFound => state == LyricsSourceState.notFound;
  bool get isTemporaryError => state == LyricsSourceState.temporaryError;
  bool get hasLyrics => isFound && rawLrc != null && rawLrc!.trim().isNotEmpty;

  static bool _detectIsSynced(String rawLrc) {
    return RegExp(r'\[\d{1,}:\d{2}\.\d{2,3}\]').hasMatch(rawLrc);
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
  String toString() {
    return 'LyricsSourceEntry(keyHash: $keyHash, source: ${source.dbValue}, '
        'state: ${state.dbValue}, isSynced: $isSynced, updatedAt: $updatedAt, '
        'hasLyrics: $hasLyrics)';
  }
}

/// Backward compatibility typedef alias.
typedef LyricSourceEntry = LyricsSourceEntry;
