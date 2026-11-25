part of 'library_store.dart';

mixin _LibraryStoreQueriesMixin on _LibraryStoreState {
  /// Returns the [Track] matching [id], checking ephemeral tracks when [id] is negative.
  Track? getTrackById(int id) =>
      id < 0 ? _ephemeralTracksById[id] : _tracksById[id];

  /// Returns the [Track] matching [path] in $O(1)$, or checks ephemeral tracks.
  Track? getTrackByPath(String path) {
    final indexed = _tracksByPath[path];
    if (indexed != null) return indexed;
    for (final t in _ephemeralTracksById.values) {
      if (t.filePath == path) return t;
    }
    return null;
  }

  /// Returns an unmodifiable view of tracks located directly inside [directoryPath].
  List<Track> getTracksInDirectory(String directoryPath) {
    final normalized = p.normalize(directoryPath);
    return UnmodifiableListView(_tracksByDirectory[normalized] ?? const []);
  }

  /// Returns the [Album] matching [id] in $O(1)$, or `null`.
  Album? getAlbumById(int id) => _albumsById[id];

  /// Returns the [Artist] matching [id] in $O(1)$, or `null`.
  Artist? getArtistById(int id) => _artistsById[id];

  /// Returns the [Genre] matching [id] in $O(1)$, or `null`.
  Genre? getGenreById(int id) => _genresById[id];

  /// Returns the [Playlist] matching [id] in $O(1)$, or `null`.
  Playlist? getPlaylistById(int id) => _playlistsById[id];

  /// Whether [trackId] is present in the Liked Songs collection.
  bool isTrackLiked(int trackId) => _likedTrackIds.contains(trackId);

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

  /// Returns stored persisted track records (`id`, `filePath`, `modifiedAt`) from RAM.
  List<({int id, String filePath, int modifiedAt})> getStoredTracks() {
    return <({int id, String filePath, int modifiedAt})>[
      for (final track in _allTracks)
        if (track.id != null && track.id! > 0 && !track.isMetadataPending)
          (
            id: track.id!,
            filePath: track.filePath,
            modifiedAt: track.modifiedAt,
          ),
    ];
  }

  /// Collects all unique cover art URIs referenced by tracks, albums, and artists.
  Set<String> getAllArtworkUris() {
    final uris = <String>{};
    for (final t in _allTracks) {
      if (t.artworkUri != null && t.artworkUri!.isNotEmpty) {
        uris.add(t.artworkUri!);
      }
    }
    for (final a in _allAlbums) {
      if (a.artworkUri != null && a.artworkUri!.isNotEmpty) {
        uris.add(a.artworkUri!);
      }
    }
    for (final ar in _allArtists) {
      if (ar.artworkUri != null && ar.artworkUri!.isNotEmpty) {
        uris.add(ar.artworkUri!);
      }
    }
    return uris;
  }

  /// Returns a sorted copy of [list] ordered by [option] and [ascending].
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

  /// Returns an unmodifiable sorted copy of [list] ordered by [option] and [ascending].
  List<Album> sortAlbums(
    List<Album> list,
    AlbumSortOption option, {
    bool ascending = true,
  }) {
    if (list.length <= 1) return List<Album>.of(list);

    final albums = List<Album>.of(list);
    switch (option) {
      case AlbumSortOption.title:
        final lowerNames = {for (final a in albums) a: a.name.toLowerCase()};
        albums.sort((a, b) {
          final cmp = lowerNames[a]!.compareTo(lowerNames[b]!);
          return ascending ? cmp : -cmp;
        });
        break;
      case AlbumSortOption.artist:
        final lowerArtists = {
          for (final a in albums) a: (a.artist?.name ?? '').toLowerCase(),
        };
        final lowerNames = {for (final a in albums) a: a.name.toLowerCase()};
        albums.sort((a, b) {
          var cmp = lowerArtists[a]!.compareTo(lowerArtists[b]!);
          if (cmp == 0) {
            cmp = lowerNames[a]!.compareTo(lowerNames[b]!);
          }
          return ascending ? cmp : -cmp;
        });
        break;
      case AlbumSortOption.year:
        final lowerNames = {for (final a in albums) a: a.name.toLowerCase()};
        albums.sort((a, b) {
          var cmp = (a.year ?? 0).compareTo(b.year ?? 0);
          if (cmp == 0) {
            cmp = lowerNames[a]!.compareTo(lowerNames[b]!);
          }
          return ascending ? cmp : -cmp;
        });
        break;
      case AlbumSortOption.trackCount:
        final lowerNames = {for (final a in albums) a: a.name.toLowerCase()};
        albums.sort((a, b) {
          var cmp = a.trackCount.compareTo(b.trackCount);
          if (cmp == 0) {
            cmp = lowerNames[a]!.compareTo(lowerNames[b]!);
          }
          return ascending ? cmp : -cmp;
        });
        break;
    }
    return List.unmodifiable(albums);
  }

  /// Returns an unmodifiable sorted copy of [list] ordered by [option] and [ascending].
  List<Artist> sortArtists(
    List<Artist> list,
    ArtistSortOption option, {
    bool ascending = true,
  }) {
    if (list.length <= 1) return List<Artist>.of(list);

    final artists = List<Artist>.of(list);
    switch (option) {
      case ArtistSortOption.name:
        final lowerNames = {for (final a in artists) a: a.name.toLowerCase()};
        artists.sort((a, b) {
          final cmp = lowerNames[a]!.compareTo(lowerNames[b]!);
          return ascending ? cmp : -cmp;
        });
        break;
      case ArtistSortOption.albums:
        final lowerNames = {for (final a in artists) a: a.name.toLowerCase()};
        artists.sort((a, b) {
          var cmp = a.albumCount.compareTo(b.albumCount);
          if (cmp == 0) {
            cmp = lowerNames[a]!.compareTo(lowerNames[b]!);
          }
          return ascending ? cmp : -cmp;
        });
        break;
      case ArtistSortOption.tracks:
        final lowerNames = {for (final a in artists) a: a.name.toLowerCase()};
        artists.sort((a, b) {
          var cmp = a.trackCount.compareTo(b.trackCount);
          if (cmp == 0) {
            cmp = lowerNames[a]!.compareTo(lowerNames[b]!);
          }
          return ascending ? cmp : -cmp;
        });
        break;
    }
    return List.unmodifiable(artists);
  }

  /// Filters tracks in memory matching optional [album], [artist], and [genre] pointers.
  List<Track> filterTracks({Album? album, Artist? artist, Genre? genre}) {
    if (album == null && artist == null && genre == null) {
      return List.unmodifiable(_allTracks);
    }

    final Iterable<Track> candidates;
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

  /// Searches tracks in RAM whose title, album, or artist matches [query].
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

  /// Searches albums in RAM whose name or primary artist matches [query].
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

  /// Searches artists in RAM whose name matches [query].
  List<Artist> searchArtists(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _allArtists.where((a) => a.name.toLowerCase().contains(q)).toList();
  }
}
