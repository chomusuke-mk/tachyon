import 'package:tachyon/core/store/domain/artist.dart';
import 'package:tachyon/core/store/domain/track.dart';

class Album {
  /// The album's unique identifier.
  final int? id;

  /// The name of the album.
  final String name;

  /// The year the album was released. This is optional and may not be available for all albums.
  final int? year;
  final String? thumbnailHash;

  final Artist? artist;
  final List<Track> tracks;

  int get trackCount => tracks.length;

  const Album({
    this.id,
    required this.name,
    this.year,
    this.thumbnailHash,
    this.artist,
    this.tracks = const [],
  });
}
