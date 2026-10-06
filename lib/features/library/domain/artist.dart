import 'album.dart';
import 'track.dart';

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

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'thumbnail_hash': thumbnailHash,
      'album_ids': albums.map((a) => a.id).toList(),
      'track_ids': tracks.map((t) => t.id).toList(),
    };
  }

  factory Artist.fromDbMap(Map<String, dynamic> map) {
    return Artist(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
      thumbnailHash: map['thumbnail_hash'] as String?,
    );
  }
}
