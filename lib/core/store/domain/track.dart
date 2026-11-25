import 'package:miniaudio_player/miniaudio_player.dart' as ma;
import 'package:tachyon/core/playback/domain/audio_playable.dart';
import 'package:tachyon/core/store/domain/album.dart';
import 'package:tachyon/core/store/domain/artist.dart';
import 'package:tachyon/core/store/domain/genre.dart';

/// Local or provisional audio track entity implementing [AudioPlayable].
class Track implements AudioPlayable {
  @override
  final int? id;
  @override
  final String filePath;
  @override
  final String title;

  /// Track number within its disc, if tagged.
  final int? trackNumber;

  /// Disc number within a multi-disc release, if tagged.
  final int? discNumber;

  /// Release year, if tagged.
  final int? year;

  /// Total duration in milliseconds.
  final int durationMs;

  /// Encoded audio bitrate in bits per second, if known.
  final int? bitrate;

  /// Audio sample rate in Hz, if known.
  final int? sampleRate;

  /// Number of audio channels, if known.
  final int? channels;

  /// Audio codec or format label, if known.
  final String? codec;

  /// Audio file size in bytes.
  final int fileSize;

  /// Last modification timestamp in milliseconds since epoch.
  final int modifiedAt;

  @override
  final double? replayGainTrackGain;
  @override
  final double? replayGainTrackPeak;

  /// Normalized precomputed waveform samples in `[0.0, 1.0]`, if extracted.
  final List<double>? waveform;

  @override
  final String? artworkUri;

  /// Associated [Album] record, if linked.
  final Album? album;

  /// Contributing [Artist] records linked to this track.
  final List<Artist> artists;

  /// Associated [Genre] records linked to this track.
  final List<Genre> genres;

  /// Whether this track is a provisional discovery entry awaiting full tag extraction.
  final bool isMetadataPending;

  /// Creates an immutable [Track] entity.
  const Track({
    this.id,
    required this.filePath,
    required this.title,
    this.trackNumber,
    this.discNumber = 1,
    this.year,
    required this.durationMs,
    this.bitrate,
    this.sampleRate,
    this.channels,
    this.codec,
    required this.fileSize,
    required this.modifiedAt,
    this.replayGainTrackGain,
    this.replayGainTrackPeak,
    this.waveform,
    this.artworkUri,
    this.album,
    this.genres = const [],
    this.artists = const [],
    this.isMetadataPending = false,
  });

  @override
  Duration get duration => Duration(milliseconds: durationMs);

  /// File modification timestamp derived from [modifiedAt].
  DateTime get modifiedDateTime =>
      DateTime.fromMillisecondsSinceEpoch(modifiedAt);

  /// Samples the waveform height corresponding to a specific playback [position]
  /// given the track's [totalDuration]. Returns 0.0 if waveform is empty or duration is 0.
  double getPointAtPosition(Duration position, Duration totalDuration) {
    if (waveform == null || waveform!.isEmpty) return 0.0;
    if (totalDuration.inMilliseconds <= 0) return 0.0;
    final progress =
        (position.inMilliseconds / totalDuration.inMilliseconds).clamp(0.0, 1.0);
    return getPointAtProgress(progress);
  }

  /// Samples the waveform height at a fractional [progress] between `0.0` and `1.0`.
  double getPointAtProgress(double progress) {
    if (waveform == null || waveform!.isEmpty) return 0.0;
    final clamped = progress.clamp(0.0, 1.0);
    final index = (clamped * (waveform!.length - 1)).round();
    return waveform![index];
  }

  @override
  List<String> get artistNames => artists.map((a) => a.name).toList();

  @override
  String? get albumTitle => album?.name;

  @override
  bool get isStream => false;

  @override
  ma.AudioSource<AudioPlayable> toAudioSource() {
    if (filePath.startsWith('http://') || filePath.startsWith('https://')) {
      final uri = Uri.tryParse(filePath);
      if (uri != null) {
        return ma.AudioSource<AudioPlayable>(
          uri,
          data: this,
          replayGainDb: replayGainTrackGain,
          replayPeak: replayGainTrackPeak,
        );
      }
    }
    return ma.AudioSource<AudioPlayable>(
      filePath,
      data: this,
      replayGainDb: replayGainTrackGain,
      replayPeak: replayGainTrackPeak,
    );
  }
}
