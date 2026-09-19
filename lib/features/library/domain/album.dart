import 'package:flutter/foundation.dart';

import 'track.dart';

@immutable
class Album {
  final int? id;
  final String name;
  final int? artistId;
  final String? artistName;
  final int? year;
  final int trackCount;
  final List<Track> tracks;

  const Album({
    this.id,
    required this.name,
    this.artistId,
    this.artistName,
    this.year,
    this.trackCount = 0,
    this.tracks = const [],
  });

  Album copyWith({
    int? id,
    String? name,
    int? artistId,
    String? artistName,
    int? year,
    int? trackCount,
    List<Track>? tracks,
  }) {
    return Album(
      id: id ?? this.id,
      name: name ?? this.name,
      artistId: artistId ?? this.artistId,
      artistName: artistName ?? this.artistName,
      year: year ?? this.year,
      trackCount: trackCount ?? this.trackCount,
      tracks: tracks ?? this.tracks,
    );
  }

  Map<String, dynamic> toDbMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'artist_id': artistId,
      'artist_name': artistName,
      'year': year,
      'track_count': trackCount,
    };
  }

  factory Album.fromDbMap(
    Map<String, dynamic> map, {
    List<Track> tracks = const [],
  }) {
    return Album(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
      artistId: map['artist_id'] as int?,
      artistName: map['artist_name'] as String?,
      year: map['year'] as int?,
      trackCount: map['track_count'] as int? ?? tracks.length,
      tracks: tracks,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'artistId': artistId,
      'artistName': artistName,
      'year': year,
      'trackCount': trackCount,
      'tracks': tracks.map((t) => t.toJson()).toList(),
    };
  }

  factory Album.fromJson(Map<String, dynamic> json) {
    return Album(
      id: json['id'] as int?,
      name: json['name'] as String? ?? '',
      artistId: (json['artistId'] ?? json['artist_id']) as int?,
      artistName: (json['artistName'] ?? json['artist_name']) as String?,
      year: json['year'] as int?,
      trackCount:
          ((json['trackCount'] ?? json['track_count']) as num?)?.toInt() ?? 0,
      tracks:
          (json['tracks'] as List<dynamic>?)
              ?.map((e) => Track.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Album &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          artistId == other.artistId &&
          artistName == other.artistName &&
          year == other.year &&
          trackCount == other.trackCount &&
          listEquals(tracks, other.tracks);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    artistId,
    artistName,
    year,
    trackCount,
    Object.hashAll(tracks),
  );
}
