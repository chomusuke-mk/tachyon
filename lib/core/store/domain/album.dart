import 'package:tachyon/core/store/domain/artist.dart';
import 'package:tachyon/core/store/domain/track.dart';

/// An album in the local music library catalog.
class Album {
  /// The album's unique identifier.
  final int? id;

  /// The name of the album.
  final String name;

  /// The year the album was released. This is optional and may not be available for all albums.
  final int? year;

  /// Cached artwork file path or URI for the album cover, if available.
  final String? artworkUri;

  /// Primary album artist, if known.
  final Artist? artist;

  /// Ordered list of tracks belonging to this album.
  final List<Track> tracks;

  /// The number of tracks in [tracks].
  int get trackCount => tracks.length;

  /// Creates an [Album] catalog entity.
  const Album({
    this.id,
    required this.name,
    this.year,
    this.artworkUri,
    this.artist,
    this.tracks = const [],
  });
}
