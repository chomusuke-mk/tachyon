import 'package:tachyon/core/store/domain/track.dart';

class Genre {
  /// The genre's unique identifier. This is typically assigned by the database or API.
  final int? id;

  /// The name of the genre.
  final String name;

  /// The list of tracks associated with this genre.
  final List<Track> tracks;

  /// Only for UI
  String? coverHash;

  /// Returns the number of tracks associated with this genre.
  int get trackCount => tracks.length;

  Genre({
    this.id,
    required this.name,
    this.tracks = const [],
    this.coverHash,
  });
}
