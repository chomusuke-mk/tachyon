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

  factory PlaylistEntry.forQueue({
    required int id,
    int position = 0,
    required Track track,
    int? addedAt,
  }) {
    return PlaylistEntry(
      id: id,
      position: position,
      addedAt: addedAt ?? DateTime.now().millisecondsSinceEpoch,
      track: track,
    );
  }

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

  /// Only for UI
  String? coverHash;

  int get trackCount => entries.length;
  bool get isSpecial => type != PlaylistType.user;

  Playlist({
    this.id,
    required this.name,
    required this.createdAt,
    this.type = PlaylistType.user,
    this.entries = const [],
    this.coverHash,
  });
}
