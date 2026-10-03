import 'package:tachyon/features/library/domain/artist.dart';
import 'package:tachyon/shared/utils/parse_utils.dart';

import 'track.dart';

class Album {
  /// The album's unique identifier.
  final int? id;
  /// The name of the album.
  final String name;
  /// The year the album was released. This is optional and may not be available for all albums.
  final int? year;

  final Artist? artist;
  final List<Track> tracks;

  int get trackCount => tracks.length;

  const Album({
    this.id,
    required this.name,
    this.year,

    this.artist,
    this.tracks = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'year': year,

      'artist_id': artist?.id,
      'track_ids': tracks.map((t) => t.id).toList(),
    };
  }

  factory Album.fromMap(Map<String, dynamic> map) {
    return Album(
      id: ParserUtils.parseInt(map['id']),
      name: ParserUtils.parseString(map['name']) ?? '',
      year: map['year'] as int?,
    );
  }
}
