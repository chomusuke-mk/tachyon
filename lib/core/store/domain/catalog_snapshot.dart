/// Flat normalized DTO representations used for lightweight isolate transfer
/// of the music catalog. STRICTLY ZERO LYRICS FIELDS.
class RawTrackDto {
  final int id;
  final String filePath;
  final String title;
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
  final double? replayGainTrackGain;
  final double? replayGainTrackPeak;
  final String? waveformData;
  final int? albumId;
  final String? thumbnailHash;

  const RawTrackDto({
    required this.id,
    required this.filePath,
    required this.title,
    this.trackNumber,
    this.discNumber,
    this.year,
    required this.durationMs,
    this.bitrate,
    this.sampleRate,
    this.channels,
    this.codec,
    required this.fileSize,
    required this.modifiedAt,
    this.replayGainTrackGain,
    this.replayGainTrackPeak,
    this.waveformData,
    this.albumId,
    this.thumbnailHash,
  });
}

class RawAlbumDto {
  final int id;
  final String name;
  final int? year;
  final int? artistId;
  final String? thumbnailHash;

  const RawAlbumDto({
    required this.id,
    required this.name,
    this.year,
    this.artistId,
    this.thumbnailHash,
  });
}

class RawArtistDto {
  final int id;
  final String name;
  final String? thumbnailHash;

  const RawArtistDto({
    required this.id,
    required this.name,
    this.thumbnailHash,
  });
}

class RawGenreDto {
  final int id;
  final String name;

  const RawGenreDto({required this.id, required this.name});
}

class RawPlaylistDto {
  final int id;
  final String name;
  final int createdAt;
  final int type;

  const RawPlaylistDto({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.type,
  });
}

class RawPlaylistEntryDto {
  final int id;
  final int playlistId;
  final int trackId;
  final int position;
  final int addedAt;

  const RawPlaylistEntryDto({
    required this.id,
    required this.playlistId,
    required this.trackId,
    required this.position,
    required this.addedAt,
  });
}

class TrackArtistPair {
  final int trackId;
  final int artistId;

  const TrackArtistPair({required this.trackId, required this.artistId});
}

class TrackGenrePair {
  final int trackId;
  final int genreId;

  const TrackGenrePair({required this.trackId, required this.genreId});
}

/// In-memory catalog snapshot exported in a single read transaction.
/// Used to hydrate the in-memory relational graph (`LibraryStore`) in the UI Isolate.
/// STRICTLY ZERO LYRICS FIELDS.
class CatalogSnapshot {
  final List<RawTrackDto> tracks;
  final List<RawAlbumDto> albums;
  final List<RawArtistDto> artists;
  final List<RawGenreDto> genres;
  final List<RawPlaylistDto> playlists;
  final List<RawPlaylistEntryDto> playlistEntries;
  final List<TrackArtistPair> trackArtists;
  final List<TrackGenrePair> trackGenres;

  const CatalogSnapshot({
    required this.tracks,
    required this.albums,
    required this.artists,
    required this.genres,
    required this.playlists,
    required this.playlistEntries,
    required this.trackArtists,
    required this.trackGenres,
  });

  const CatalogSnapshot.empty()
    : tracks = const [],
      albums = const [],
      artists = const [],
      genres = const [],
      playlists = const [],
      playlistEntries = const [],
      trackArtists = const [],
      trackGenres = const [];
}
