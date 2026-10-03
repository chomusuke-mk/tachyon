import 'package:tachyon/features/library/domain/album.dart';
import 'package:tachyon/features/library/domain/artist.dart';
import 'package:tachyon/features/library/domain/genre.dart';
import 'package:tachyon/features/library/domain/lyrics.dart';
import 'package:tachyon/shared/utils/parse_utils.dart';

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

  final Album? album;
  final Lyrics? lyrics;
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

    this.album,
    this.lyrics,
    this.genres = const [],
    this.artists = const [],
  });

  Duration get duration => Duration(milliseconds: durationMs);
  DateTime get modifiedDateTime =>
      DateTime.fromMillisecondsSinceEpoch(modifiedAt);

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

      'lyrics_id': lyrics?.id,
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
    );
  }
}
