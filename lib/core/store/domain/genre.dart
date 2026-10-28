import 'package:tachyon/core/store/domain/track.dart';

class Genre {
  /// The genre's unique identifier. This is typically assigned by the database or API.
  final int? id;

  /// The name of the genre.
  final String name;

  /// The list of tracks associated with this genre.
  final List<Track> tracks;

  /// Returns the number of tracks associated with this genre.
  int get trackCount => tracks.length;

  /// Dynamically resolved from the first track with a non-empty cover hash.
  String? get coverHash {
    for (final track in tracks) {
      final hash = track.thumbnailHash ?? track.album?.thumbnailHash;
      if (hash != null && hash.trim().isNotEmpty) {
        return hash.trim();
      }
    }
    return null;
  }

  const Genre({
    this.id,
    required this.name,
    this.tracks = const [],
  });
}
