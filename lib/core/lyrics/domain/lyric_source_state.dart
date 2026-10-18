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
