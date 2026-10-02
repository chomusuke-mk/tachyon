import 'package:flutter/foundation.dart';
import 'package:tachyon/features/library/domain/track.dart';

enum Loop {
  off('off'),
  one('one'),
  all('all');

  Loop next() {
    switch (this) {
      case Loop.off:
        return Loop.all;
      case Loop.all:
        return Loop.one;
      case Loop.one:
        return Loop.off;
    }
  }

  const Loop(this.repr);
  final String repr;
  static Loop fromString(String? val) {
    return Loop.values.firstWhere((e) => e.repr == val, orElse: () => Loop.off);
  }
}

@immutable
class QueueItem {
  final String id;
  final int? trackId;
  final String filePath;
  final String title;
  final String artist;
  final List<String> artists;
  final String album;
  final Duration duration;
  final String? coverPath;
  final Map<String, dynamic> extras;

  const QueueItem({
    required this.id,
    this.trackId,
    required this.filePath,
    required this.title,
    required this.artist,
    this.artists = const [],
    required this.album,
    required this.duration,
    this.coverPath,
    this.extras = const {},
  });

  factory QueueItem.fromTrack(Track track, {String? id}) {
    return QueueItem(
      id: id ?? '${track.filePath}_${DateTime.now().microsecondsSinceEpoch}',
      trackId: track.id,
      filePath: track.filePath,
      title: track.title,
      artist: track.artist ?? 'Unknown Artist',
      artists: track.artists,
      album: track.album ?? 'Unknown Album',
      duration: track.duration,
      extras: {
        'year': track.year,
        'trackNumber': track.trackNumber,
        'discNumber': track.discNumber,
        'bitrate': track.bitrate,
        'sampleRate': track.sampleRate,
        'channels': track.channels,
        'lyrics': track.lyrics,
        'codec': track.codec,
      },
    );
  }

  Track toTrack() {
    return Track(
      id: trackId,
      filePath: filePath,
      title: title,
      artist: artist,
      artists: artists,
      album: album,
      durationMs: duration.inMilliseconds,
      fileSize: 0,
      modifiedAt: 0,
      lyrics: extras['lyrics'] as String?,
    );
  }

  QueueItem copyWith({
    String? id,
    int? trackId,
    String? filePath,
    String? title,
    String? artist,
    List<String>? artists,
    String? album,
    Duration? duration,
    String? coverPath,
    Map<String, dynamic>? extras,
  }) {
    return QueueItem(
      id: id ?? this.id,
      trackId: trackId ?? this.trackId,
      filePath: filePath ?? this.filePath,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      artists: artists ?? this.artists,
      album: album ?? this.album,
      duration: duration ?? this.duration,
      coverPath: coverPath ?? this.coverPath,
      extras: extras ?? this.extras,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'trackId': trackId,
      'filePath': filePath,
      'file_path': filePath,
      'title': title,
      'artist': artist,
      'artists': artists,
      'album': album,
      'durationMs': duration.inMilliseconds,
      'coverPath': coverPath,
      'extras': extras,
    };
  }

  factory QueueItem.fromJson(Map<String, dynamic> json) {
    return QueueItem(
      id: json['id'] as String? ?? '',
      trackId: json['trackId'] as int?,
      filePath: (json['filePath'] ?? json['file_path'] ?? json['uri']) as String? ?? '',
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      artists:
          (json['artists'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      album: json['album'] as String? ?? '',
      duration: Duration(
        milliseconds:
            ((json['durationMs'] ?? json['duration']) as num?)?.toInt() ?? 0,
      ),
      coverPath: json['coverPath'] as String?,
      extras: json['extras'] as Map<String, dynamic>? ?? const {},
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QueueItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          trackId == other.trackId &&
          filePath == other.filePath &&
          title == other.title &&
          artist == other.artist &&
          listEquals(artists, other.artists) &&
          album == other.album &&
          duration == other.duration &&
          coverPath == other.coverPath &&
          mapEquals(extras, other.extras);

  @override
  int get hashCode => Object.hash(
    id,
    trackId,
    filePath,
    title,
    artist,
    Object.hashAll(artists),
    album,
    duration,
    coverPath,
    Object.hashAll(extras.keys),
  );
}
