import 'package:tachyon/shared/utils/parse_utils.dart';

import 'track.dart';

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

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'position': position,
      'added_at': addedAt,
      'playlist_id': playlist?.id,
      'track_id': track?.id,
    };
  }

  factory PlaylistEntry.fromMap(Map<String, dynamic> map) {
    return PlaylistEntry(
      id: ParserUtils.parseInt(map['id']),
      position: ParserUtils.parseInt(map['position']) ?? 0,
      addedAt: ParserUtils.parseInt(map['added_at']) ?? 0,
    );
  }
}

class Playlist {
  final int? id;
  final String name;
  final int createdAt;
  final PlaylistType type;
  final List<PlaylistEntry> entries;

  int get trackCount => entries.length;
  bool get isSpecial => type != PlaylistType.user;

  const Playlist({
    this.id,
    required this.name,
    required this.createdAt,
    this.type = PlaylistType.user,
    this.entries = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'created_at': createdAt,
      'type': type.value,
      'entry_ids': entries.map((e) => e.id).toList(),
    };
  }

  factory Playlist.fromMap(
    Map<String, dynamic> map) {
    return Playlist(
      id: ParserUtils.parseInt(map['id']),
      name: ParserUtils.parseString(map['name']) ?? '',
      createdAt: ParserUtils.parseInt(map['created_at']) ?? 0,
      type: PlaylistType.fromValue(ParserUtils.parseInt(map['type'])),
    );
  }
}
