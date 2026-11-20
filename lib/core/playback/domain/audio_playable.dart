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

  /// Unified artwork URI (local cached image path or remote stream/station URL).
  String? get artworkUri;

  /// Primary file system path or stream URI string.
  String get filePath;

  /// Optional ReplayGain track loudness adjustment in decibels (dB).
  double? get replayGainTrackGain;

  /// Optional ReplayGain linear peak amplitude.
  double? get replayGainTrackPeak;

  /// Whether this item represents a continuous livestream without bounded duration.
  bool get isStream;

  /// Converts this playable item into an engine-compatible [ma.AudioSource].
  ma.AudioSource<AudioPlayable> toAudioSource();
}

/// Convenience extension on [ma.AudioSource<AudioPlayable>] when parameterized with [AudioPlayable].
extension EngineItemPlayableExtension on ma.AudioSource<AudioPlayable> {
  /// Unboxes the caller-owned domain object [data] as an [AudioPlayable].
  AudioPlayable? get track => data;
}
