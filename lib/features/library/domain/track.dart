import 'package:tachyon/features/library/domain/album.dart';
import 'package:tachyon/features/library/domain/artist.dart';
import 'package:tachyon/features/library/domain/genre.dart';
import 'package:tachyon/shared/utils/parse_utils.dart';
import 'package:tachyon/shared/utils/waveform_codec.dart';

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

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'file_path': filePath,
      'title': title,
      'track_number': trackNumber,
      'disc_number': discNumber,
      'year': year,
      'duration_ms': durationMs,
      'bitrate': bitrate,
      'sample_rate': sampleRate,
      'channels': channels,
      'codec': codec,
      'file_size': fileSize,
      'modified_at': modifiedAt,
      'replay_gain_track_gain': replayGainTrackGain,
      'replay_gain_track_peak': replayGainTrackPeak,
      'waveform_data': WaveformCodec.encode(waveform),
      'thumbnail_hash': thumbnailHash,

      'album_id': album?.id,
      'artist_ids': artists.map((a) => a.id).toList(),
      'genre_ids': genres.map((g) => g.id).toList(),
    };
  }

  factory Track.fromMap(Map<String, dynamic> map) {
    return Track(
      id: ParserUtils.parseInt(map['id']),
      filePath: ParserUtils.parseString(map['file_path']) ?? '',
      title: ParserUtils.parseString(map['title']) ?? '',
      trackNumber: ParserUtils.parseInt(map['track_number']),
      discNumber: ParserUtils.parseInt(map['disc_number']),
      year: ParserUtils.parseInt(map['year']),
      durationMs: ParserUtils.parseInt(map['duration_ms']) ?? 0,
      bitrate: ParserUtils.parseInt(map['bitrate']),
      sampleRate: ParserUtils.parseInt(map['sample_rate']),
      channels: ParserUtils.parseInt(map['channels']),
      codec: ParserUtils.parseString(map['codec']),
      fileSize: ParserUtils.parseInt(map['file_size']) ?? 0,
      modifiedAt: ParserUtils.parseInt(map['modified_at']) ?? 0,
      replayGainTrackGain: ParserUtils.parseDouble(
        map['replay_gain_track_gain'],
      ),
      replayGainTrackPeak: ParserUtils.parseDouble(
        map['replay_gain_track_peak'],
      ),
      waveform: WaveformCodec.decode(ParserUtils.parseString(map['waveform_data'])),
      thumbnailHash: ParserUtils.parseString(map['thumbnail_hash']),
    );
  }
}
