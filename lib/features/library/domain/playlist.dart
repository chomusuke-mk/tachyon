import 'package:flutter/foundation.dart';

import 'track.dart';

enum PlaylistType {
  user(0),
  liked(1),
  history(2);

  final int value;
  const PlaylistType(this.value);

  static PlaylistType fromValue(int val) {
    return PlaylistType.values.firstWhere(
      (e) => e.value == val,
      orElse: () => PlaylistType.user,
    );
  }
}

@immutable
class PlaylistEntry {
  final int? id;
  final int playlistId;
  final int? trackId;
  final String filePath;
  final String? customTitle;
  final int position;
  final int addedAt;
  final Track? track;

  const PlaylistEntry({
    this.id,
    required this.playlistId,
    this.trackId,
    required this.filePath,
    this.customTitle,
    required this.position,
    required this.addedAt,
    this.track,
  });

  PlaylistEntry copyWith({
    int? id,
    int? playlistId,
    int? trackId,
    String? filePath,
    String? customTitle,
    int? position,
    int? addedAt,
    Track? track,
  }) {
    return PlaylistEntry(
      id: id ?? this.id,
      playlistId: playlistId ?? this.playlistId,
      trackId: trackId ?? this.trackId,
      filePath: filePath ?? this.filePath,
      customTitle: customTitle ?? this.customTitle,
      position: position ?? this.position,
      addedAt: addedAt ?? this.addedAt,
      track: track ?? this.track,
    );
  }

  Map<String, dynamic> toDbMap() {
    return {
      if (id != null) 'id': id,
      'playlist_id': playlistId,
      'track_id': trackId,
      'file_path': filePath,
      'custom_title': customTitle,
      'position': position,
      'added_at': addedAt,
    };
  }

  factory PlaylistEntry.fromDbMap(Map<String, dynamic> map, {Track? track}) {
    return PlaylistEntry(
      id: map['id'] as int?,
      playlistId: (map['playlist_id'] as int?) ?? 0,
      trackId: map['track_id'] as int?,
      filePath: map['file_path'] as String? ?? '',
      customTitle: map['custom_title'] as String?,
      position: (map['position'] as int?) ?? 0,
      addedAt: (map['added_at'] as int?) ?? 0,
      track: track,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'playlistId': playlistId,
      'trackId': trackId,
      'filePath': filePath,
      'file_path': filePath,
      'customTitle': customTitle,
      'position': position,
      'addedAt': addedAt,
      'track': track?.toJson(),
    };
  }

  factory PlaylistEntry.fromJson(Map<String, dynamic> json) {
    return PlaylistEntry(
      id: json['id'] as int?,
      playlistId:
          ((json['playlistId'] ?? json['playlist_id']) as num?)?.toInt() ?? 0,
      trackId: (json['trackId'] ?? json['track_id']) as int?,
      filePath: (json['filePath'] ?? json['file_path']) as String? ?? '',
      customTitle: (json['customTitle'] ?? json['custom_title']) as String?,
      position: ((json['position']) as num?)?.toInt() ?? 0,
      addedAt: ((json['addedAt'] ?? json['added_at']) as num?)?.toInt() ?? 0,
      track: json['track'] != null
          ? Track.fromJson(json['track'] as Map<String, dynamic>)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaylistEntry &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          playlistId == other.playlistId &&
          trackId == other.trackId &&
          filePath == other.filePath &&
          customTitle == other.customTitle &&
          position == other.position &&
          addedAt == other.addedAt &&
          track == other.track;

  @override
  int get hashCode => Object.hash(
    id,
    playlistId,
    trackId,
    filePath,
    customTitle,
    position,
    addedAt,
    track,
  );
}

@immutable
class Playlist {
  final int? id;
  final String name;
  final int createdAt;
  final PlaylistType type;
  final int? explicitTrackCount;
  final List<PlaylistEntry> entries;

  const Playlist({
    this.id,
    required this.name,
    required this.createdAt,
    this.type = PlaylistType.user,
    this.explicitTrackCount,
    this.entries = const [],
  });

  int get trackCount =>
      entries.isNotEmpty ? entries.length : (explicitTrackCount ?? 0);
  int get isSpecial => type.value;
  bool get isSpecialPlaylist => type != PlaylistType.user;

  Playlist copyWith({
    int? id,
    String? name,
    int? createdAt,
    PlaylistType? type,
    int? explicitTrackCount,
    List<PlaylistEntry>? entries,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      type: type ?? this.type,
      explicitTrackCount: explicitTrackCount ?? this.explicitTrackCount,
      entries: entries ?? this.entries,
    );
  }

  Map<String, dynamic> toDbMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'created_at': createdAt,
      'is_special': type.value,
    };
  }

  factory Playlist.fromDbMap(
    Map<String, dynamic> map, {
    List<PlaylistEntry> entries = const [],
  }) {
    return Playlist(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
      createdAt: (map['created_at'] as int?) ?? 0,
      type: PlaylistType.fromValue((map['is_special'] as int?) ?? 0),
      explicitTrackCount: (map['track_count'] as int?) ?? entries.length,
      entries: entries,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt,
      'type': type.value,
      'isSpecial': isSpecial,
      'trackCount': trackCount,
      'entries': entries.map((e) => e.toJson()).toList(),
    };
  }

  factory Playlist.fromJson(Map<String, dynamic> json) {
    final typeVal =
        (json['type'] ?? json['is_special'] ?? json['isSpecial']) as int? ?? 0;
    return Playlist(
      id: json['id'] as int?,
      name: json['name'] as String? ?? '',
      createdAt:
          ((json['createdAt'] ?? json['created_at']) as num?)?.toInt() ?? 0,
      type: PlaylistType.fromValue(typeVal),
      explicitTrackCount:
          ((json['trackCount'] ?? json['track_count']) as num?)?.toInt() ?? 0,
      entries:
          (json['entries'] as List<dynamic>?)
              ?.map((e) => PlaylistEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Playlist &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          createdAt == other.createdAt &&
          type == other.type &&
          listEquals(entries, other.entries);

  @override
  int get hashCode =>
      Object.hash(id, name, createdAt, type, Object.hashAll(entries));
}
