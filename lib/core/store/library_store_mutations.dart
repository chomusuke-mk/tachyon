part of 'library_store.dart';

mixin _LibraryStoreMutationsMixin on _LibraryStoreState {
  /// Registers an external unindexed track with a negative ID (`id < 0`) for
  /// instant playback without polluting indexed collections or SQLite.
  Track registerEphemeralTrack(
    String filePath, {
    String? title,
    String? artist,
  }) {
    final existing = _tracksByPath[filePath];
    if (existing != null) return existing;

    for (final track in _ephemeralTracksById.values) {
      if (track.filePath == filePath) return track;
    }

    final id = _nextEphemeralId--;
    final filename = p.basenameWithoutExtension(filePath);
    final track = Track(
      id: id,
      filePath: filePath,
      title: title ?? (filename.isNotEmpty ? filename : filePath),
      durationMs: 0,
      fileSize: 0,
      modifiedAt: DateTime.now().millisecondsSinceEpoch,
      artists: artist != null && artist.isNotEmpty
          ? [Artist(name: artist)]
          : const [],
    );
    _ephemeralTracksById[id] = track;
    return track;
  }

  /// Updates metadata of an ephemeral track after background extraction completes.
  void updateEphemeralTrack(Track updated) {
    if (updated.id != null && updated.id! < 0) {
      _ephemeralTracksById[updated.id!] = updated;
      _tracksView = null;
      notifyListeners();
    }
  }

  /// Removes an ephemeral track from session memory by [id].
  void removeEphemeralTrack(int id) {
    if (id < 0) {
      _ephemeralTracksById.remove(id);
    }
  }

  /// Stages newly discovered audio [files] as provisional [Track] entries in RAM
  /// so they are immediately visible and playable while background scanning runs.
  void stageDiscoveredFiles(List<DiscoveredAudioFile> files) {
    final incomingPaths = <String>{for (final f in files) f.path};
    var changed = false;

    final stalePaths = <String>[
      for (final path in _pendingDiscoveredByPath.keys)
        if (!incomingPaths.contains(path)) path,
    ];
    for (final path in stalePaths) {
      final removed = _pendingDiscoveredByPath.remove(path);
      if (removed == null) continue;
      if (identical(_tracksByPath[path], removed)) {
        _tracksByPath.remove(path);
      }
      final dir = p.normalize(p.dirname(path));
      _tracksByDirectory[dir]?.removeWhere((t) => identical(t, removed));
      _allTracks.removeWhere((t) => identical(t, removed));
      changed = true;
    }

    for (final file in files) {
      if (_tracksByPath.containsKey(file.path)) continue;
      final extClean = p.extension(file.path).replaceAll('.', '').toUpperCase();
      final baseName = p.basenameWithoutExtension(file.path);
      final title = baseName.isNotEmpty ? baseName : p.basename(file.path);
      final provisional = Track(
        id: null,
        filePath: file.path,
        title: title,
        durationMs: 0,
        codec: extClean.isNotEmpty ? extClean : null,
        fileSize: file.size,
        modifiedAt: file.modifiedAt,
        isMetadataPending: true,
      );
      _pendingDiscoveredByPath[file.path] = provisional;
      _tracksByPath[file.path] = provisional;
      final dir = p.normalize(p.dirname(file.path));
      _tracksByDirectory.putIfAbsent(dir, () => []).add(provisional);
      _allTracks.add(provisional);
      changed = true;
    }

    if (changed) {
      _invalidateViews();
      notifyListeners();
    }
  }

  /// Removes all provisional pending tracks staged during discovery.
  ///
  /// Set [notify] to `false` when immediately following up with full hydration.
  void clearPendingDiscoveredTracks({bool notify = true}) {
    if (_pendingDiscoveredByPath.isEmpty) return;
    for (final entry in _pendingDiscoveredByPath.entries) {
      final path = entry.key;
      final track = entry.value;
      if (identical(_tracksByPath[path], track)) {
        _tracksByPath.remove(path);
      }
      final dir = p.normalize(p.dirname(path));
      _tracksByDirectory[dir]?.removeWhere((t) => identical(t, track));
      _allTracks.removeWhere((t) => identical(t, track));
    }
    _pendingDiscoveredByPath.clear();
    _invalidateViews();
    if (notify) {
      notifyListeners();
    }
  }

  /// Enriches a provisional pending track at [filePath] using live playback
  /// [metadata], [audioInfo], [artworkUri], or [duration] without mutating
  /// persisted database tracks.
  Track? updatePendingTrackFromLivePlayback({
    required String filePath,
    ma.AudioMetadata? metadata,
    ma.AudioInfo? audioInfo,
    String? artworkUri,
    Duration? duration,
  }) {
    final existing = _pendingDiscoveredByPath[filePath];
    if (existing == null) return null;

    String? nonEmpty(String? v) {
      final trimmed = v?.trim();
      return (trimmed != null && trimmed.isNotEmpty) ? trimmed : null;
    }

    final nextTitle = nonEmpty(metadata?.title) ?? existing.title;

    List<Artist> nextArtists = existing.artists;
    final rawTrackArtist = nonEmpty(metadata?.trackArtist);
    final rawAlbumArtist = nonEmpty(metadata?.albumArtist);
    if (rawTrackArtist != null) {
      final parsed = rawTrackArtist
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .map((name) => Artist(name: name))
          .toList(growable: false);
      if (parsed.isNotEmpty) {
        nextArtists = parsed;
      }
    } else if (rawAlbumArtist != null) {
      nextArtists = [Artist(name: rawAlbumArtist)];
    }

    final albumName = nonEmpty(metadata?.album);
    final nextYear = metadata?.year ?? existing.year;
    final Album? nextAlbum = albumName != null
        ? Album(name: albumName, year: nextYear)
        : existing.album;

    final infoDurMs = audioInfo?.duration?.inMilliseconds ?? 0;
    final argDurMs = duration?.inMilliseconds ?? 0;
    final nextDurationMs = infoDurMs > 0
        ? infoDurMs
        : (argDurMs > 0 ? argDurMs : existing.durationMs);

    final nextBitrate = (audioInfo != null && audioInfo.bitrate > 0)
        ? audioInfo.bitrate
        : existing.bitrate;
    final nextSampleRate = (audioInfo != null && audioInfo.sampleRate > 0)
        ? audioInfo.sampleRate
        : existing.sampleRate;
    final nextChannels = (audioInfo != null && audioInfo.channels > 0)
        ? audioInfo.channels
        : existing.channels;
    final nextCodec =
        (audioInfo != null &&
            audioInfo.codec.isNotEmpty &&
            audioInfo.codec != 'Unknown')
        ? audioInfo.codec
        : existing.codec;

    final nextTrackNumber = metadata?.trackNumber ?? existing.trackNumber;
    final nextDiscNumber = metadata?.discNumber ?? existing.discNumber;

    String? nextArtworkUri = existing.artworkUri;
    final cleanArt = nonEmpty(artworkUri);
    if (cleanArt != null) {
      if (cleanArt.startsWith('http://') ||
          cleanArt.startsWith('https://') ||
          p.isAbsolute(cleanArt)) {
        nextArtworkUri = cleanArt;
      } else if (MetadataUtils.thumbnailsDirectory != null) {
        nextArtworkUri = MetadataUtils.getArtworkPath(cleanArt);
      } else {
        nextArtworkUri = cleanArt;
      }
    }

    final nextGain =
        ParseUtils.parseDouble(metadata?.replayGainTrackGain) ??
        existing.replayGainTrackGain;
    final nextPeak =
        ParseUtils.parseDouble(metadata?.replayGainTrackPeak) ??
        existing.replayGainTrackPeak;

    bool artistsEqual(List<Artist> a, List<Artist> b) {
      if (identical(a, b)) return true;
      if (a.length != b.length) return false;
      for (int i = 0; i < a.length; i++) {
        if (a[i].name != b[i].name) return false;
      }
      return true;
    }

    if (nextTitle == existing.title &&
        artistsEqual(existing.artists, nextArtists) &&
        nextAlbum?.name == existing.album?.name &&
        nextYear == existing.year &&
        nextTrackNumber == existing.trackNumber &&
        nextDiscNumber == existing.discNumber &&
        nextDurationMs == existing.durationMs &&
        nextBitrate == existing.bitrate &&
        nextSampleRate == existing.sampleRate &&
        nextChannels == existing.channels &&
        nextCodec == existing.codec &&
        nextArtworkUri == existing.artworkUri &&
        nextGain == existing.replayGainTrackGain &&
        nextPeak == existing.replayGainTrackPeak) {
      return existing;
    }

    final updated = Track(
      id: null,
      filePath: existing.filePath,
      title: nextTitle,
      trackNumber: nextTrackNumber,
      discNumber: nextDiscNumber,
      year: nextYear,
      durationMs: nextDurationMs,
      bitrate: nextBitrate,
      sampleRate: nextSampleRate,
      channels: nextChannels,
      codec: nextCodec,
      fileSize: existing.fileSize,
      modifiedAt: existing.modifiedAt,
      replayGainTrackGain: nextGain,
      replayGainTrackPeak: nextPeak,
      waveform: existing.waveform,
      artworkUri: nextArtworkUri,
      album: nextAlbum,
      genres: existing.genres,
      artists: nextArtists,
      isMetadataPending: true,
    );

    _pendingDiscoveredByPath[filePath] = updated;
    _tracksByPath[filePath] = updated;

    final allIdx = _allTracks.indexWhere((t) => identical(t, existing));
    if (allIdx != -1) {
      _allTracks[allIdx] = updated;
    } else {
      final pathIdx = _allTracks.indexWhere(
        (t) => t.filePath == filePath && t.isMetadataPending,
      );
      if (pathIdx != -1) {
        _allTracks[pathIdx] = updated;
      }
    }

    final dir = p.normalize(p.dirname(filePath));
    final dirList = _tracksByDirectory[dir];
    if (dirList != null) {
      final dirIdx = dirList.indexWhere((t) => identical(t, existing));
      if (dirIdx != -1) {
        dirList[dirIdx] = updated;
      } else {
        final pathIdx = dirList.indexWhere(
          (t) => t.filePath == filePath && t.isMetadataPending,
        );
        if (pathIdx != -1) {
          dirList[pathIdx] = updated;
        }
      }
    }

    _invalidateViews();
    notifyListeners();
    return updated;
  }

  /// Sets the liked state of [trackId] to [isLiked] in memory.
  void setTrackLiked(int trackId, bool isLiked) {
    _likedTrackIdsView = null;
    if (isLiked) {
      _likedTrackIds.add(trackId);
    } else {
      _likedTrackIds.remove(trackId);
    }

    final likedPl = _likedSongsPlaylistInternal;
    if (likedPl != null) {
      if (isLiked) {
        final alreadyIn = likedPl.entries.any((e) => e.track?.id == trackId);
        if (!alreadyIn) {
          final track = _tracksById[trackId];
          if (track != null) {
            likedPl.entries.add(
              PlaylistEntry(
                id: null,
                position: likedPl.entries.length,
                addedAt: DateTime.now().millisecondsSinceEpoch,
                playlist: likedPl,
                track: track,
              ),
            );
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
    }
    notifyListeners();
  }

  /// Toggles the in-memory liked state of [trackId] and returns the new state.
  bool toggleTrackLiked(int trackId) {
    final nextState = !_likedTrackIds.contains(trackId);
    setTrackLiked(trackId, nextState);
    return nextState;
  }

  /// Inserts [trackId] into [playlistId] in memory at optional [position].
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

    if (playlist.type == PlaylistType.liked) {
      _likedTrackIdsView = null;
      _likedTrackIds.add(trackId);
    }
    notifyListeners();
  }

  /// Appends all [trackIds] to [playlistId] in memory.
  void addTracksToPlaylist(int playlistId, List<int> trackIds) {
    if (trackIds.isEmpty) return;
    for (final trackId in trackIds) {
      addTrackToPlaylist(playlistId, trackId);
    }
  }

  /// Removes [trackId] from [playlistId] in memory and compacts entry positions.
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
      _likedTrackIdsView = null;
      _likedTrackIds.remove(trackId);
    }
    notifyListeners();
  }

  /// Moves a playlist entry inside [playlistId] from [fromIndex] to [toIndex] in RAM.
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
    notifyListeners();
  }

  /// Adds [playlist] to the in-memory store.
  void addPlaylist(Playlist playlist) {
    if (playlist.id != null) {
      _playlistsById[playlist.id!] = playlist;
    }
    _allPlaylists.add(playlist);
    _playlistsView = null;
    notifyListeners();
  }

  /// Removes the playlist identified by [playlistId] from memory.
  void removePlaylist(int playlistId) {
    _playlistsById.remove(playlistId);
    _allPlaylists.removeWhere((p) => p.id == playlistId);
    _playlistsView = null;
    notifyListeners();
  }

  /// Updates the display name of [playlistId] to [newName] in memory.
  void renamePlaylist(int playlistId, String newName) {
    final playlist = _playlistsById[playlistId];
    if (playlist == null) return;
    final updated = Playlist(
      id: playlist.id,
      name: newName,
      createdAt: playlist.createdAt,
      type: playlist.type,
      entries: playlist.entries,
    );
    _playlistsById[playlistId] = updated;
    final index = _allPlaylists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      _allPlaylists[index] = updated;
    }
    _playlistsView = null;
    notifyListeners();
  }

  /// Clears all entries from the History playlist in memory.
  void clearHistory() {
    _historyPlaylistInternal?.entries.clear();
    notifyListeners();
  }

  /// Removes [trackId] and all its back-links from the in-memory graph.
  void removeTrack(int trackId) {
    final track = _tracksById.remove(trackId);
    if (track == null) return;
    _tracksByPath.remove(track.filePath);
    final trackDir = p.normalize(p.dirname(track.filePath));
    _tracksByDirectory[trackDir]?.removeWhere((t) => t.id == trackId);
    _allTracks.removeWhere((t) => t.id == trackId);
    _tracksView = null;

    if (track.album != null && track.album!.id != null) {
      _albumsById[track.album!.id]?.tracks.removeWhere((t) => t.id == trackId);
    }

    for (final artist in track.artists) {
      if (artist.id != null) {
        _artistsById[artist.id]?.tracks.removeWhere((t) => t.id == trackId);
      }
    }

    for (final genre in track.genres) {
      if (genre.id != null) {
        _genresById[genre.id]?.tracks.removeWhere((t) => t.id == trackId);
      }
    }

    for (final playlist in _allPlaylists) {
      playlist.entries.removeWhere((e) => e.track?.id == trackId);
    }
    _likedTrackIdsView = null;
    _likedTrackIds.remove(trackId);
    notifyListeners();
  }

  /// Creates a new user playlist named [name] in both RAM and [AppDatabase].
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
    _log.d('Created playlist in store: id=$playlistId name="$trimmed"');
    return playlist;
  }

  /// Deletes the playlist identified by [playlistId] from RAM and [AppDatabase].
  Future<void> deletePlaylistInStore(int playlistId) async {
    _log.d('Deleting playlist in store: id=$playlistId');
    removePlaylist(playlistId);
    await _database?.deletePlaylist(playlistId);
  }

  /// Renames the playlist identified by [playlistId] to [newName] in RAM and SQLite.
  Future<void> renamePlaylistInStore(int playlistId, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    _log.d('Renaming playlist in store: id=$playlistId -> "$trimmed"');
    renamePlaylist(playlistId, trimmed);
    await _database?.renamePlaylist(playlistId, trimmed);
  }

  /// Adds [trackId] to [playlistId] in both RAM and [AppDatabase].
  Future<void> addTrackToPlaylistInStore(int playlistId, int trackId) async {
    addTrackToPlaylist(playlistId, trackId);
    await _database?.addTrackToPlaylist(playlistId, trackId);
  }

  /// Appends [trackIds] to [playlistId] in both RAM and [AppDatabase].
  Future<void> addTracksToPlaylistInStore(
    int playlistId,
    List<int> trackIds,
  ) async {
    if (trackIds.isEmpty) return;
    addTracksToPlaylist(playlistId, trackIds);
    await _database?.addTracksToPlaylist(playlistId, trackIds);
  }

  /// Removes [trackId] from [playlistId] in both RAM and [AppDatabase].
  Future<void> removeTrackFromPlaylistInStore(
    int playlistId,
    int trackId,
  ) async {
    removeTrackFromPlaylist(playlistId, trackId);
    await _database?.removeTrackFromPlaylist(playlistId, trackId);
  }

  /// Reorders an entry in [playlistId] from [fromIndex] to [toIndex] in RAM and SQLite.
  Future<void> reorderPlaylistEntriesInStore(
    int playlistId,
    int fromIndex,
    int toIndex,
  ) async {
    reorderPlaylistEntries(playlistId, fromIndex, toIndex);
    await _database?.reorderPlaylistEntries(playlistId, fromIndex, toIndex);
  }

  /// Toggles the liked status of [trackId] in RAM and [AppDatabase].
  Future<bool> toggleLikeInStore(int trackId) async {
    if (!_tracksById.containsKey(trackId)) return false;
    final nextState = toggleTrackLiked(trackId);
    await _database?.toggleLikeTrack(trackId);
    return nextState;
  }

  /// Clears playback history in both RAM and [AppDatabase].
  Future<void> clearHistoryInStore() async {
    clearHistory();
    await _database?.clearHistory();
  }

  /// Deletes [trackId] and purges orphaned albums/artists/genres in SQLite, then reloads.
  Future<void> deleteTrackInStore(int trackId) async {
    _log.d('Deleting track in store: trackId=$trackId');
    removeTrack(trackId);
    await _database?.deleteTracksAndPurgeOrphans([trackId]);
    if (_database != null) {
      await (this as LibraryStore).reloadFromDatabase();
    }
  }

  /// Clears all catalog tables and rehydrates an empty snapshot.
  Future<void> clearAllDataInStore() async {
    _log.i('Clearing all catalog data in store and database');
    await _database?.clearAllData();
    if (_database != null) {
      final db = _database;
      final snapshot = await db.getCatalogSnapshot();
      final stations = await db.getRadioStations();
      (this as LibraryStore).hydrateFromSnapshot(
        snapshot,
        radioStations: stations,
      );
    } else {
      (this as LibraryStore).hydrateFromSnapshot(
        const CatalogSnapshot.empty(),
      );
    }
  }

  /// Persists or updates [station] in SQLite and updates the sorted in-memory list.
  Future<RadioStation?> saveRadioStationInStore(RadioStation station) async {
    final db = _database;
    if (db == null) return null;
    final saved = await db.saveRadioStation(station);
    final idx = _radioStations.indexWhere(
      (s) =>
          (saved.id != null && s.id == saved.id) ||
          s.streamUrl == saved.streamUrl,
    );
    if (idx != -1) {
      _radioStations[idx] = saved;
    } else {
      _radioStations.add(saved);
    }
    _sortRadioStations();
    _radioStationsView = null;
    notifyListeners();
    return saved;
  }

  /// Deletes the radio station with [id] from SQLite and RAM.
  Future<void> deleteRadioStationInStore(int id) async {
    final db = _database;
    if (db == null) return;
    await db.deleteRadioStation(id);
    _radioStations.removeWhere((s) => s.id == id);
    _radioStationsView = null;
    notifyListeners();
  }

  /// Toggles the favorite flag of radio station [id] in SQLite and RAM.
  Future<void> toggleRadioStationFavoriteInStore(int id) async {
    final db = _database;
    if (db == null) return;
    final idx = _radioStations.indexWhere((s) => s.id == id);
    if (idx == -1) return;
    final current = _radioStations[idx];
    final newFav = !current.isFavorite;
    await db.setRadioStationFavorite(id, newFav);
    _radioStations[idx] = current.copyWith(isFavorite: newFav);
    _sortRadioStations();
    _radioStationsView = null;
    notifyListeners();
  }
}
