/// Flat normalized DTO representations used for lightweight isolate transfer
/// of the music catalog. STRICTLY ZERO LYRICS FIELDS.
class RawTrackDto {
  /// Persisted database track ID.
  final int id;

  /// Absolute file path or stream URI of the audio file.
  final String filePath;

  /// Track display title.
  final String title;

  /// Track index within its disc, if present.
  final int? trackNumber;

  /// Disc index within a multi-disc album, if present.
  final int? discNumber;

  /// Release year, if present.
  final int? year;

  /// Total track duration in milliseconds.
  final int durationMs;

  /// Encoded audio bitrate in bits per second, if known.
  final int? bitrate;

  /// Audio sample rate in Hz, if known.
  final int? sampleRate;

  /// Number of audio channels, if known.
  final int? channels;

  /// Audio codec name or container format, if known.
  final String? codec;

  /// File size in bytes.
  final int fileSize;

  /// Last file modification timestamp in milliseconds since epoch.
  final int modifiedAt;

  /// ReplayGain track gain adjustment in decibels, if tagged.
  final double? replayGainTrackGain;

  /// ReplayGain track peak linear amplitude, if tagged.
  final double? replayGainTrackPeak;

  /// Encoded waveform amplitude payload string, if computed.
  final String? waveformData;

  /// Foreign key referencing the parent album, if any.
  final int? albumId;

  /// Stored artwork hash or URI, if available.
  final String? artworkUri;

  /// Creates an immutable [RawTrackDto] record.
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
    this.artworkUri,
  });
}

/// Flat normalized album DTO exported inside [CatalogSnapshot].
class RawAlbumDto {
  /// Persisted database album ID.
  final int id;

  /// Album title.
  final String name;

  /// Release year, if known.
  final int? year;

  /// Foreign key referencing the primary artist, if any.
  final int? artistId;

  /// Stored artwork hash or URI, if available.
  final String? artworkUri;

  /// Creates an immutable [RawAlbumDto] record.
  const RawAlbumDto({
    required this.id,
    required this.name,
    this.year,
    this.artistId,
    this.artworkUri,
  });
}

/// Flat normalized artist DTO exported inside [CatalogSnapshot].
class RawArtistDto {
  /// Persisted database artist ID.
  final int id;

  /// Artist display name.
  final String name;

  /// Stored artwork hash or URI, if available.
  final String? artworkUri;

  /// Creates an immutable [RawArtistDto] record.
  const RawArtistDto({
    required this.id,
    required this.name,
    this.artworkUri,
  });
}

/// Flat normalized genre DTO exported inside [CatalogSnapshot].
class RawGenreDto {
  /// Persisted database genre ID.
  final int id;

  /// Genre display name.
  final String name;

  /// Creates an immutable [RawGenreDto] record.
  const RawGenreDto({required this.id, required this.name});
}

/// Flat normalized playlist DTO exported inside [CatalogSnapshot].
class RawPlaylistDto {
  /// Persisted database playlist ID.
  final int id;

  /// Playlist display name.
  final String name;

  /// Creation timestamp in milliseconds since epoch.
  final int createdAt;

  /// Raw integer playlist kind code.
  final int type;

  /// Creates an immutable [RawPlaylistDto] record.
  const RawPlaylistDto({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.type,
  });
}

/// Flat normalized playlist entry join DTO exported inside [CatalogSnapshot].
class RawPlaylistEntryDto {
  /// Persisted database entry ID.
  final int id;

  /// Foreign key referencing the owning playlist.
  final int playlistId;

  /// Foreign key referencing the linked track.
  final int trackId;

  /// Zero-based position of the entry in the playlist.
  final int position;

  /// Timestamp when the entry was added, in milliseconds since epoch.
  final int addedAt;

  /// Creates an immutable [RawPlaylistEntryDto] record.
  const RawPlaylistEntryDto({
    required this.id,
    required this.playlistId,
    required this.trackId,
    required this.position,
    required this.addedAt,
  });
}

/// Normalized many-to-many link between a track and an artist.
class TrackArtistPair {
  /// Referenced track ID.
  final int trackId;

  /// Referenced artist ID.
  final int artistId;

  /// Creates a [TrackArtistPair] association.
  const TrackArtistPair({required this.trackId, required this.artistId});
}

/// Normalized many-to-many link between a track and a genre.
class TrackGenrePair {
  /// Referenced track ID.
  final int trackId;

  /// Referenced genre ID.
  final int genreId;

  /// Creates a [TrackGenrePair] association.
  const TrackGenrePair({required this.trackId, required this.genreId});
}

/// In-memory catalog snapshot exported in a single read transaction.
/// Used to hydrate the in-memory relational graph (`LibraryStore`) in the UI Isolate.
/// STRICTLY ZERO LYRICS FIELDS.
class CatalogSnapshot {
  /// All raw track records in the snapshot.
  final List<RawTrackDto> tracks;

  /// All raw album records in the snapshot.
  final List<RawAlbumDto> albums;

  /// All raw artist records in the snapshot.
  final List<RawArtistDto> artists;

  /// All raw genre records in the snapshot.
  final List<RawGenreDto> genres;

  /// All raw playlist records in the snapshot.
  final List<RawPlaylistDto> playlists;

  /// All raw playlist entry records in the snapshot.
  final List<RawPlaylistEntryDto> playlistEntries;

  /// Track-to-artist join pairs in the snapshot.
  final List<TrackArtistPair> trackArtists;

  /// Track-to-genre join pairs in the snapshot.
  final List<TrackGenrePair> trackGenres;

  /// Creates a [CatalogSnapshot] containing all normalized catalog collections.
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

  /// Creates an empty [CatalogSnapshot] with no records.
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
