import 'track.dart';

class Genre {
  /// The genre's unique identifier. This is typically assigned by the database or API.
  final int? id;

  /// The name of the genre.
  final String name;

  /// The list of tracks associated with this genre.
  final List<Track> tracks;

  /// Returns the number of tracks associated with this genre.
  int get trackCount => tracks.length;

  const Genre({this.id, required this.name, this.tracks = const []});

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'track_ids': tracks.map((t) => t.id).toList(),
    };
  }

  factory Genre.fromMap(Map<String, dynamic> map) {
    return Genre(id: map['id'] as int?, name: map['name'] as String? ?? '');
  }
}
