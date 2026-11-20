import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:miniaudio_player/miniaudio_player.dart' as ma;
import 'package:path/path.dart' as p;
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/metadata/domain/discovered_audio_file.dart';
import 'package:tachyon/core/store/domain/album.dart';
import 'package:tachyon/core/store/domain/artist.dart';
import 'package:tachyon/core/store/domain/catalog_snapshot.dart';
import 'package:tachyon/core/store/domain/genre.dart';
import 'package:tachyon/core/store/domain/playlist.dart';
import 'package:tachyon/core/store/domain/track.dart';
import 'package:tachyon/core/playback/domain/radio_station.dart';
import 'package:tachyon/core/store/domain/track_sort_option.dart';
import 'package:tachyon/core/store/domain/album_sort_option.dart';
import 'package:tachyon/core/store/domain/artist_sort_option.dart';
import 'package:tachyon/core/metadata/metadata_utils.dart';
import 'package:tachyon/shared/utils/parse_utils.dart';
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
  static const int likedSongsPlaylistId = 1;
  static const int historyPlaylistId = 2;

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

  // Ephemeral external tracks (id < 0) for instant zero-latency playback
  final Map<int, Track> _ephemeralTracksById = {};
  int _nextEphemeralId = -1;

  // Provisional discovered tracks staged before background metadata extraction finishes
  final Map<String, Track> _pendingDiscoveredByPath = {};

  bool get hasPendingDiscoveredTracks => _pendingDiscoveredByPath.isNotEmpty;
  int get pendingDiscoveredCount => _pendingDiscoveredByPath.length;

  // Ordered lists
  final List<Track> _allTracks = [];
  final List<Album> _allAlbums = [];
  final List<Artist> _allArtists = [];
  final List<Genre> _allGenres = [];
  final List<Playlist> _allPlaylists = [];

  // Fast set of liked track IDs
  final Set<int> _likedTrackIds = <int>{};

  // Radio stations
  final List<RadioStation> _radioStations = [];

  // Cached zero-copy unmodifiable views, invalidated on collection mutation
  List<Track>? _tracksView;
  List<Album>? _albumsView;
  List<Artist>? _artistsView;
  List<Genre>? _genresView;
  List<Playlist>? _playlistsView;
  Set<int>? _likedTrackIdsView;
  List<RadioStation>? _radioStationsView;

  bool _isHydrated = false;
  bool get isHydrated => _isHydrated;

  void _invalidateViews() {
    _tracksView = null;
    _albumsView = null;
    _artistsView = null;
    _genresView = null;
    _playlistsView = null;
    _likedTrackIdsView = null;
    _radioStationsView = null;
  }

  LibraryStore([this._database]);

  /// Creates a hydrated [LibraryStore] from a [CatalogSnapshot].
  factory LibraryStore.fromSnapshot(
    CatalogSnapshot snapshot, [
    AppDatabase? database,
    List<RadioStation>? radioStations,
  ]) {
    final store = LibraryStore(database);
    store.hydrateFromSnapshot(snapshot, radioStations: radioStations);
    return store;
  }

  /// Reloads the entire relational catalog from [AppDatabase] and hydrates the graph.
  Future<void> reloadFromDatabase() async {
    final db = _database;
    if (db == null) return;
    final snapshot = await db.getCatalogSnapshot();
    final stations = await db.getRadioStations();
    hydrateFromSnapshot(snapshot, radioStations: stations);
  }

  // ---------------------------------------------------------------------------
  // Getters & Collections
  // ---------------------------------------------------------------------------
  List<Track> get tracks => _tracksView ??= UnmodifiableListView(_allTracks);

  List<Album> get albums => _albumsView ??= UnmodifiableListView(_allAlbums);

  List<Artist> get artists =>
      _artistsView ??= UnmodifiableListView(_allArtists);

  List<Genre> get genres => _genresView ??= UnmodifiableListView(_allGenres);

  List<Playlist> get playlists =>
      _playlistsView ??= UnmodifiableListView(_allPlaylists);

  List<RadioStation> get radioStations =>
      _radioStationsView ??= UnmodifiableListView(_radioStations);

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
  Track? getTrackById(int id) => id < 0 ? _ephemeralTracksById[id] : _tracksById[id];
  Track? getTrackByPath(String path) {
    final indexed = _tracksByPath[path];
    if (indexed != null) return indexed;
    for (final t in _ephemeralTracksById.values) {
      if (t.filePath == path) return t;
    }
    return null;
  }

  /// Registers an external unindexed track with a negative ID (id < 0) for instant playback.
  /// Does not pollute indexed collections or SQLite.
  Track registerEphemeralTrack(String filePath, {String? title, String? artist}) {
    final existing = getTrackByPath(filePath);
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
      artists: artist != null && artist.isNotEmpty ? [Artist(name: artist)] : const [],
    );
    _ephemeralTracksById[id] = track;
    return track;
  }

  /// Updates metadata of an ephemeral track when background extraction completes.
  void updateEphemeralTrack(Track updated) {
    if (updated.id != null && updated.id! < 0) {
      _ephemeralTracksById[updated.id!] = updated;
      notifyListeners();
    }
  }

  /// Removes an ephemeral track from session memory.
  void removeEphemeralTrack(int id) {
    if (id < 0) {
      _ephemeralTracksById.remove(id);
    }
  }
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

  /// Returns stored track info (`(id, filePath, modifiedAt)`) from RAM.
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

  /// Stages newly discovered audio files as provisional [Track] entries in RAM
  /// so they are immediately visible and playable while background analysis runs.
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

  /// Enriches a provisional pending track using metadata received during live
  /// playback. Never mutates already-persisted database tracks.
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

    final nextBitrate =
        (audioInfo != null && audioInfo.bitrate > 0)
            ? audioInfo.bitrate
            : existing.bitrate;
    final nextSampleRate =
        (audioInfo != null && audioInfo.sampleRate > 0)
            ? audioInfo.sampleRate
            : existing.sampleRate;
    final nextChannels =
        (audioInfo != null && audioInfo.channels > 0)
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

  /// Collects all active cover art URIs/paths across tracks, albums, and artists in RAM.
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

  // ---------------------------------------------------------------------------
  // Hydration Algorithm (O(N) single-pass)
  // ---------------------------------------------------------------------------
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

    // Pre-calculate artwork fallbacks from snapshot
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

    // 2. Instantiate Artists with mutable backing lists for bi-directional linking
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
        artworkUri:
            resolveArtwork(rawTrack.artworkUri) ?? album?.artworkUri,
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

    if (radioStations != null) {
      _radioStations
        ..clear()
        ..addAll(radioStations);
      _sortRadioStations();
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
    notifyListeners();
  }

  void addPlaylist(Playlist playlist) {
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
        g?.tracks.removeWhere((t) => t.id == trackId);
      }
    }

    for (final playlist in _allPlaylists) {
      playlist.entries.removeWhere((e) => e.track?.id == trackId);
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

  Future<RadioStation?> saveRadioStationInStore(RadioStation station) async {
    final db = _database;
    if (db == null) return null;
    final saved = await db.saveRadioStation(station);
    final idx = _radioStations.indexWhere(
      (s) => (saved.id != null && s.id == saved.id) || s.streamUrl == saved.streamUrl,
    );
    if (idx != -1) {
      _radioStations[idx] = saved;
    } else {
      _radioStations.add(saved);
    }
    _sortRadioStations();
    _invalidateViews();
    notifyListeners();
    return saved;
  }

  Future<void> deleteRadioStationInStore(int id) async {
    final db = _database;
    if (db == null) return;
    await db.deleteRadioStation(id);
    _radioStations.removeWhere((s) => s.id == id);
    _invalidateViews();
    notifyListeners();
  }

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
    _invalidateViews();
    notifyListeners();
  }

  void _sortRadioStations() {
    _radioStations.sort((a, b) {
      if (a.isFavorite != b.isFavorite) {
        return a.isFavorite ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
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
