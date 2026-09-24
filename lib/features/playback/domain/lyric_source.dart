export 'package:tachyon/features/playback/domain/lyric_source_state.dart';

/// Represents the origin source of lyrics for a track.
///
/// Hierarchy order:
/// 1. [embedded]: Audio tags (USLT, LYRICS) in the track file.
/// 2. [file]: Contiguous `.lrc` / `.LRC` file in the track's folder.
/// 3. [lrclib]: Remote primary API (`lrclib.net`).
/// 4. [lyricsOvh]: Remote secondary fallback API (`lyrics.ovh`).
enum LyricsSource {
  embedded('embedded'),
  file('file'),
  lrclib('lrclib'),
  lyricsOvh('lyrics_ovh');

  const LyricsSource(this.dbValue);

  /// The string identifier persisted in the SQLite database (`lyrics_source_cache.source`).
  final String dbValue;

  /// Whether this source is a local offline source (embedded tags or contiguous file).
  bool get isLocal => this == LyricsSource.embedded || this == LyricsSource.file;

  /// Whether this source is a remote web API (lrclib or lyricsOvh).
  bool get isRemote => !isLocal;

  /// Priority rank in the search hierarchy (1 = highest, 4 = lowest).
  int get priority => switch (this) {
        LyricsSource.embedded => 1,
        LyricsSource.file => 2,
        LyricsSource.lrclib => 3,
        LyricsSource.lyricsOvh => 4,
      };

  /// Parses a string into a [LyricsSource], supporting legacy and alternative aliases.
  static LyricsSource fromString(String value) {
    return switch (value.trim().toLowerCase()) {
      'embedded' => LyricsSource.embedded,
      'file' || 'lrc_file' || 'lrc' => LyricsSource.file,
      'lrclib' || 'lrclib.net' => LyricsSource.lrclib,
      'lyrics_ovh' || 'lyricsovh' || 'ovh' => LyricsSource.lyricsOvh,
      _ => throw ArgumentError.value(value, 'value', 'Unknown LyricsSource value'),
    };
  }

  /// Parses a database string or identifier into a [LyricsSource].
  static LyricsSource fromDbString(String value) => fromString(value);

  /// Safe parse that returns [defaultValue] (or `null`) instead of throwing on unknown values.
  static LyricsSource? tryParse(String? value, {LyricsSource? defaultValue}) {
    if (value == null) return defaultValue;
    final parsed = switch (value.trim().toLowerCase()) {
      'embedded' => LyricsSource.embedded,
      'file' || 'lrc_file' || 'lrc' => LyricsSource.file,
      'lrclib' || 'lrclib.net' => LyricsSource.lrclib,
      'lyrics_ovh' || 'lyricsovh' || 'ovh' => LyricsSource.lyricsOvh,
      _ => null,
    };
    return parsed ?? defaultValue;
  }
}

/// Backward compatibility typedef alias.
typedef LyricSource = LyricsSource;
