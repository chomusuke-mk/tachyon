import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:tachyon/core/backend/backend.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/library/data/library_store.dart';
import 'package:tachyon/features/library/domain/playlist.dart';
import 'package:tachyon/features/library/domain/track.dart';

class PlaylistsController extends ChangeNotifier {
  final TachyonBackendClient backend;
  TachyonBackendClient get _backend => backend;

  LibraryStore store;
  LibraryStore get _store => store;
  set _store(LibraryStore val) => store = val;
  StreamSubscription<void>? _catalogSubscription;
  bool _isDisposed = false;

  PlaylistsController({required this.backend, LibraryStore? store})
      : store = store ?? LibraryStore() {
    _syncFromStore();
  }

  // ---------------------------------------------------------------------------
  // State Fields
  // ---------------------------------------------------------------------------
  List<Playlist> _playlists = [];
  Playlist? _selectedPlaylist;
  List<Track> _selectedPlaylistTracks = [];
  final Set<int> _likedTrackIds = <int>{};

  bool _isLoading = false;
  String? _errorMessage;

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------
  List<Playlist> get playlists => List.unmodifiable(_playlists);
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

  bool isTrackLiked(int trackId) => _store.isTrackLiked(trackId);

  // ---------------------------------------------------------------------------
  // Store Integration
  // ---------------------------------------------------------------------------
  void updateStore(LibraryStore store) {
    _store = store;
    _syncFromStore();
    notifyListeners();
  }

  void _syncFromStore() {
    final s = _store;
    _playlists = s.playlists;
    _likedTrackIds.clear();
    _likedTrackIds.addAll(s.likedTrackIds);

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
        final found = _store.getPlaylistById(playlist.id!);
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
      final id = await _backend.createPlaylist(clean);
      if (id != -1) {
        _store.addPlaylist(Playlist(
          id: id,
          name: clean,
          createdAt: DateTime.now().millisecondsSinceEpoch,
          type: PlaylistType.user,
            entries: [],
        ));
        _syncFromStore();
        notifyListeners();
      }
      return id;
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
      _store.renamePlaylist(playlistId, clean);
      _syncFromStore();
      notifyListeners();
      await _backend.renamePlaylist(playlistId, clean);
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
      _store.removePlaylist(playlistId);
      if (_selectedPlaylist?.id == playlistId) {
        _selectedPlaylist = null;
        _selectedPlaylistTracks.clear();
      }
      _syncFromStore();
      notifyListeners();
      await _backend.deletePlaylist(playlistId);
    } catch (e) {
      debugPrint('[PlaylistsController] deletePlaylist error: $e');
    }
  }

  Future<void> addTrackToPlaylist(int playlistId, int trackId) async {
    _store.addTrackToPlaylist(playlistId, trackId);
    if (playlistId == AppDatabase.likedSongsPlaylistId) {
      _likedTrackIds.add(trackId);
    }
    _syncFromStore();
    notifyListeners();

    try {
      await _backend.addTracksToPlaylist(playlistId, [trackId]);
    } catch (e) {
      debugPrint('[PlaylistsController] addTrackToPlaylist error: $e');
    }
  }

  Future<void> addTracksToPlaylist(int playlistId, List<int> trackIds) async {
    if (trackIds.isEmpty) return;
    _store.addTracksToPlaylist(playlistId, trackIds);
    if (playlistId == AppDatabase.likedSongsPlaylistId) {
      _likedTrackIds.addAll(trackIds);
    }
    _syncFromStore();
    notifyListeners();

    try {
      await _backend.addTracksToPlaylist(playlistId, trackIds);
    } catch (e) {
      debugPrint('[PlaylistsController] addTracksToPlaylist error: $e');
    }
  }

  Future<void> removeTrackFromPlaylist(int playlistId, int trackId) async {
    _store.removeTrackFromPlaylist(playlistId, trackId);
    if (playlistId == AppDatabase.likedSongsPlaylistId) {
      _likedTrackIds.remove(trackId);
    }
    _syncFromStore();
    notifyListeners();

    try {
      await _backend.removeTrackFromPlaylist(playlistId, trackId);
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

    // Optimistic UI update on store and in-memory track list
    _store.reorderPlaylistEntries(playlistId, fromIndex, toIndex);
    final item = _selectedPlaylistTracks.removeAt(fromIndex);
    _selectedPlaylistTracks.insert(toIndex, item);
    notifyListeners();

    try {
      await _backend.reorderPlaylistTracks(playlistId, fromIndex, toIndex);
    } catch (e) {
      debugPrint('[PlaylistsController] reorderPlaylistEntries error: $e');
      await loadPlaylists();
    }
  }

  Future<bool> toggleLike(int trackId, [String? filePath]) async {
    final wasLiked = isTrackLiked(trackId);
    final nowLiked = !wasLiked;
    if (nowLiked) {
      _likedTrackIds.add(trackId);
    } else {
      _likedTrackIds.remove(trackId);
    }
    _store.setTrackLiked(trackId, nowLiked);
    _syncFromStore();
    notifyListeners();

    try {
      final isLiked = await _backend.toggleLikeTrack(trackId, filePath);
      if (isLiked != nowLiked) {
        if (isLiked) {
          _likedTrackIds.add(trackId);
        } else {
          _likedTrackIds.remove(trackId);
        }
        _store.setTrackLiked(trackId, isLiked);
        _syncFromStore();
        notifyListeners();
      }
      return isLiked;
    } catch (e) {
      if (wasLiked) {
        _likedTrackIds.add(trackId);
      } else {
        _likedTrackIds.remove(trackId);
      }
      _store.setTrackLiked(trackId, wasLiked);
      _syncFromStore();
      notifyListeners();
      debugPrint('[PlaylistsController] toggleLike error: $e');
      return wasLiked;
    }
  }

  Future<void> toggleLikeTrack(Track track) async {
    if (track.id == null) return;
    await toggleLike(track.id!, track.filePath);
  }

  Future<void> clearHistory() async {
    try {
      _store.clearHistory();
      if (_selectedPlaylist?.id == AppDatabase.historyPlaylistId) {
        _selectedPlaylistTracks.clear();
      }
      _syncFromStore();
      notifyListeners();
      await _backend.clearHistory();
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
    _catalogSubscription?.cancel();
    _catalogSubscription = null;
    super.dispose();
  }
}
