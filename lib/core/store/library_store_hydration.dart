part of 'library_store.dart';

mixin _LibraryStoreHydrationMixin on _LibraryStoreState {
  /// Populates the entire relational object graph in a single $O(N)$ pass from [snapshot].
  ///
  /// When [radioStations] is provided, replaces and sorts the radio stations collection.
  void hydrateFromSnapshot(
    CatalogSnapshot snapshot, {
    List<RadioStation>? radioStations,
  }) {
    _invalidateViews();
    _pendingDiscoveredByPath.clear();
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

    String? resolveArtwork(String? value) {
      if (value == null) return null;
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        return internString(trimmed);
      }
      if (p.isAbsolute(trimmed)) {
        return internString(trimmed);
      }
      if (MetadataUtils.thumbnailsDirectory != null) {
        return internString(MetadataUtils.getArtworkPath(trimmed));
      }
      return internString(trimmed);
    }

    final albumFirstTrackArtwork = <int, String>{};
    for (final rawTrack in snapshot.tracks) {
      if (rawTrack.albumId != null) {
        final uri = resolveArtwork(rawTrack.artworkUri);
        if (uri != null) {
          albumFirstTrackArtwork.putIfAbsent(rawTrack.albumId!, () => uri);
        }
      }
    }

    final effectiveAlbumArtworks = <int, String>{};
    final artistFirstAlbumArtwork = <int, String>{};
    for (final rawAlbum in snapshot.albums) {
      final uri =
          resolveArtwork(rawAlbum.artworkUri) ??
          albumFirstTrackArtwork[rawAlbum.id];
      if (uri != null) {
        effectiveAlbumArtworks[rawAlbum.id] = uri;
        if (rawAlbum.artistId != null) {
          artistFirstAlbumArtwork.putIfAbsent(rawAlbum.artistId!, () => uri);
        }
      }
    }

    final trackEffectiveArtwork = <int, String>{};
    for (final rawTrack in snapshot.tracks) {
      final uri =
          resolveArtwork(rawTrack.artworkUri) ??
          (rawTrack.albumId != null
              ? effectiveAlbumArtworks[rawTrack.albumId]
              : null);
      if (uri != null) {
        trackEffectiveArtwork[rawTrack.id] = uri;
      }
    }

    final artistFirstTrackArtwork = <int, String>{};
    for (final pair in snapshot.trackArtists) {
      final uri = trackEffectiveArtwork[pair.trackId];
      if (uri != null) {
        artistFirstTrackArtwork.putIfAbsent(pair.artistId, () => uri);
      }
    }

    final artistAlbumsMap = <int, List<Album>>{};
    final artistTracksMap = <int, List<Track>>{};
    for (final rawArtist in snapshot.artists) {
      final albumsList = <Album>[];
      final tracksList = <Track>[];
      artistAlbumsMap[rawArtist.id] = albumsList;
      artistTracksMap[rawArtist.id] = tracksList;

      final effectiveArtwork =
          resolveArtwork(rawArtist.artworkUri) ??
          artistFirstAlbumArtwork[rawArtist.id] ??
          artistFirstTrackArtwork[rawArtist.id];

      final artist = Artist(
        id: rawArtist.id,
        name: rawArtist.name,
        artworkUri: effectiveArtwork,
        albums: albumsList,
        tracks: tracksList,
      );
      _artistsById[rawArtist.id] = artist;
      _allArtists.add(artist);
    }

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

    final albumTracksMap = <int, List<Track>>{};
    for (final rawAlbum in snapshot.albums) {
      final tracksList = <Track>[];
      albumTracksMap[rawAlbum.id] = tracksList;

      final artist = rawAlbum.artistId != null
          ? _artistsById[rawAlbum.artistId]
          : null;

      final effectiveAlbumArtwork =
          resolveArtwork(rawAlbum.artworkUri) ??
          effectiveAlbumArtworks[rawAlbum.id];

      final album = Album(
        id: rawAlbum.id,
        name: rawAlbum.name,
        year: rawAlbum.year,
        artworkUri: effectiveAlbumArtwork,
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
        artworkUri: resolveArtwork(rawTrack.artworkUri) ?? album?.artworkUri,
        album: album,
        artists: linkedArtists,
        genres: linkedGenres,
      );

      _tracksById[rawTrack.id] = track;
      _tracksByPath[rawTrack.filePath] = track;
      final trackDir = p.normalize(p.dirname(rawTrack.filePath));
      _tracksByDirectory.putIfAbsent(trackDir, () => []).add(track);
      _allTracks.add(track);

      if (album != null && album.id != null) {
        albumTracksMap[album.id]?.add(track);
      }

      for (final artist in linkedArtists) {
        if (artist.id != null) {
          artistTracksMap[artist.id]?.add(track);
          if (album != null) {
            final aAlbums = artistAlbumsMap[artist.id];
            if (aAlbums != null && !aAlbums.contains(album)) {
              aAlbums.add(album);
            }
          }
        }
      }

      for (final genre in linkedGenres) {
        if (genre.id != null) {
          genreTracksMap[genre.id]?.add(track);
        }
      }
    }

    for (final tracksList in albumTracksMap.values) {
      tracksList.sort((a, b) {
        final discComp = (a.discNumber ?? 1).compareTo(b.discNumber ?? 1);
        if (discComp != 0) return discComp;
        return (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0);
      });
    }

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

    if (radioStations != null) {
      _radioStations
        ..clear()
        ..addAll(radioStations);
      _sortRadioStations();
    }

    _isHydrated = true;
    _log.d(
      'Hydrated catalog: tracks=${_allTracks.length} albums=${_allAlbums.length} '
      'artists=${_allArtists.length} genres=${_allGenres.length} '
      'playlists=${_allPlaylists.length} radios=${_radioStations.length}',
    );
    notifyListeners();
  }
}
