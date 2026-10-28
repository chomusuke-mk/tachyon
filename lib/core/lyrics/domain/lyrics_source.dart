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

  /// The string identifier persisted in the SQLite database (`lyrics.source`).
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

  /// Parses a value persisted in `lyrics.source`.
  static LyricsSource fromDbString(String value) => LyricsSource.values.firstWhere(
        (s) => s.dbValue == value,
        orElse: () => throw ArgumentError.value(value, 'value', 'Unknown LyricsSource value'),
      );
}

/// Represents the query resolution state of lyrics from a specific source,
/// persisted in `lyrics.state`.
enum LyricsSourceState {
  /// Lyrics were successfully fetched or extracted from this source.
  found('FOUND'),

  /// The source confirmed that lyrics do not exist (e.g. HTTP 404).
  /// Future queries to this source for this track must be skipped.
  notFound('NOT_FOUND'),

  /// The query failed due to a transient issue (network drop, HTTP 5xx, HTTP 429).
  /// Never persisted, so future retries remain possible.
  temporaryError('TEMPORARY_ERROR');

  const LyricsSourceState(this.dbValue);

  /// String value stored in SQLite `lyrics.state`.
  final String dbValue;

  /// Parses a value persisted in `lyrics.state`.
  static LyricsSourceState fromDbString(String value) => LyricsSourceState.values.firstWhere(
        (s) => s.dbValue == value,
        orElse: () => throw ArgumentError.value(value, 'value', 'Unknown LyricsSourceState value'),
      );
}
