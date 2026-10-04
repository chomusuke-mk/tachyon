import 'package:tachyon/features/library/domain/album.dart';
import 'package:tachyon/features/library/domain/artist.dart';
import 'package:tachyon/features/library/domain/catalog_snapshot.dart';
import 'package:tachyon/features/library/domain/genre.dart';
import 'package:tachyon/features/library/domain/playlist.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/library/domain/track_sort_option.dart';

/// In-memory relational graph for the UI Isolate.
///
/// Features:
/// - O(N) single-pass hydration from [CatalogSnapshot].
/// - 100% pointer identity: shared entities point to identical memory addresses.
/// - Bi-directional pointer linking (track <-> album, track <-> artist, track <-> genre, playlistEntry <-> playlist & track).
/// - O(1) ID lookups for tracks, albums, artists, genres, and playlists.
/// - In-memory filtering, searching, and sorting with 0 SQLite calls.
class LibraryStore {
  // Primary indices for O(1) lookups
  final Map<int, Track> _tracksById = {};
  final Map<String, Track> _tracksByPath = {};
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

  LibraryStore();

  /// Creates a hydrated [LibraryStore] from a [CatalogSnapshot].
  factory LibraryStore.fromSnapshot(CatalogSnapshot snapshot) {
    final store = LibraryStore();
    store.hydrateFromSnapshot(snapshot);
    return store;
  }

  // ---------------------------------------------------------------------------
  // Getters & Collections
  // ---------------------------------------------------------------------------
  List<Track> get tracks => List.unmodifiable(_allTracks);
  List<Track> get allTracks => List.unmodifiable(_allTracks);

  List<Album> get albums => List.unmodifiable(_allAlbums);
  List<Album> get allAlbums => List.unmodifiable(_allAlbums);

  List<Artist> get artists => List.unmodifiable(_allArtists);
  List<Artist> get allArtists => List.unmodifiable(_allArtists);

  List<Genre> get genres => List.unmodifiable(_allGenres);
  List<Genre> get allGenres => List.unmodifiable(_allGenres);

  List<Playlist> get playlists => List.unmodifiable(_allPlaylists);
  List<Playlist> get allPlaylists => List.unmodifiable(_allPlaylists);

  Set<int> get likedTrackIds => Set.unmodifiable(_likedTrackIds);

  Playlist? get likedSongsPlaylist =>
      _allPlaylists.where((p) => p.type == PlaylistType.liked).firstOrNull;

  Playlist? get historyPlaylist =>
      _allPlaylists.where((p) => p.type == PlaylistType.history).firstOrNull;

  List<Playlist> get userPlaylists =>
      _allPlaylists.where((p) => p.type == PlaylistType.user).toList();

  // ---------------------------------------------------------------------------
  // O(1) Lookups
  // ---------------------------------------------------------------------------
  Track? getTrackById(int id) => _tracksById[id];
  Track? getTrackByPath(String path) => _tracksByPath[path];
  Album? getAlbumById(int id) => _albumsById[id];
  Artist? getArtistById(int id) => _artistsById[id];
  Genre? getGenreById(int id) => _genresById[id];
  Playlist? getPlaylistById(int id) => _playlistsById[id];

  bool isTrackLiked(int trackId) => _likedTrackIds.contains(trackId);

  // ---------------------------------------------------------------------------
  // Hydration Algorithm (O(N) single-pass)
  // ---------------------------------------------------------------------------
  void hydrateFromSnapshot(CatalogSnapshot snapshot) {
    _tracksById.clear();
    _tracksByPath.clear();
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

    // 2. Instantiate Artists with mutable backing lists for bi-directional linking
    final artistAlbumsMap = <int, List<Album>>{};
    final artistTracksMap = <int, List<Track>>{};

    for (final rawArtist in snapshot.artists) {
      final albumsList = <Album>[];
      final tracksList = <Track>[];
      artistAlbumsMap[rawArtist.id] = albumsList;
      artistTracksMap[rawArtist.id] = tracksList;

      final artist = Artist(
        id: rawArtist.id,
        name: rawArtist.name,
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

      final album = Album(
        id: rawAlbum.id,
        name: rawAlbum.name,
        year: rawAlbum.year,
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

      final linkedArtistIds = trackToArtistIds[rawTrack.id] ?? const [];
      final linkedArtists = <Artist>[];
      for (final aId in linkedArtistIds) {
        final artist = _artistsById[aId];
        if (artist != null) {
          linkedArtists.add(artist);
        }
      }

      final linkedGenreIds = trackToGenreIds[rawTrack.id] ?? const [];
      final linkedGenres = <Genre>[];
      for (final gId in linkedGenreIds) {
        final genre = _genresById[gId];
        if (genre != null) {
          linkedGenres.add(genre);
        }
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
        codec: rawTrack.codec,
        fileSize: rawTrack.fileSize,
        modifiedAt: rawTrack.modifiedAt,
        replayGainTrackGain: rawTrack.replayGainTrackGain,
        replayGainTrackPeak: rawTrack.replayGainTrackPeak,
        album: album,
        artists: linkedArtists,
        genres: linkedGenres,
      );

      _tracksById[rawTrack.id] = track;
      _tracksByPath[rawTrack.filePath] = track;
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
    }
  }

  // ---------------------------------------------------------------------------
  // In-Memory Mutations
  // ---------------------------------------------------------------------------
  void setTrackLiked(int trackId, bool isLiked) {
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
          final newEntry = PlaylistEntry(
            id: null,
            position: likedPl.entries.length,
            addedAt: DateTime.now().millisecondsSinceEpoch,
            playlist: likedPl,
            track: track,
          );
          likedPl.entries.add(newEntry);
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
    }
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

    if (playlist.type == PlaylistType.liked) {
      _likedTrackIds.add(trackId);
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
    if (playlist.type == PlaylistType.liked) {
      _likedTrackIds.remove(trackId);
    }
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
  }

  void addPlaylist(Playlist playlist) {
    if (playlist.id != null) {
      _playlistsById[playlist.id!] = playlist;
    }
    _allPlaylists.add(playlist);
  }

  void removePlaylist(int playlistId) {
    _playlistsById.remove(playlistId);
    _allPlaylists.removeWhere((p) => p.id == playlistId);
  }

  void removeTrack(int trackId) {
    final track = _tracksById.remove(trackId);
    if (track == null) return;
    _tracksByPath.remove(track.filePath);
    _allTracks.removeWhere((t) => t.id == trackId);

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
        g?.tracks.removeWhere((t) => t.id == trackId);
      }
    }

    for (final playlist in _allPlaylists) {
      playlist.entries.removeWhere((e) => e.track?.id == trackId);
    }
    _likedTrackIds.remove(trackId);
  }

  // ---------------------------------------------------------------------------
  // In-Memory Search, Filter, and Sort (0 SQL Calls)
  // ---------------------------------------------------------------------------
  List<Track> sortTracks(
    List<Track> list,
    TrackSortOption option, {
    bool ascending = true,
  }) {
    final copy = List<Track>.of(list);
    copy.sort((a, b) {
      int cmp;
      switch (option) {
        case TrackSortOption.title:
          cmp = a.title.toLowerCase().compareTo(b.title.toLowerCase());
          break;
        case TrackSortOption.artist:
          final aArtist = a.artists.firstOrNull?.name ?? '';
          final bArtist = b.artists.firstOrNull?.name ?? '';
          cmp = aArtist.toLowerCase().compareTo(bArtist.toLowerCase());
          break;
        case TrackSortOption.album:
          final aAlbum = a.album?.name ?? '';
          final bAlbum = b.album?.name ?? '';
          cmp = aAlbum.toLowerCase().compareTo(bAlbum.toLowerCase());
          break;
        case TrackSortOption.year:
          cmp = (a.year ?? 0).compareTo(b.year ?? 0);
          break;
        case TrackSortOption.duration:
          cmp = a.durationMs.compareTo(b.durationMs);
          break;
        case TrackSortOption.dateAdded:
          cmp = a.modifiedAt.compareTo(b.modifiedAt);
          break;
      }
      if (cmp == 0) {
        cmp = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      }
      return ascending ? cmp : -cmp;
    });
    return copy;
  }

  List<Track> filterTracks({
    Album? album,
    Artist? artist,
    Genre? genre,
  }) {
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
      if (album != null && !identical(track.album, album) && track.album?.id != album.id) {
        return false;
      }
      if (artist != null && !track.artists.any((a) => identical(a, artist) || a.id == artist.id)) {
        return false;
      }
      if (genre != null && !track.genres.any((g) => identical(g, genre) || g.id == genre.id)) {
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
      if (t.album != null && t.album!.name.toLowerCase().contains(q)) return true;
      if (t.artists.any((a) => a.name.toLowerCase().contains(q))) return true;
      return false;
    }).toList();
  }

  List<Album> searchAlbums(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _allAlbums.where((a) {
      if (a.name.toLowerCase().contains(q)) return true;
      if (a.artist != null && a.artist!.name.toLowerCase().contains(q)) return true;
      return false;
    }).toList();
  }

  List<Artist> searchArtists(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _allArtists.where((a) => a.name.toLowerCase().contains(q)).toList();
  }
}
