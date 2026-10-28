import 'package:miniaudio_player/miniaudio_player.dart' as ma;

/// Unified domain abstraction representing any playable audio asset in Tachyon.
///
/// Implemented by local library tracks ([Track]) and extensible to remote
/// streams, podcasts, or online radio stations.
abstract interface class AudioPlayable {
  /// Unique identifier (if persisted in the local database).
  int? get id;

  /// Display title of the audio item.
  String get title;

  /// Formatted list of contributing artist names.
  List<String> get artistNames;

  /// Optional album or container collection title.
  String? get albumTitle;

  /// Total duration of the track (or [Duration.zero] for infinite livestreams).
  Duration get duration;

  /// Optional thumbnail hash used by [AlbumArtImage] to resolve cached artwork.
  String? get thumbnailHash;

  /// Primary file system path or stream URI string.
  String get filePath;

  /// Optional ReplayGain track loudness adjustment in decibels (dB).
  double? get replayGainTrackGain;

  /// Optional ReplayGain linear peak amplitude.
  double? get replayGainTrackPeak;

  /// Whether this item represents a continuous livestream without bounded duration.
  bool get isStream;

  /// Converts this playable item into an engine-compatible [ma.EngineItem].
  ma.EngineItem<AudioPlayable> toEngineItem({int position = 0});
}

/// Convenience extension on [ma.EngineItem] when parameterized with [AudioPlayable].
extension EngineItemPlayableExtension on ma.EngineItem<AudioPlayable> {
  /// Unboxes the caller-owned domain object [data] as an [AudioPlayable].
  AudioPlayable? get track => data;
}
