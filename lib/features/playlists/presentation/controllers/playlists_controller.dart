import 'package:flutter/foundation.dart';

import 'package:tachyon/core/logging/app_logger.dart';
import 'package:tachyon/core/store/domain/playlist.dart';
import 'package:tachyon/core/store/domain/track.dart';
import 'package:tachyon/core/store/library_store.dart';

/// State controller managing playlists, liked songs, playback history, and track membership.
class PlaylistsController extends ChangeNotifier {
  static const _log = ScopedLogger('Playlists');

  /// Underlying [LibraryStore] backing playlist persistence and lookups.
  final LibraryStore store;
  bool _isDisposed = false;

  /// Creates a [PlaylistsController] listening to [store] or a new [LibraryStore].
  PlaylistsController({LibraryStore? store}) : store = store ?? LibraryStore() {
    this.store.addListener(_onStoreChanged);
    _syncFromStore();
  }

  void _onStoreChanged() {
    if (_isDisposed) return;
    _syncFromStore();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // State Fields
  // ---------------------------------------------------------------------------
  List<Playlist> _playlists = const [];
  Playlist? _selectedPlaylist;
  List<Track> _selectedPlaylistTracks = [];

  bool _isLoading = false;
  String? _errorMessage;

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------

  /// All playlists currently held in [store], including system and user playlists.
  List<Playlist> get playlists => _playlists;

  /// Currently selected playlist for detail inspection, or `null` if none.
  Playlist? get selectedPlaylist => _selectedPlaylist;

  /// Unmodifiable list of tracks belonging to [selectedPlaylist].
  List<Track> get selectedPlaylistTracks =>
      List.unmodifiable(_selectedPlaylistTracks);

  /// Built-in playlist containing the user's liked tracks, if available.
  Playlist? get likedSongsPlaylist =>
      _playlists.where((p) => p.type == PlaylistType.liked).firstOrNull;

  /// Built-in playlist recording recently played tracks, if available.
  Playlist? get historyPlaylist =>
      _playlists.where((p) => p.type == PlaylistType.history).firstOrNull;

  /// List of custom playlists created by the user.
  List<Playlist> get userPlaylists =>
      _playlists.where((p) => p.type == PlaylistType.user).toList();

  /// Whether playlists are currently loading.
  bool get isLoading => _isLoading;

  /// Error message from the most recent failed playlist load or selection, if any.
  String? get errorMessage => _errorMessage;

  /// Returns whether the track identified by [trackId] is marked as liked.
  bool isTrackLiked(int trackId) => store.isTrackLiked(trackId);

  // ---------------------------------------------------------------------------
  // Store Integration
  // ---------------------------------------------------------------------------
  void _syncFromStore() {
    final s = store;
    _playlists = s.playlists;

    if (_selectedPlaylist != null && _selectedPlaylist!.id != null) {
      final found = s.getPlaylistById(_selectedPlaylist!.id!);
      if (found != null) {
        _selectedPlaylist = found;
        _selectedPlaylistTracks = found.tracks;
      } else {
        _selectedPlaylist = null;
        _selectedPlaylistTracks = [];
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Operations
  // ---------------------------------------------------------------------------

  /// Refreshes [playlists] and [selectedPlaylistTracks] from [store].
  Future<void> loadPlaylists() async {
    _errorMessage = null;
    try {
      _syncFromStore();
    } catch (e, st) {
      _errorMessage = 'Failed to load playlists: $e';
      _log.e(_errorMessage!, error: e, stackTrace: st);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Selects [playlist] and resolves its latest track list from [store].
  Future<void> selectPlaylist(Playlist playlist) async {
    _errorMessage = null;
    try {
      if (playlist.id != null) {
        final found = store.getPlaylistById(playlist.id!);
        if (found != null) {
          _selectedPlaylist = found;
          _selectedPlaylistTracks = found.tracks;
          return;
        }
      }

      // Resolve directly from memory pointers in playlist entries
      _selectedPlaylist = playlist;
      _selectedPlaylistTracks = playlist.tracks;
    } catch (e) {
      _errorMessage = 'Failed to load playlist tracks: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Creates a new user playlist named [name] and returns its ID.
  ///
  /// Returns `-1` if the trimmed [name] is empty or creation fails.
  Future<int> createPlaylist(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return -1;

    try {
      final playlist = await store.createPlaylistInStore(clean);
      _syncFromStore();
      notifyListeners();
      return playlist?.id ?? -1;
    } catch (e) {
      _log.e('createPlaylist error', error: e);
      return -1;
    }
  }

  /// Renames the user playlist identified by [playlistId] to [newName].
  ///
  /// Ignores empty names and protected system playlists (liked songs and history).
  Future<void> renamePlaylist(int playlistId, String newName) async {
    final clean = newName.trim();
    if (clean.isEmpty) return;
    if (playlistId == LibraryStore.likedSongsPlaylistId ||
        playlistId == LibraryStore.historyPlaylistId) {
      return; // Protected system playlist
    }

    try {
      await store.renamePlaylistInStore(playlistId, clean);
      _syncFromStore();
      notifyListeners();
    } catch (e) {
      _log.e('renamePlaylist error', error: e);
    }
  }

  /// Deletes the user playlist identified by [playlistId].
  ///
  /// Ignores protected system playlists (liked songs and history) and clears
  /// [selectedPlaylist] if it matches [playlistId].
  Future<void> deletePlaylist(int playlistId) async {
    if (playlistId == LibraryStore.likedSongsPlaylistId ||
        playlistId == LibraryStore.historyPlaylistId) {
      return; // Protected system playlist
    }

    try {
      if (_selectedPlaylist?.id == playlistId) {
        _selectedPlaylist = null;
        _selectedPlaylistTracks.clear();
      }
      await store.deletePlaylistInStore(playlistId);
      _syncFromStore();
      notifyListeners();
    } catch (e) {
      _log.e('deletePlaylist error', error: e);
    }
  }

  /// Adds the track with [trackId] to the playlist identified by [playlistId].
  Future<void> addTrackToPlaylist(int playlistId, int trackId) async {
    try {
      await store.addTrackToPlaylistInStore(playlistId, trackId);
      _syncFromStore();
      notifyListeners();
    } catch (e) {
      _log.e('addTrackToPlaylist error', error: e);
    }
  }

  /// Adds all tracks in [trackIds] to the playlist identified by [playlistId].
  Future<void> addTracksToPlaylist(int playlistId, List<int> trackIds) async {
    if (trackIds.isEmpty) return;
    try {
      await store.addTracksToPlaylistInStore(playlistId, trackIds);
      _syncFromStore();
      notifyListeners();
    } catch (e) {
      _log.e('addTracksToPlaylist error', error: e);
    }
  }

  /// Removes the track with [trackId] from the playlist identified by [playlistId].
  Future<void> removeTrackFromPlaylist(int playlistId, int trackId) async {
    try {
      await store.removeTrackFromPlaylistInStore(playlistId, trackId);
      _syncFromStore();
      notifyListeners();
    } catch (e) {
      _log.e('removeTrackFromPlaylist error', error: e);
    }
  }

  /// Moves a track within playlist [playlistId] from [fromIndex] to [toIndex].
  ///
  /// Reloads playlists if persistence fails.
  Future<void> reorderPlaylistEntries(
    int playlistId,
    int fromIndex,
    int toIndex,
  ) async {
    if (fromIndex < 0 || fromIndex >= _selectedPlaylistTracks.length) return;
    if (toIndex < 0 || toIndex >= _selectedPlaylistTracks.length) return;

    try {
      await store.reorderPlaylistEntriesInStore(playlistId, fromIndex, toIndex);
      _syncFromStore();
      notifyListeners();
    } catch (e) {
      _log.e('reorderPlaylistEntries error', error: e);
      await loadPlaylists();
    }
  }

  /// Toggles the liked state of [trackId] and returns the updated state.
  Future<bool> toggleLike(int trackId) async {
    try {
      final isLiked = await store.toggleLikeInStore(trackId);
      _syncFromStore();
      notifyListeners();
      return isLiked;
    } catch (e) {
      _log.e('toggleLike error', error: e);
      return isTrackLiked(trackId);
    }
  }

  /// Toggles the liked state of [track] when its ID is non-null.
  Future<void> toggleLikeTrack(Track track) async {
    if (track.id == null) return;
    await toggleLike(track.id!);
  }

  /// Removes all entries from the playback history playlist.
  Future<void> clearHistory() async {
    try {
      if (_selectedPlaylist?.id == LibraryStore.historyPlaylistId) {
        _selectedPlaylistTracks.clear();
      }
      await store.clearHistoryInStore();
      _syncFromStore();
      notifyListeners();
    } catch (e) {
      _log.e('clearHistory error', error: e);
    }
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    store.removeListener(_onStoreChanged);
    super.dispose();
  }
}
