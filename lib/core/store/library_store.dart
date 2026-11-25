import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:miniaudio_player/miniaudio_player.dart' as ma;
import 'package:path/path.dart' as p;
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/logging/app_logger.dart';
import 'package:tachyon/core/metadata/domain/discovered_audio_file.dart';
import 'package:tachyon/core/metadata/metadata_utils.dart';
import 'package:tachyon/core/playback/domain/radio_station.dart';
import 'package:tachyon/core/store/domain/album.dart';
import 'package:tachyon/core/store/domain/album_sort_option.dart';
import 'package:tachyon/core/store/domain/artist.dart';
import 'package:tachyon/core/store/domain/artist_sort_option.dart';
import 'package:tachyon/core/store/domain/catalog_snapshot.dart';
import 'package:tachyon/core/store/domain/genre.dart';
import 'package:tachyon/core/store/domain/playlist.dart';
import 'package:tachyon/core/store/domain/track.dart';
import 'package:tachyon/core/store/domain/track_sort_option.dart';
import 'package:tachyon/shared/utils/parse_utils.dart';
import 'package:tachyon/shared/utils/waveform_codec.dart';

part 'library_store_hydration.dart';
part 'library_store_mutations.dart';
part 'library_store_queries.dart';

const _log = ScopedLogger('LibraryStore');

/// Shared state holder for [LibraryStore] mixins across part files.
abstract class _LibraryStoreState extends ChangeNotifier {
  static const int likedSongsPlaylistId = 1;
  static const int historyPlaylistId = 2;

  final AppDatabase? _database;
  final math.Random _random = math.Random();

  final Map<int, Track> _tracksById = {};
  final Map<String, Track> _tracksByPath = {};
  final Map<String, List<Track>> _tracksByDirectory = {};
  final Map<int, Album> _albumsById = {};
  final Map<int, Artist> _artistsById = {};
  final Map<int, Genre> _genresById = {};
  final Map<int, Playlist> _playlistsById = {};

  final Map<int, Track> _ephemeralTracksById = {};
  int _nextEphemeralId = -1;

  final Map<String, Track> _pendingDiscoveredByPath = {};

  final List<Track> _allTracks = [];
  final List<Album> _allAlbums = [];
  final List<Artist> _allArtists = [];
  final List<Genre> _allGenres = [];
  final List<Playlist> _allPlaylists = [];

  final Set<int> _likedTrackIds = <int>{};
  final List<RadioStation> _radioStations = [];

  List<Track>? _tracksView;
  List<Album>? _albumsView;
  List<Artist>? _artistsView;
  List<Genre>? _genresView;
  List<Playlist>? _playlistsView;
  Set<int>? _likedTrackIdsView;
  List<RadioStation>? _radioStationsView;

  bool _isHydrated = false;

  _LibraryStoreState([this._database]);

  Playlist? get _likedSongsPlaylistInternal =>
      _allPlaylists.where((p) => p.type == PlaylistType.liked).firstOrNull;

  Playlist? get _historyPlaylistInternal =>
      _allPlaylists.where((p) => p.type == PlaylistType.history).firstOrNull;

  void _invalidateViews() {
    _tracksView = null;
    _albumsView = null;
    _artistsView = null;
    _genresView = null;
    _playlistsView = null;
    _likedTrackIdsView = null;
    _radioStationsView = null;
  }

  void _sortRadioStations() {
    _radioStations.sort((a, b) {
      if (a.isFavorite != b.isFavorite) {
        return a.isFavorite ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  }
}

/// In-memory relational graph for the Main Isolate.
///
/// Features:
/// - $O(N)$ single-pass hydration from [CatalogSnapshot].
/// - 100% pointer identity where shared entities point to identical objects.
/// - Bi-directional pointer linking between tracks, albums, artists, genres, and playlists.
/// - $O(1)$ ID lookups and zero-SQL filtering, searching, and sorting.
class LibraryStore extends _LibraryStoreState
    with
        _LibraryStoreHydrationMixin,
        _LibraryStoreMutationsMixin,
        _LibraryStoreQueriesMixin {
  /// Database ID reserved for the built-in Liked Songs playlist.
  static const int likedSongsPlaylistId = _LibraryStoreState.likedSongsPlaylistId;

  /// Database ID reserved for the built-in playback History playlist.
  static const int historyPlaylistId = _LibraryStoreState.historyPlaylistId;

  /// Creates a [LibraryStore] optionally backed by [database].
  LibraryStore([super.database]);

  /// Creates a hydrated [LibraryStore] directly from [snapshot] and optional [radioStations].
  factory LibraryStore.fromSnapshot(
    CatalogSnapshot snapshot, [
    AppDatabase? database,
    List<RadioStation>? radioStations,
  ]) {
    final store = LibraryStore(database);
    store.hydrateFromSnapshot(snapshot, radioStations: radioStations);
    return store;
  }

  /// Reloads the entire relational catalog from [AppDatabase] and rehydrates RAM.
  Future<void> reloadFromDatabase() async {
    final db = _database;
    if (db == null) return;
    _log.d('Reloading catalog snapshot from AppDatabase');
    final snapshot = await db.getCatalogSnapshot();
    final stations = await db.getRadioStations();
    hydrateFromSnapshot(snapshot, radioStations: stations);
  }

  /// Whether any provisional tracks discovered during an active scan are awaiting extraction.
  bool get hasPendingDiscoveredTracks => _pendingDiscoveredByPath.isNotEmpty;

  /// Number of provisional tracks currently awaiting metadata extraction.
  int get pendingDiscoveredCount => _pendingDiscoveredByPath.length;

  /// Whether the store has been hydrated from a snapshot at least once.
  bool get isHydrated => _isHydrated;

  /// Unmodifiable view of all tracks currently in memory.
  List<Track> get tracks => _tracksView ??= UnmodifiableListView(_allTracks);

  /// Unmodifiable view of all albums currently in memory.
  List<Album> get albums => _albumsView ??= UnmodifiableListView(_allAlbums);

  /// Unmodifiable view of all artists currently in memory.
  List<Artist> get artists =>
      _artistsView ??= UnmodifiableListView(_allArtists);

  /// Unmodifiable view of all genres currently in memory.
  List<Genre> get genres => _genresView ??= UnmodifiableListView(_allGenres);

  /// Unmodifiable view of all playlists currently in memory.
  List<Playlist> get playlists =>
      _playlistsView ??= UnmodifiableListView(_allPlaylists);

  /// Unmodifiable view of all saved radio stations currently in memory.
  List<RadioStation> get radioStations =>
      _radioStationsView ??= UnmodifiableListView(_radioStations);

  /// Unmodifiable set of track IDs currently marked as liked.
  Set<int> get likedTrackIds =>
      _likedTrackIdsView ??= UnmodifiableSetView(_likedTrackIds);

  /// Built-in Liked Songs playlist, if hydrated.
  Playlist? get likedSongsPlaylist => _likedSongsPlaylistInternal;

  /// Built-in History playlist, if hydrated.
  Playlist? get historyPlaylist => _historyPlaylistInternal;

  /// All user-created playlists currently in memory.
  List<Playlist> get userPlaylists =>
      _allPlaylists.where((p) => p.type == PlaylistType.user).toList();
}
