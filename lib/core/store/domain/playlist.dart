import 'package:tachyon/core/store/domain/track.dart';

enum PlaylistType {
  user(0),
  liked(1),
  history(2);

  final int value;
  const PlaylistType(this.value);

  static PlaylistType fromValue(int? val) {
    return PlaylistType.values.firstWhere(
      (e) => e.value == val,
      orElse: () => PlaylistType.user,
    );
  }
}

class PlaylistEntry {
  /// The entry's unique identifier.
  final int? id;

  /// The position of the track in the playlist. This is used to determine the order of tracks in the playlist.
  final int position;

  /// The timestamp when the track was added to the playlist.
  final int addedAt;

  final Playlist? playlist;
  final Track? track;

  const PlaylistEntry({
    this.id,
    required this.position,
    required this.addedAt,
    this.track,
    this.playlist,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaylistEntry &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          position == other.position &&
          track == other.track;

  @override
  int get hashCode => Object.hash(id, position, track);
}

class Playlist {
  final int? id;
  final String name;
  final int createdAt;
  final PlaylistType type;
  final List<PlaylistEntry> entries;

  int get trackCount => entries.length;
  bool get isSpecial => type != PlaylistType.user;

  /// Dynamically resolved from the most recently added entry with a valid cover hash.
  String? get coverHash {
    if (entries.isEmpty) return null;
    final sorted = List<PlaylistEntry>.from(entries)
      ..sort((a, b) {
        final cmp = b.addedAt.compareTo(a.addedAt);
        if (cmp != 0) return cmp;
        return b.position.compareTo(a.position);
      });
    for (final entry in sorted) {
      final track = entry.track;
      if (track != null) {
        final hash = track.thumbnailHash ?? track.album?.thumbnailHash;
        if (hash != null && hash.trim().isNotEmpty) {
          return hash.trim();
        }
      }
    }
    return null;
  }

  const Playlist({
    this.id,
    required this.name,
    required this.createdAt,
    this.type = PlaylistType.user,
    this.entries = const [],
  });
}
