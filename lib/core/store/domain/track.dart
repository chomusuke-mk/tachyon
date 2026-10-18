import 'package:tachyon/core/store/domain/album.dart';
import 'package:tachyon/core/store/domain/artist.dart';
import 'package:tachyon/core/store/domain/genre.dart';

class Track {
  final int? id;
  final String filePath;
  final String title;
  final int? trackNumber;
  final int? discNumber;
  final int? year;
  final int durationMs;
  final int? bitrate;
  final int? sampleRate;
  final int? channels;
  final String? codec;
  final int fileSize;
  final int modifiedAt;
  final double? replayGainTrackGain;
  final double? replayGainTrackPeak;
  final List<double>? waveform;
  final String? thumbnailHash;

  final Album? album;
  final List<Artist> artists;
  final List<Genre> genres;

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
    this.thumbnailHash,
    this.album,
    this.genres = const [],
    this.artists = const [],
  });

  Duration get duration => Duration(milliseconds: durationMs);
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
}
