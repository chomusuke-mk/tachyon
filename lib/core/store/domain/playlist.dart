import 'package:tachyon/core/store/domain/track.dart';

/// Category of a [Playlist] distinguishing user playlists from system lists.
enum PlaylistType {
  /// Standard user-created playlist.
  user(0),

  /// Built-in Liked Songs collection.
  liked(1),

  /// Built-in playback History collection.
  history(2);

  /// Integer storage code representing this playlist type.
  final int value;

  /// Associates an integer storage [value] with a [PlaylistType].
  const PlaylistType(this.value);

  /// Parses an integer [val] into a [PlaylistType], defaulting to [PlaylistType.user].
  static PlaylistType fromValue(int? val) {
    return PlaylistType.values.firstWhere(
      (e) => e.value == val,
      orElse: () => PlaylistType.user,
    );
  }
}

/// Ordered track entry belonging to a [Playlist].
class PlaylistEntry {
  /// The entry's unique identifier.
  final int? id;

  /// The position of the track in the playlist. This is used to determine the order of tracks in the playlist.
  final int position;

  /// The timestamp when the track was added to the playlist.
  final int addedAt;

  /// Owning [Playlist] containing this entry, if linked.
  final Playlist? playlist;

  /// Referenced [Track] at this position, if resolved.
  final Track? track;

  /// Creates a [PlaylistEntry] record.
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

/// A user-created or system-managed playlist of tracks.
class Playlist {
  /// Unique database identifier for this playlist, if persisted.
  final int? id;

  /// Display name of the playlist.
  final String name;

  /// Creation timestamp in milliseconds since epoch.
  final int createdAt;

  /// Kind of playlist ([PlaylistType.user], [PlaylistType.liked], or [PlaylistType.history]).
  final PlaylistType type;

  /// Ordered entries belonging to this playlist.
  final List<PlaylistEntry> entries;

  /// Number of entries in [entries].
  int get trackCount => entries.length;

  /// Whether this playlist is a system-managed playlist rather than user-created.
  bool get isSpecial => type != PlaylistType.user;

  /// Ordered list of non-null tracks contained in this playlist.
  List<Track> get tracks =>
      entries.map((e) => e.track).whereType<Track>().toList(growable: false);

  /// Dynamically resolved from the most recently added entry with a valid artwork URI.
  String? get artworkUri {
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
        final uri = track.artworkUri ?? track.album?.artworkUri;
        if (uri != null && uri.trim().isNotEmpty) {
          return uri.trim();
        }
      }
    }
    return null;
  }

  /// Creates a [Playlist] entity.
  const Playlist({
    this.id,
    required this.name,
    required this.createdAt,
    this.type = PlaylistType.user,
    this.entries = const [],
  });
}
