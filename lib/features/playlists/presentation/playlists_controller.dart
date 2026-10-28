import 'package:flutter/foundation.dart';

import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/store/domain/playlist.dart';
import 'package:tachyon/core/store/domain/track.dart';
import 'package:tachyon/core/store/library_store.dart';

class PlaylistsController extends ChangeNotifier {
  final LibraryStore store;
  bool _isDisposed = false;

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
  List<Playlist> get playlists => _playlists;
  Playlist? get selectedPlaylist => _selectedPlaylist;
  List<Track> get selectedPlaylistTracks =>
      List.unmodifiable(_selectedPlaylistTracks);

  Playlist? get likedSongsPlaylist =>
      _playlists.where((p) => p.type == PlaylistType.liked).firstOrNull;

  Playlist? get historyPlaylist =>
      _playlists.where((p) => p.type == PlaylistType.history).firstOrNull;

  List<Playlist> get userPlaylists =>
      _playlists.where((p) => p.type == PlaylistType.user).toList();

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

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
        _selectedPlaylistTracks = found.entries
            .map((e) => e.track)
            .whereType<Track>()
            .toList();
      } else {
        _selectedPlaylist = null;
        _selectedPlaylistTracks = [];
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Operations
  // ---------------------------------------------------------------------------
  Future<void> loadPlaylists() async {
    _errorMessage = null;
    try {
      _syncFromStore();
    } catch (e, st) {
      _errorMessage = 'Failed to load playlists: $e';
      debugPrint('$_errorMessage\n$st');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> selectPlaylist(Playlist playlist) async {
    _errorMessage = null;
    try {
      if (playlist.id != null) {
        final found = store.getPlaylistById(playlist.id!);
        if (found != null) {
          _selectedPlaylist = found;
          _selectedPlaylistTracks = found.entries
              .map((e) => e.track)
              .whereType<Track>()
              .toList();
          return;
        }
      }

      // Resolve directly from memory pointers in playlist entries
      _selectedPlaylist = playlist;
      _selectedPlaylistTracks = playlist.entries
          .map((e) => e.track)
          .whereType<Track>()
          .toList();
    } catch (e) {
      _errorMessage = 'Failed to load playlist tracks: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<int> createPlaylist(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return -1;

    try {
      final playlist = await store.createPlaylistInStore(clean);
      _syncFromStore();
      notifyListeners();
      return playlist?.id ?? -1;
    } catch (e) {
      debugPrint('[PlaylistsController] createPlaylist error: $e');
      return -1;
    }
  }

  Future<void> renamePlaylist(int playlistId, String newName) async {
    final clean = newName.trim();
    if (clean.isEmpty) return;
    if (playlistId == AppDatabase.likedSongsPlaylistId ||
        playlistId == AppDatabase.historyPlaylistId) {
      return; // Protected system playlist
    }

    try {
      await store.renamePlaylistInStore(playlistId, clean);
      _syncFromStore();
      notifyListeners();
    } catch (e) {
      debugPrint('[PlaylistsController] renamePlaylist error: $e');
    }
  }

  Future<void> deletePlaylist(int playlistId) async {
    if (playlistId == AppDatabase.likedSongsPlaylistId ||
        playlistId == AppDatabase.historyPlaylistId) {
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
      debugPrint('[PlaylistsController] deletePlaylist error: $e');
    }
  }

  Future<void> addTrackToPlaylist(int playlistId, int trackId) async {
    try {
      await store.addTrackToPlaylistInStore(playlistId, trackId);
      _syncFromStore();
      notifyListeners();
    } catch (e) {
      debugPrint('[PlaylistsController] addTrackToPlaylist error: $e');
    }
  }

  Future<void> addTracksToPlaylist(int playlistId, List<int> trackIds) async {
    if (trackIds.isEmpty) return;
    try {
      await store.addTracksToPlaylistInStore(playlistId, trackIds);
      _syncFromStore();
      notifyListeners();
    } catch (e) {
      debugPrint('[PlaylistsController] addTracksToPlaylist error: $e');
    }
  }

  Future<void> removeTrackFromPlaylist(int playlistId, int trackId) async {
    try {
      await store.removeTrackFromPlaylistInStore(playlistId, trackId);
      _syncFromStore();
      notifyListeners();
    } catch (e) {
      debugPrint('[PlaylistsController] removeTrackFromPlaylist error: $e');
    }
  }

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
      debugPrint('[PlaylistsController] reorderPlaylistEntries error: $e');
      await loadPlaylists();
    }
  }

  Future<bool> toggleLike(int trackId) async {
    try {
      final isLiked = await store.toggleLikeInStore(trackId);
      _syncFromStore();
      notifyListeners();
      return isLiked;
    } catch (e) {
      debugPrint('[PlaylistsController] toggleLike error: $e');
      return isTrackLiked(trackId);
    }
  }

  Future<void> toggleLikeTrack(Track track) async {
    if (track.id == null) return;
    await toggleLike(track.id!);
  }

  Future<void> clearHistory() async {
    try {
      if (_selectedPlaylist?.id == AppDatabase.historyPlaylistId) {
        _selectedPlaylistTracks.clear();
      }
      await store.clearHistoryInStore();
      _syncFromStore();
      notifyListeners();
    } catch (e) {
      debugPrint('[PlaylistsController] clearHistory error: $e');
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
