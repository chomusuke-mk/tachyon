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

  /// Dynamically resolved from the first track with a non-empty artwork URI.
  String? get artworkUri {
    for (final track in tracks) {
      final uri = track.artworkUri ?? track.album?.artworkUri;
      if (uri != null && uri.trim().isNotEmpty) {
        return uri.trim();
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
