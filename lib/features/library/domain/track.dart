import 'package:flutter/foundation.dart';

@immutable
class Track {
  final int? id;
  final String uri;
  final String title;
  final int? albumId;
  final String? album;
  final int? artistId;
  final String? artist;
  final List<String> artists;
  final String? albumArtist;
  final int? trackNumber;
  final int? discNumber;
  final int? year;
  final int durationMs;
  final int? bitrate;
  final int? sampleRate;
  final int? channels;
  final String? codec;
  final int fileSize;
  final int modifiedAt;
  final String? lyrics;
  final List<String> genres;

  const Track({
    this.id,
    required this.uri,
    required this.title,
    this.albumId,
    this.album,
    this.artistId,
    this.artist,
    this.artists = const [],
    this.albumArtist,
    this.trackNumber,
    this.discNumber = 1,
    this.year,
    required this.durationMs,
    this.bitrate,
    this.sampleRate,
    this.channels,
    this.codec,
    required this.fileSize,
    required this.modifiedAt,
    this.lyrics,
    this.genres = const [],
  });

  Duration get duration => Duration(milliseconds: durationMs);
  DateTime get modifiedDateTime =>
      DateTime.fromMillisecondsSinceEpoch(modifiedAt);

  // Convenience aliases for flexible consumption
  String? get artistName => artist;
  String? get albumName => album;

  Track copyWith({
    int? id,
    String? uri,
    String? title,
    int? albumId,
    String? album,
    int? artistId,
    String? artist,
    List<String>? artists,
    String? albumArtist,
    int? trackNumber,
    int? discNumber,
    int? year,
    int? durationMs,
    int? bitrate,
    int? sampleRate,
    int? channels,
    String? codec,
    int? fileSize,
    int? modifiedAt,
    String? lyrics,
    List<String>? genres,
  }) {
    return Track(
      id: id ?? this.id,
      uri: uri ?? this.uri,
      title: title ?? this.title,
      albumId: albumId ?? this.albumId,
      album: album ?? this.album,
      artistId: artistId ?? this.artistId,
      artist: artist ?? this.artist,
      artists: artists ?? this.artists,
      albumArtist: albumArtist ?? this.albumArtist,
      trackNumber: trackNumber ?? this.trackNumber,
      discNumber: discNumber ?? this.discNumber,
      year: year ?? this.year,
      durationMs: durationMs ?? this.durationMs,
      bitrate: bitrate ?? this.bitrate,
      sampleRate: sampleRate ?? this.sampleRate,
      channels: channels ?? this.channels,
      codec: codec ?? this.codec,
      fileSize: fileSize ?? this.fileSize,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      lyrics: lyrics ?? this.lyrics,
      genres: genres ?? this.genres,
    );
  }

  Map<String, dynamic> toDbMap() {
    return {
      if (id != null) 'id': id,
      'uri': uri,
      'title': title,
      'album_id': albumId,
      'artist_id': artistId,
      'album_artist': albumArtist,
      'track_number': trackNumber,
      'disc_number': discNumber ?? 1,
      'year': year,
      'duration_ms': durationMs,
      'bitrate': bitrate,
      'sample_rate': sampleRate,
      'channels': channels,
      'codec': codec,
      'file_size': fileSize,
      'modified_at': modifiedAt,
      'lyrics': lyrics,
    };
  }

  factory Track.fromDbMap(
    Map<String, dynamic> map, {
    List<String> artists = const [],
    List<String> genres = const [],
    String? albumName,
    String? artistName,
  }) {
    return Track(
      id: map['id'] as int?,
      uri: map['uri'] as String? ?? '',
      title: map['title'] as String? ?? '',
      albumId: map['album_id'] as int?,
      album:
          albumName ??
          (map['album_name'] as String?) ??
          (map['album'] as String?),
      artistId: map['artist_id'] as int?,
      artist:
          artistName ??
          (map['artist_name'] as String?) ??
          (map['artist'] as String?),
      artists: artists.isNotEmpty
          ? artists
          : ((map['artist_name'] ?? map['artist']) != null
                ? [(map['artist_name'] ?? map['artist']) as String]
                : const []),
      albumArtist: map['album_artist'] as String?,
      trackNumber: map['track_number'] as int?,
      discNumber: map['disc_number'] as int? ?? 1,
      year: map['year'] as int?,
      durationMs: map['duration_ms'] as int? ?? 0,
      bitrate: map['bitrate'] as int?,
      sampleRate: map['sample_rate'] as int?,
      channels: map['channels'] as int?,
      codec: map['codec'] as String?,
      fileSize: map['file_size'] as int? ?? 0,
      modifiedAt: map['modified_at'] as int? ?? 0,
      lyrics: map['lyrics'] as String?,
      genres: genres,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'uri': uri,
      'title': title,
      'albumId': albumId,
      'album': album,
      'artistId': artistId,
      'artist': artist,
      'artists': artists,
      'albumArtist': albumArtist,
      'trackNumber': trackNumber,
      'discNumber': discNumber,
      'year': year,
      'durationMs': durationMs,
      'bitrate': bitrate,
      'sampleRate': sampleRate,
      'channels': channels,
      'codec': codec,
      'fileSize': fileSize,
      'modifiedAt': modifiedAt,
      'lyrics': lyrics,
      'genres': genres,
    };
  }

  factory Track.fromJson(Map<String, dynamic> json) {
    // Robustly handle both camelCase (API/JSON) and snake_case (raw DB query result)
    final id = json['id'] as int?;
    final uri = (json['uri'] as String?) ?? '';
    final title = (json['title'] as String?) ?? '';
    final albumId = (json['albumId'] ?? json['album_id']) as int?;
    final album = (json['album'] ?? json['album_name']) as String?;
    final artistId = (json['artistId'] ?? json['artist_id']) as int?;
    final artist = (json['artist'] ?? json['artist_name']) as String?;
    final albumArtist =
        (json['albumArtist'] ?? json['album_artist']) as String?;
    final trackNumber = (json['trackNumber'] ?? json['track_number']) as int?;
    final discNumber = (json['discNumber'] ?? json['disc_number']) as int? ?? 1;
    final year = json['year'] as int?;
    final durationMs =
        ((json['durationMs'] ?? json['duration_ms']) as num?)?.toInt() ?? 0;
    final bitrate = json['bitrate'] as int?;
    final sampleRate = (json['sampleRate'] ?? json['sample_rate']) as int?;
    final channels = json['channels'] as int?;
    final codec = json['codec'] as String?;
    final fileSize =
        ((json['fileSize'] ?? json['file_size']) as num?)?.toInt() ?? 0;
    final modifiedAt =
        ((json['modifiedAt'] ?? json['modified_at']) as num?)?.toInt() ?? 0;
    final lyrics = json['lyrics'] as String?;

    List<String> artists = const [];
    if (json['artists'] is List) {
      artists = (json['artists'] as List).map((e) => e.toString()).toList();
    } else if (artist != null && artist.isNotEmpty) {
      artists = [artist];
    }

    List<String> genres = const [];
    if (json['genres'] is List) {
      genres = (json['genres'] as List).map((e) => e.toString()).toList();
    }

    return Track(
      id: id,
      uri: uri,
      title: title,
      albumId: albumId,
      album: album,
      artistId: artistId,
      artist: artist,
      artists: artists,
      albumArtist: albumArtist,
      trackNumber: trackNumber,
      discNumber: discNumber,
      year: year,
      durationMs: durationMs,
      bitrate: bitrate,
      sampleRate: sampleRate,
      channels: channels,
      codec: codec,
      fileSize: fileSize,
      modifiedAt: modifiedAt,
      lyrics: lyrics,
      genres: genres,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Track &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          uri == other.uri &&
          title == other.title &&
          albumId == other.albumId &&
          album == other.album &&
          artistId == other.artistId &&
          artist == other.artist &&
          listEquals(artists, other.artists) &&
          albumArtist == other.albumArtist &&
          trackNumber == other.trackNumber &&
          discNumber == other.discNumber &&
          year == other.year &&
          durationMs == other.durationMs &&
          bitrate == other.bitrate &&
          sampleRate == other.sampleRate &&
          channels == other.channels &&
          codec == other.codec &&
          fileSize == other.fileSize &&
          modifiedAt == other.modifiedAt &&
          lyrics == other.lyrics &&
          listEquals(genres, other.genres);

  @override
  int get hashCode => Object.hashAll([
    id,
    uri,
    title,
    albumId,
    album,
    artistId,
    artist,
    Object.hashAll(artists),
    albumArtist,
    trackNumber,
    discNumber,
    year,
    durationMs,
    bitrate,
    sampleRate,
    channels,
    codec,
    fileSize,
    modifiedAt,
    lyrics,
    Object.hashAll(genres),
  ]);
}
