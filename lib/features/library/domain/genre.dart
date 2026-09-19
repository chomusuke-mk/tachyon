import 'package:flutter/foundation.dart';
import 'track.dart';

@immutable
class Genre {
  final int? id;
  final String name;
  final int trackCount;
  final List<Track> tracks;

  const Genre({
    this.id,
    required this.name,
    this.trackCount = 0,
    this.tracks = const [],
  });

  Genre copyWith({
    int? id,
    String? name,
    int? trackCount,
    List<Track>? tracks,
  }) {
    return Genre(
      id: id ?? this.id,
      name: name ?? this.name,
      trackCount: trackCount ?? this.trackCount,
      tracks: tracks ?? this.tracks,
    );
  }

  Map<String, dynamic> toDbMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
    };
  }

  factory Genre.fromDbMap(Map<String, dynamic> map, {List<Track> tracks = const []}) {
    return Genre(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
      trackCount: (map['track_count'] as int?) ?? tracks.length,
      tracks: tracks,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'trackCount': trackCount,
      'tracks': tracks.map((t) => t.toJson()).toList(),
    };
  }

  factory Genre.fromJson(Map<String, dynamic> json) {
    return Genre(
      id: json['id'] as int?,
      name: json['name'] as String? ?? '',
      trackCount: ((json['trackCount'] ?? json['track_count']) as num?)?.toInt() ?? 0,
      tracks: (json['tracks'] as List<dynamic>?)
              ?.map((e) => Track.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Genre &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          trackCount == other.trackCount &&
          listEquals(tracks, other.tracks);

  @override
  int get hashCode => Object.hash(
        id,
        name,
        trackCount,
        Object.hashAll(tracks),
      );
}
