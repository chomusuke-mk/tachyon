import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/store/domain/album.dart';
import 'package:tachyon/core/store/domain/artist.dart';
import 'package:tachyon/core/store/domain/catalog_snapshot.dart';
import 'package:tachyon/core/store/domain/genre.dart';
import 'package:tachyon/core/store/domain/playlist.dart';
import 'package:tachyon/core/store/domain/track.dart';
import 'package:tachyon/core/store/domain/track_sort_option.dart';
import 'package:tachyon/shared/utils/waveform_codec.dart';

/// In-memory relational graph for the Main Isolate.
///
/// Features:
/// - O(N) single-pass hydration from [CatalogSnapshot].
/// - 100% pointer identity: shared entities point to identical memory addresses.
/// - Bi-directional pointer linking (track <-> album, track <-> artist, track <-> genre, playlistEntry <-> playlist & track).
/// - O(1) ID lookups for tracks, albums, artists, genres, and playlists.
/// - In-memory filtering, searching, and sorting with 0 SQLite calls.
class LibraryStore extends ChangeNotifier {
  final AppDatabase? _database;
  final math.Random _random = math.Random();

  // Primary indices for O(1) lookups
  final Map<int, Track> _tracksById = {};
  final Map<String, Track> _tracksByPath = {};
  final Map<String, List<Track>> _tracksByDirectory = {};
  final Map<int, Album> _albumsById = {};
  final Map<int, Artist> _artistsById = {};
  final Map<int, Genre> _genresById = {};
  final Map<int, Playlist> _playlistsById = {};

  // Ordered lists
  final List<Track> _allTracks = [];
  final List<Album> _allAlbums = [];
  final List<Artist> _allArtists = [];
  final List<Genre> _allGenres = [];
  final List<Playlist> _allPlaylists = [];

  // Fast set of liked track IDs
  final Set<int> _likedTrackIds = <int>{};

  // Cached zero-copy unmodifiable views, invalidated on collection mutation
  List<Track>? _tracksView;
  List<Album>? _albumsView;
  List<Artist>? _artistsView;
  List<Genre>? _genresView;
  List<Playlist>? _playlistsView;
  Set<int>? _likedTrackIdsView;

  bool _isHydrated = false;
  bool get isHydrated => _isHydrated;

  void _invalidateViews() {
    _tracksView = null;
    _albumsView = null;
    _artistsView = null;
    _genresView = null;
    _playlistsView = null;
    _likedTrackIdsView = null;
  }

  LibraryStore([this._database]);

  /// Creates a hydrated [LibraryStore] from a [CatalogSnapshot].
  factory LibraryStore.fromSnapshot(
    CatalogSnapshot snapshot, [
    AppDatabase? database,
  ]) {
    final store = LibraryStore(database);
    store.hydrateFromSnapshot(snapshot);
    return store;
  }

  /// Reloads the entire relational catalog from [AppDatabase] and hydrates the graph.
  Future<void> reloadFromDatabase() async {
    final db = _database;
    if (db == null) return;
    final snapshot = await db.getCatalogSnapshot();
    hydrateFromSnapshot(snapshot);
  }

  // ---------------------------------------------------------------------------
  // Getters & Collections
  // ---------------------------------------------------------------------------
  List<Track> get tracks => _tracksView ??= UnmodifiableListView(_allTracks);
  List<Track> get allTracks => tracks;

  List<Album> get albums => _albumsView ??= UnmodifiableListView(_allAlbums);
  List<Album> get allAlbums => albums;

  List<Artist> get artists =>
      _artistsView ??= UnmodifiableListView(_allArtists);
  List<Artist> get allArtists => artists;

  List<Genre> get genres => _genresView ??= UnmodifiableListView(_allGenres);
  List<Genre> get allGenres => genres;

  List<Playlist> get playlists =>
      _playlistsView ??= UnmodifiableListView(_allPlaylists);
  List<Playlist> get allPlaylists => playlists;

  Set<int> get likedTrackIds =>
      _likedTrackIdsView ??= UnmodifiableSetView(_likedTrackIds);

  Playlist? get likedSongsPlaylist =>
      _allPlaylists.where((p) => p.type == PlaylistType.liked).firstOrNull;

  Playlist? get historyPlaylist =>
      _allPlaylists.where((p) => p.type == PlaylistType.history).firstOrNull;

  List<Playlist> get userPlaylists =>
      _allPlaylists.where((p) => p.type == PlaylistType.user).toList();

  // ---------------------------------------------------------------------------
  // O(1) Lookups & In-Memory Queries
  // ---------------------------------------------------------------------------
  Track? getTrackById(int id) => _tracksById[id];
  Track? getTrackByPath(String path) => _tracksByPath[path];
  List<Track> getTracksInDirectory(String directoryPath) {
    final normalized = p.normalize(directoryPath);
    return UnmodifiableListView(_tracksByDirectory[normalized] ?? const []);
  }

  Album? getAlbumById(int id) => _albumsById[id];
  Artist? getArtistById(int id) => _artistsById[id];
  Genre? getGenreById(int id) => _genresById[id];
  Playlist? getPlaylistById(int id) => _playlistsById[id];

  bool isTrackLiked(int trackId) => _likedTrackIds.contains(trackId);

  /// Resolves a list of track IDs in $O(K)$ directly from RAM.
  List<Track> getTracksByIds(List<int> ids) {
    if (ids.isEmpty) return const [];
    final result = <Track>[];
    for (final id in ids) {
      final track = _tracksById[id];
      if (track != null) {
        result.add(track);
      }
    }
    return result;
  }

  /// Selects up to [limit] random tracks from RAM in $O(N)$ without querying SQLite.
  List<Track> getRandomTracks(int limit) {
    if (limit <= 0 || _allTracks.isEmpty) return const [];
    final candidates = List<Track>.of(_allTracks);
    final count = math.min(limit, candidates.length);
    for (var i = 0; i < count; i++) {
      final j = i + _random.nextInt(candidates.length - i);
      final tmp = candidates[i];
      candidates[i] = candidates[j];
      candidates[j] = tmp;
    }
    return candidates.sublist(0, count);
  }

  /// Returns track file metadata map (`filePath -> (modifiedAt, fileSize)`) from RAM.
  Map<String, ({int modifiedAt, int fileSize})> getExistingTrackMetas() {
    return <String, ({int modifiedAt, int fileSize})>{
      for (final track in _allTracks)
        track.filePath: (
          modifiedAt: track.modifiedAt,
          fileSize: track.fileSize,
        ),
    };
  }

  /// Returns stored track info (`(id, filePath, modifiedAt)`) from RAM.
  List<({int id, String filePath, int modifiedAt})> getStoredTracks() {
    return <({int id, String filePath, int modifiedAt})>[
      for (final track in _allTracks)
        if (track.id != null)
          (
            id: track.id!,
            filePath: track.filePath,
            modifiedAt: track.modifiedAt,
          ),
    ];
  }

  /// Collects all active cover art hashes across tracks, albums, and artists in RAM.
  Set<String> getAllThumbnailHashes() {
    final hashes = <String>{};
    for (final t in _allTracks) {
      if (t.thumbnailHash != null && t.thumbnailHash!.isNotEmpty) {
        hashes.add(t.thumbnailHash!);
      }
    }
    for (final a in _allAlbums) {
      if (a.thumbnailHash != null && a.thumbnailHash!.isNotEmpty) {
        hashes.add(a.thumbnailHash!);
      }
    }
    for (final ar in _allArtists) {
      if (ar.thumbnailHash != null && ar.thumbnailHash!.isNotEmpty) {
        hashes.add(ar.thumbnailHash!);
      }
    }
    return hashes;
  }

  /// Returns ordered track IDs for a playlist directly from RAM.
  List<int> getTrackIdsForPlaylist(int playlistId) {
    final playlist = _playlistsById[playlistId];
    if (playlist == null) return const [];
    return playlist.entries
        .map((e) => e.track?.id)
        .whereType<int>()
        .toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // Hydration Algorithm (O(N) single-pass)
  // ---------------------------------------------------------------------------
  void hydrateFromSnapshot(CatalogSnapshot snapshot) {
    _invalidateViews();
    _tracksById.clear();
    _tracksByPath.clear();
    _tracksByDirectory.clear();
    _albumsById.clear();
    _artistsById.clear();
    _genresById.clear();
    _playlistsById.clear();

    _allTracks.clear();
    _allAlbums.clear();
    _allArtists.clear();
    _allGenres.clear();
    _allPlaylists.clear();
    _likedTrackIds.clear();

    // 1. Group many-to-many relationship pairs by trackId
    final trackToArtistIds = <int, List<int>>{};
    for (final pair in snapshot.trackArtists) {
      trackToArtistIds.putIfAbsent(pair.trackId, () => []).add(pair.artistId);
    }

    final trackToGenreIds = <int, List<int>>{};
    for (final pair in snapshot.trackGenres) {
      trackToGenreIds.putIfAbsent(pair.trackId, () => []).add(pair.genreId);
    }

    final internedStrings = <String, String>{};
    String? internString(String? value) {
      if (value == null) return null;
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      return internedStrings.putIfAbsent(trimmed, () => trimmed);
    }

    // Pre-calculate thumbnail fallbacks from snapshot
    final albumFirstTrackThumbnail = <int, String>{};
    for (final rawTrack in snapshot.tracks) {
      if (rawTrack.albumId != null) {
        final hash = internString(rawTrack.thumbnailHash);
        if (hash != null) {
          albumFirstTrackThumbnail.putIfAbsent(rawTrack.albumId!, () => hash);
        }
      }
    }

    final effectiveAlbumThumbnails = <int, String>{};
    final artistFirstAlbumThumbnail = <int, String>{};
    for (final rawAlbum in snapshot.albums) {
      final hash =
          internString(rawAlbum.thumbnailHash) ??
          albumFirstTrackThumbnail[rawAlbum.id];
      if (hash != null) {
        effectiveAlbumThumbnails[rawAlbum.id] = hash;
        if (rawAlbum.artistId != null) {
          artistFirstAlbumThumbnail.putIfAbsent(rawAlbum.artistId!, () => hash);
        }
      }
    }

    final trackEffectiveThumbnail = <int, String>{};
    for (final rawTrack in snapshot.tracks) {
      final hash =
          internString(rawTrack.thumbnailHash) ??
          (rawTrack.albumId != null
              ? effectiveAlbumThumbnails[rawTrack.albumId]
              : null);
      if (hash != null) {
        trackEffectiveThumbnail[rawTrack.id] = hash;
      }
    }

    final artistFirstTrackThumbnail = <int, String>{};
    for (final pair in snapshot.trackArtists) {
      final hash = trackEffectiveThumbnail[pair.trackId];
      if (hash != null) {
        artistFirstTrackThumbnail.putIfAbsent(pair.artistId, () => hash);
      }
    }

    // 2. Instantiate Artists with mutable backing lists for bi-directional linking
    final artistAlbumsMap = <int, List<Album>>{};
    final artistTracksMap = <int, List<Track>>{};

    for (final rawArtist in snapshot.artists) {
      final albumsList = <Album>[];
      final tracksList = <Track>[];
      artistAlbumsMap[rawArtist.id] = albumsList;
      artistTracksMap[rawArtist.id] = tracksList;

      final effectiveThumbnail =
          internString(rawArtist.thumbnailHash) ??
          artistFirstAlbumThumbnail[rawArtist.id] ??
          artistFirstTrackThumbnail[rawArtist.id];

      final artist = Artist(
        id: rawArtist.id,
        name: rawArtist.name,
        thumbnailHash: effectiveThumbnail,
        albums: albumsList,
        tracks: tracksList,
      );
      _artistsById[rawArtist.id] = artist;
      _allArtists.add(artist);
    }

    // 3. Instantiate Genres with mutable backing lists
    final genreTracksMap = <int, List<Track>>{};

    for (final rawGenre in snapshot.genres) {
      final tracksList = <Track>[];
      genreTracksMap[rawGenre.id] = tracksList;

      final genre = Genre(
        id: rawGenre.id,
        name: rawGenre.name,
        tracks: tracksList,
      );
      _genresById[rawGenre.id] = genre;
      _allGenres.add(genre);
    }

    // 4. Instantiate Albums linking Artist reference and mutable tracks list
    final albumTracksMap = <int, List<Track>>{};

    for (final rawAlbum in snapshot.albums) {
      final tracksList = <Track>[];
      albumTracksMap[rawAlbum.id] = tracksList;

      final artist = rawAlbum.artistId != null
          ? _artistsById[rawAlbum.artistId]
          : null;

      final effectiveAlbumThumbnail =
          internString(rawAlbum.thumbnailHash) ??
          effectiveAlbumThumbnails[rawAlbum.id];

      final album = Album(
        id: rawAlbum.id,
        name: rawAlbum.name,
        year: rawAlbum.year,
        thumbnailHash: effectiveAlbumThumbnail,
        artist: artist,
        tracks: tracksList,
      );
      _albumsById[rawAlbum.id] = album;
      _allAlbums.add(album);

      if (artist != null && artist.id != null) {
        final artistAlbums = artistAlbumsMap[artist.id];
        if (artistAlbums != null && !artistAlbums.contains(album)) {
          artistAlbums.add(album);
        }
      }
    }

    // 5. Instantiate Tracks linking Album, Artists, and Genres
    for (final rawTrack in snapshot.tracks) {
      final album = rawTrack.albumId != null
          ? _albumsById[rawTrack.albumId]
          : null;

      final linkedArtistIds = trackToArtistIds[rawTrack.id];
      final List<Artist> linkedArtists;
      if (linkedArtistIds == null || linkedArtistIds.isEmpty) {
        linkedArtists = const <Artist>[];
      } else {
        final temp = <Artist>[];
        for (final aId in linkedArtistIds) {
          final artist = _artistsById[aId];
          if (artist != null) {
            temp.add(artist);
          }
        }
        linkedArtists = temp.isEmpty
            ? const <Artist>[]
            : List<Artist>.of(temp, growable: false);
      }

      final linkedGenreIds = trackToGenreIds[rawTrack.id];
      final List<Genre> linkedGenres;
      if (linkedGenreIds == null || linkedGenreIds.isEmpty) {
        linkedGenres = const <Genre>[];
      } else {
        final temp = <Genre>[];
        for (final gId in linkedGenreIds) {
          final genre = _genresById[gId];
          if (genre != null) {
            temp.add(genre);
          }
        }
        linkedGenres = temp.isEmpty
            ? const <Genre>[]
            : List<Genre>.of(temp, growable: false);
      }

      final track = Track(
        id: rawTrack.id,
        filePath: rawTrack.filePath,
        title: rawTrack.title,
        trackNumber: rawTrack.trackNumber,
        discNumber: rawTrack.discNumber ?? 1,
        year: rawTrack.year,
        durationMs: rawTrack.durationMs,
        bitrate: rawTrack.bitrate,
        sampleRate: rawTrack.sampleRate,
        channels: rawTrack.channels,
        codec: internString(rawTrack.codec),
        fileSize: rawTrack.fileSize,
        modifiedAt: rawTrack.modifiedAt,
        replayGainTrackGain: rawTrack.replayGainTrackGain,
        replayGainTrackPeak: rawTrack.replayGainTrackPeak,
        waveform: WaveformCodec.decode(rawTrack.waveformData),
        thumbnailHash:
            internString(rawTrack.thumbnailHash) ?? album?.thumbnailHash,
        album: album,
        artists: linkedArtists,
        genres: linkedGenres,
      );

      _tracksById[rawTrack.id] = track;
      _tracksByPath[rawTrack.filePath] = track;
      final trackDir = p.normalize(p.dirname(rawTrack.filePath));
      _tracksByDirectory.putIfAbsent(trackDir, () => []).add(track);
      _allTracks.add(track);

      // Back-link track to Album
      if (album != null && album.id != null) {
        final albumTracks = albumTracksMap[album.id];
        if (albumTracks != null) {
          albumTracks.add(track);
        }
      }

      // Back-link track to Artists and ensure album is linked to artist
      for (final artist in linkedArtists) {
        if (artist.id != null) {
          final aTracks = artistTracksMap[artist.id];
          if (aTracks != null) {
            aTracks.add(track);
          }
          if (album != null) {
            final aAlbums = artistAlbumsMap[artist.id];
            if (aAlbums != null && !aAlbums.contains(album)) {
              aAlbums.add(album);
            }
          }
        }
      }

      // Back-link track to Genres
      for (final genre in linkedGenres) {
        if (genre.id != null) {
          final gTracks = genreTracksMap[genre.id];
          if (gTracks != null) {
            gTracks.add(track);
          }
        }
      }
    }

    // Sort tracks inside each album by discNumber then trackNumber
    for (final tracksList in albumTracksMap.values) {
      tracksList.sort((a, b) {
        final discComp = (a.discNumber ?? 1).compareTo(b.discNumber ?? 1);
        if (discComp != 0) return discComp;
        return (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0);
      });
    }

    // Compute coverHash for each genre based on its tracks
    for (final genre in _allGenres) {
      genre.coverHash = computeGenreCoverHash(genre);
    }

    // 6. Instantiate Playlists and PlaylistEntries linking to Tracks
    final playlistEntriesMap = <int, List<RawPlaylistEntryDto>>{};
    for (final entry in snapshot.playlistEntries) {
      playlistEntriesMap.putIfAbsent(entry.playlistId, () => []).add(entry);
    }

    for (final rawPlaylist in snapshot.playlists) {
      final entriesList = <PlaylistEntry>[];
      final playlist = Playlist(
        id: rawPlaylist.id,
        name: rawPlaylist.name,
        createdAt: rawPlaylist.createdAt,
        type: PlaylistType.fromValue(rawPlaylist.type),
        entries: entriesList,
      );
      _playlistsById[rawPlaylist.id] = playlist;
      _allPlaylists.add(playlist);

      final rawEntries = playlistEntriesMap[rawPlaylist.id] ?? const [];
      final sortedRawEntries = List<RawPlaylistEntryDto>.from(rawEntries)
        ..sort((a, b) => a.position.compareTo(b.position));

      for (final rawEntry in sortedRawEntries) {
        final track = _tracksById[rawEntry.trackId];
        final entry = PlaylistEntry(
          id: rawEntry.id,
          position: rawEntry.position,
          addedAt: rawEntry.addedAt,
          playlist: playlist,
          track: track,
        );
        entriesList.add(entry);

        if (playlist.type == PlaylistType.liked && track?.id != null) {
          _likedTrackIds.add(track!.id!);
        }
      }

      playlist.coverHash = computePlaylistCoverHash(playlist);
    }

    _isHydrated = true;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // In-Memory Mutations
  // ---------------------------------------------------------------------------
  void setTrackLiked(int trackId, bool isLiked) {
    _likedTrackIdsView = null;
    if (isLiked) {
      _likedTrackIds.add(trackId);
    } else {
      _likedTrackIds.remove(trackId);
    }

    final likedPl = likedSongsPlaylist;
    if (likedPl != null) {
      if (isLiked) {
        final alreadyIn = likedPl.entries.any((e) => e.track?.id == trackId);
        if (!alreadyIn) {
          final track = _tracksById[trackId];
          if (track != null) {
            final newEntry = PlaylistEntry(
              id: null,
              position: likedPl.entries.length,
              addedAt: DateTime.now().millisecondsSinceEpoch,
              playlist: likedPl,
              track: track,
            );
            likedPl.entries.add(newEntry);
          }
        }
      } else {
        likedPl.entries.removeWhere((e) => e.track?.id == trackId);
        for (var i = 0; i < likedPl.entries.length; i++) {
          final old = likedPl.entries[i];
          likedPl.entries[i] = PlaylistEntry(
            id: old.id,
            position: i,
            addedAt: old.addedAt,
            playlist: likedPl,
            track: old.track,
          );
        }
      }
      likedPl.coverHash = computePlaylistCoverHash(likedPl);
    }
    notifyListeners();
  }

  bool toggleTrackLiked(int trackId) {
    final nextState = !_likedTrackIds.contains(trackId);
    setTrackLiked(trackId, nextState);
    return nextState;
  }

  void addTrackToPlaylist(
    int playlistId,
    int trackId, {
    int? entryId,
    int? position,
    int? addedAt,
  }) {
    final playlist = _playlistsById[playlistId];
    if (playlist == null) return;
    final track = _tracksById[trackId];
    if (track == null) return;
    final pos = position ?? playlist.entries.length;
    final entry = PlaylistEntry(
      id: entryId,
      position: pos,
      addedAt: addedAt ?? DateTime.now().millisecondsSinceEpoch,
      playlist: playlist,
      track: track,
    );

    if (pos >= playlist.entries.length) {
      playlist.entries.add(entry);
    } else {
      playlist.entries.insert(pos, entry);
      for (var i = 0; i < playlist.entries.length; i++) {
        final curr = playlist.entries[i];
        if (curr.position != i) {
          playlist.entries[i] = PlaylistEntry(
            id: curr.id,
            position: i,
            addedAt: curr.addedAt,
            playlist: playlist,
            track: curr.track,
          );
        }
      }
    }

    playlist.coverHash = computePlaylistCoverHash(playlist);

    if (playlist.type == PlaylistType.liked) {
      _likedTrackIdsView = null;
      _likedTrackIds.add(trackId);
    }
    notifyListeners();
  }

  void addTracksToPlaylist(int playlistId, List<int> trackIds) {
    if (trackIds.isEmpty) return;
    for (final trackId in trackIds) {
      addTrackToPlaylist(playlistId, trackId);
    }
  }

  void removeTrackFromPlaylist(int playlistId, int trackId) {
    final playlist = _playlistsById[playlistId];
    if (playlist == null) return;
    playlist.entries.removeWhere((e) => e.track?.id == trackId);
    for (var i = 0; i < playlist.entries.length; i++) {
      final curr = playlist.entries[i];
      if (curr.position != i) {
        playlist.entries[i] = PlaylistEntry(
          id: curr.id,
          position: i,
          addedAt: curr.addedAt,
          playlist: playlist,
          track: curr.track,
        );
      }
    }
    playlist.coverHash = computePlaylistCoverHash(playlist);
    if (playlist.type == PlaylistType.liked) {
      _likedTrackIdsView = null;
      _likedTrackIds.remove(trackId);
    }
    notifyListeners();
  }

  void reorderPlaylistEntries(int playlistId, int fromIndex, int toIndex) {
    final playlist = _playlistsById[playlistId];
    if (playlist == null) return;
    if (fromIndex < 0 || fromIndex >= playlist.entries.length) return;
    if (toIndex < 0 || toIndex >= playlist.entries.length) return;

    final item = playlist.entries.removeAt(fromIndex);
    playlist.entries.insert(toIndex, item);
    for (var i = 0; i < playlist.entries.length; i++) {
      final curr = playlist.entries[i];
      playlist.entries[i] = PlaylistEntry(
        id: curr.id,
        position: i,
        addedAt: curr.addedAt,
        playlist: playlist,
        track: curr.track,
      );
    }
    playlist.coverHash = computePlaylistCoverHash(playlist);
    notifyListeners();
  }

  void addPlaylist(Playlist playlist) {
    playlist.coverHash ??= computePlaylistCoverHash(playlist);
    if (playlist.id != null) {
      _playlistsById[playlist.id!] = playlist;
    }
    _allPlaylists.add(playlist);
    _playlistsView = null;
    notifyListeners();
  }

  void removePlaylist(int playlistId) {
    _playlistsById.remove(playlistId);
    _allPlaylists.removeWhere((p) => p.id == playlistId);
    _playlistsView = null;
    notifyListeners();
  }

  void renamePlaylist(int playlistId, String newName) {
    final playlist = _playlistsById[playlistId];
    if (playlist == null) return;
    final updated = Playlist(
      id: playlist.id,
      name: newName,
      createdAt: playlist.createdAt,
      type: playlist.type,
      entries: playlist.entries,
      coverHash: playlist.coverHash,
    );
    _playlistsById[playlistId] = updated;
    final index = _allPlaylists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      _allPlaylists[index] = updated;
    }
    _playlistsView = null;
    notifyListeners();
  }

  void clearHistory() {
    historyPlaylist?.entries.clear();
    historyPlaylist?.coverHash = null;
    notifyListeners();
  }

  void removeTrack(int trackId) {
    final track = _tracksById.remove(trackId);
    if (track == null) return;
    _tracksByPath.remove(track.filePath);
    final trackDir = p.normalize(p.dirname(track.filePath));
    _tracksByDirectory[trackDir]?.removeWhere((t) => t.id == trackId);
    _allTracks.removeWhere((t) => t.id == trackId);
    _tracksView = null;

    if (track.album != null && track.album!.id != null) {
      final album = _albumsById[track.album!.id];
      album?.tracks.removeWhere((t) => t.id == trackId);
    }

    for (final artist in track.artists) {
      if (artist.id != null) {
        final a = _artistsById[artist.id];
        a?.tracks.removeWhere((t) => t.id == trackId);
      }
    }

    for (final genre in track.genres) {
      if (genre.id != null) {
        final g = _genresById[genre.id];
        if (g != null) {
          g.tracks.removeWhere((t) => t.id == trackId);
          g.coverHash = computeGenreCoverHash(g);
        }
      }
    }

    for (final playlist in _allPlaylists) {
      final had = playlist.entries.any((e) => e.track?.id == trackId);
      playlist.entries.removeWhere((e) => e.track?.id == trackId);
      if (had) {
        playlist.coverHash = computePlaylistCoverHash(playlist);
      }
    }
    _likedTrackIdsView = null;
    _likedTrackIds.remove(trackId);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Coordinated Mutations (In-Memory Graph + AppDatabase)
  // ---------------------------------------------------------------------------
  Future<Playlist?> createPlaylistInStore(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final db = _database;
    int playlistId;
    if (db != null) {
      playlistId = await db.createPlaylist(trimmed);
      if (playlistId <= 0) return null;
    } else {
      playlistId = (_playlistsById.keys.fold<int>(2, math.max)) + 1;
    }
    final playlist = Playlist(
      id: playlistId,
      name: trimmed,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      type: PlaylistType.user,
      entries: <PlaylistEntry>[],
    );
    addPlaylist(playlist);
    return playlist;
  }

  Future<void> deletePlaylistInStore(int playlistId) async {
    removePlaylist(playlistId);
    await _database?.deletePlaylist(playlistId);
  }

  Future<void> renamePlaylistInStore(int playlistId, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    renamePlaylist(playlistId, trimmed);
    await _database?.renamePlaylist(playlistId, trimmed);
  }

  Future<void> addTrackToPlaylistInStore(int playlistId, int trackId) async {
    addTrackToPlaylist(playlistId, trackId);
    await _database?.addTrackToPlaylist(playlistId, trackId);
  }

  Future<void> addTracksToPlaylistInStore(
    int playlistId,
    List<int> trackIds,
  ) async {
    if (trackIds.isEmpty) return;
    addTracksToPlaylist(playlistId, trackIds);
    await _database?.addTracksToPlaylist(playlistId, trackIds);
  }

  Future<void> removeTrackFromPlaylistInStore(
    int playlistId,
    int trackId,
  ) async {
    removeTrackFromPlaylist(playlistId, trackId);
    await _database?.removeTrackFromPlaylist(playlistId, trackId);
  }

  Future<void> reorderPlaylistEntriesInStore(
    int playlistId,
    int fromIndex,
    int toIndex,
  ) async {
    reorderPlaylistEntries(playlistId, fromIndex, toIndex);
    await _database?.reorderPlaylistEntries(playlistId, fromIndex, toIndex);
  }

  Future<bool> toggleLikeInStore(int trackId) async {
    if (!_tracksById.containsKey(trackId)) return false;
    final nextState = toggleTrackLiked(trackId);
    await _database?.toggleLikeTrack(trackId);
    return nextState;
  }

  Future<void> clearHistoryInStore() async {
    clearHistory();
    await _database?.clearHistory();
  }

  Future<void> deleteTrackInStore(int trackId) async {
    removeTrack(trackId);
    await _database?.deleteTracksAndPurgeOrphans([trackId]);
    if (_database != null) {
      await reloadFromDatabase();
    }
  }

  Future<void> deleteTracksInStore(List<int> trackIds) async {
    if (trackIds.isEmpty) return;
    for (final id in trackIds) {
      removeTrack(id);
    }
    await _database?.deleteTracksAndPurgeOrphans(trackIds);
    if (_database != null) {
      await reloadFromDatabase();
    }
  }

  Future<void> clearAllDataInStore() async {
    await _database?.clearAllData();
    if (_database != null) {
      await reloadFromDatabase();
    } else {
      hydrateFromSnapshot(const CatalogSnapshot.empty());
    }
  }

  static String? computePlaylistCoverHash(
    Playlist playlist, [
    List<Track>? tracks,
  ]) {
    if (playlist.entries.isNotEmpty) {
      final sorted = List<PlaylistEntry>.from(playlist.entries)
        ..sort((a, b) {
          final cmp = b.addedAt.compareTo(a.addedAt);
          if (cmp != 0) return cmp;
          return b.position.compareTo(a.position);
        });
      for (final entry in sorted) {
        final track = entry.track;
        if (track != null) {
          final hash = track.thumbnailHash ?? track.album?.thumbnailHash;
          if (hash != null && hash.trim().isNotEmpty) {
            return hash.trim();
          }
        }
      }
    }

    if (tracks != null && tracks.isNotEmpty) {
      for (final track in tracks.reversed) {
        final hash = track.thumbnailHash ?? track.album?.thumbnailHash;
        if (hash != null && hash.trim().isNotEmpty) {
          return hash.trim();
        }
      }
    }

    return null;
  }

  static String? computeGenreCoverHash(Genre genre) {
    for (final track in genre.tracks) {
      final hash = track.thumbnailHash ?? track.album?.thumbnailHash;
      if (hash != null && hash.trim().isNotEmpty) {
        return hash.trim();
      }
    }
    return null;
  }

  static String? computeArtistThumbnailHash(Artist artist) {
    for (final album in artist.albums) {
      final hash = album.thumbnailHash;
      if (hash != null && hash.trim().isNotEmpty) {
        return hash.trim();
      }
    }

    for (final track in artist.tracks) {
      final hash = track.thumbnailHash ?? track.album?.thumbnailHash;
      if (hash != null && hash.trim().isNotEmpty) {
        return hash.trim();
      }
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // In-Memory Search, Filter, and Sort (0 SQL Calls)
  // ---------------------------------------------------------------------------
  List<Track> sortTracks(
    List<Track> list,
    TrackSortOption option, {
    bool ascending = true,
  }) {
    if (list.length <= 1) return List<Track>.of(list);

    final n = list.length;
    final indices = List<int>.generate(n, (i) => i, growable: false);
    final lowerTitles = List<String>.generate(
      n,
      (i) => list[i].title.toLowerCase(),
      growable: false,
    );

    List<String>? primaryStrings;
    if (option == TrackSortOption.artist) {
      primaryStrings = List<String>.generate(
        n,
        (i) => (list[i].artists.firstOrNull?.name ?? '').toLowerCase(),
        growable: false,
      );
    } else if (option == TrackSortOption.album) {
      primaryStrings = List<String>.generate(
        n,
        (i) => (list[i].album?.name ?? '').toLowerCase(),
        growable: false,
      );
    }

    indices.sort((ia, ib) {
      int cmp;
      switch (option) {
        case TrackSortOption.title:
          cmp = lowerTitles[ia].compareTo(lowerTitles[ib]);
          break;
        case TrackSortOption.artist:
        case TrackSortOption.album:
          cmp = primaryStrings![ia].compareTo(primaryStrings[ib]);
          break;
        case TrackSortOption.year:
          cmp = (list[ia].year ?? 0).compareTo(list[ib].year ?? 0);
          break;
        case TrackSortOption.duration:
          cmp = list[ia].durationMs.compareTo(list[ib].durationMs);
          break;
        case TrackSortOption.dateAdded:
          cmp = list[ia].modifiedAt.compareTo(list[ib].modifiedAt);
          break;
      }
      if (cmp == 0 && option != TrackSortOption.title) {
        cmp = lowerTitles[ia].compareTo(lowerTitles[ib]);
      }
      return ascending ? cmp : -cmp;
    });

    return List<Track>.generate(n, (i) => list[indices[i]], growable: false);
  }

  List<Track> filterTracks({Album? album, Artist? artist, Genre? genre}) {
    if (album == null && artist == null && genre == null) {
      return List.unmodifiable(_allTracks);
    }

    Iterable<Track> candidates;
    if (album != null) {
      candidates = album.tracks;
    } else if (artist != null) {
      candidates = artist.tracks;
    } else if (genre != null) {
      candidates = genre.tracks;
    } else {
      candidates = _allTracks;
    }

    return candidates.where((track) {
      if (album != null &&
          !identical(track.album, album) &&
          track.album?.id != album.id) {
        return false;
      }
      if (artist != null &&
          !track.artists.any(
            (a) => identical(a, artist) || a.id == artist.id,
          )) {
        return false;
      }
      if (genre != null &&
          !track.genres.any((g) => identical(g, genre) || g.id == genre.id)) {
        return false;
      }
      return true;
    }).toList();
  }

  List<Track> searchTracks(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _allTracks.where((t) {
      if (t.title.toLowerCase().contains(q)) return true;
      if (t.album != null && t.album!.name.toLowerCase().contains(q)) {
        return true;
      }
      if (t.artists.any((a) => a.name.toLowerCase().contains(q))) return true;
      return false;
    }).toList();
  }

  List<Album> searchAlbums(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _allAlbums.where((a) {
      if (a.name.toLowerCase().contains(q)) return true;
      if (a.artist != null && a.artist!.name.toLowerCase().contains(q)) {
        return true;
      }
      return false;
    }).toList();
  }

  List<Artist> searchArtists(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _allArtists.where((a) => a.name.toLowerCase().contains(q)).toList();
  }
}
