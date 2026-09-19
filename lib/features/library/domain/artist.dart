import 'package:flutter/foundation.dart';
import 'album.dart';
import 'track.dart';

@immutable
class Artist {
  final int? id;
  final String name;
  final int trackCount;
  final int albumCount;
  final List<Album> albums;
  final List<Track> tracks;

  const Artist({
    this.id,
    required this.name,
    this.trackCount = 0,
    this.albumCount = 0,
    this.albums = const [],
    this.tracks = const [],
  });

  Artist copyWith({
    int? id,
    String? name,
    int? trackCount,
    int? albumCount,
    List<Album>? albums,
    List<Track>? tracks,
  }) {
    return Artist(
      id: id ?? this.id,
      name: name ?? this.name,
      trackCount: trackCount ?? this.trackCount,
      albumCount: albumCount ?? this.albumCount,
      albums: albums ?? this.albums,
      tracks: tracks ?? this.tracks,
    );
  }

  Map<String, dynamic> toDbMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'track_count': trackCount,
      'album_count': albumCount,
    };
  }

  factory Artist.fromDbMap(
    Map<String, dynamic> map, {
    List<Album> albums = const [],
    List<Track> tracks = const [],
  }) {
    return Artist(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
      trackCount: map['track_count'] as int? ?? tracks.length,
      albumCount: map['album_count'] as int? ?? albums.length,
      albums: albums,
      tracks: tracks,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'trackCount': trackCount,
      'albumCount': albumCount,
      'albums': albums.map((a) => a.toJson()).toList(),
      'tracks': tracks.map((t) => t.toJson()).toList(),
    };
  }

  factory Artist.fromJson(Map<String, dynamic> json) {
    return Artist(
      id: json['id'] as int?,
      name: json['name'] as String? ?? '',
      trackCount: ((json['trackCount'] ?? json['track_count']) as num?)?.toInt() ?? 0,
      albumCount: ((json['albumCount'] ?? json['album_count']) as num?)?.toInt() ?? 0,
      albums: (json['albums'] as List<dynamic>?)
              ?.map((e) => Album.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      tracks: (json['tracks'] as List<dynamic>?)
              ?.map((e) => Track.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Artist &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          trackCount == other.trackCount &&
          albumCount == other.albumCount &&
          listEquals(albums, other.albums) &&
          listEquals(tracks, other.tracks);

  @override
  int get hashCode => Object.hash(
        id,
        name,
        trackCount,
        albumCount,
        Object.hashAll(albums),
        Object.hashAll(tracks),
      );
}
