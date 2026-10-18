import 'package:tachyon/core/store/domain/album.dart';
import 'package:tachyon/core/store/domain/track.dart';

class Artist {
  /// The artist's unique identifier.
  final int? id;

  /// The name of the artist.
  final String name;
  final String? thumbnailHash;

  /// The list of albums associated with this artist.
  final List<Album> albums;

  /// The list of tracks associated with this artist.
  final List<Track> tracks;

  /// Returns the number of albums associated with this artist.
  int get albumCount => albums.length;

  /// Returns the number of tracks associated with this artist.
  int get trackCount => tracks.length;

  const Artist({
    this.id,
    required this.name,
    this.thumbnailHash,
    this.albums = const [],
    this.tracks = const [],
  });
}
