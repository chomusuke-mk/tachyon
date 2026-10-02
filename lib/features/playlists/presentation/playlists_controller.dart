import 'package:flutter/foundation.dart';

import 'package:tachyon/core/backend/backend.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/library/domain/playlist.dart';
import 'package:tachyon/features/library/domain/track.dart';

class PlaylistsController extends ChangeNotifier {
  final TachyonBackendClient _backend;

  PlaylistsController({required this._backend});

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

  bool isTrackLiked(int trackId) => _likedTrackIds.contains(trackId);

  // ---------------------------------------------------------------------------
  // Operations
  // ---------------------------------------------------------------------------
  Future<void> loadPlaylists() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _playlists = await _backend.getPlaylists();

      // Pre-cache liked track IDs for O(1) synchronous UI lookups
      final likedTrackIds = await _backend.getPlaylistTrackIds(
        AppDatabase.likedSongsPlaylistId,
      );
      _likedTrackIds.clear();
      _likedTrackIds.addAll(likedTrackIds);

      if (_selectedPlaylist != null) {
        final found = _playlists
            .where((p) => p.id == _selectedPlaylist!.id)
            .firstOrNull;
        if (found != null) {
          _selectedPlaylist = found;
          _selectedPlaylistTracks = await _backend.getPlaylistTracks(found.id!);
        } else {
          _selectedPlaylist = null;
          _selectedPlaylistTracks.clear();
        }
      }
    } catch (e, st) {
      _errorMessage = 'Failed to load playlists: $e';
      debugPrint('$_errorMessage\n$st');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> selectPlaylist(Playlist playlist) async {
    _selectedPlaylist = playlist;
    _isLoading = true;
    notifyListeners();

    try {
      if (playlist.id != null) {
        _selectedPlaylistTracks = await _backend.getPlaylistTracks(
          playlist.id!,
        );
      } else {
        _selectedPlaylistTracks = [];
      }
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

    final id = await _backend.createPlaylist(clean);
    await loadPlaylists();
    return id;
  }

  Future<void> renamePlaylist(int playlistId, String newName) async {
    final clean = newName.trim();
    if (clean.isEmpty) return;
    if (playlistId == AppDatabase.likedSongsPlaylistId ||
        playlistId == AppDatabase.historyPlaylistId) {
      return; // Protected system playlist
    }

    await _backend.renamePlaylist(playlistId, clean);
    await loadPlaylists();
  }

  Future<void> deletePlaylist(int playlistId) async {
    if (playlistId == AppDatabase.likedSongsPlaylistId ||
        playlistId == AppDatabase.historyPlaylistId) {
      return; // Protected system playlist
    }

    await _backend.deletePlaylist(playlistId);
    if (_selectedPlaylist?.id == playlistId) {
      _selectedPlaylist = null;
      _selectedPlaylistTracks.clear();
    }
    await loadPlaylists();
  }

  Future<void> addTrackToPlaylist(int playlistId, int trackId) async {
    await _backend.addTracksToPlaylist(playlistId, [trackId]);
    if (playlistId == AppDatabase.likedSongsPlaylistId) {
      _likedTrackIds.add(trackId);
    }
    if (_selectedPlaylist?.id == playlistId) {
      _selectedPlaylistTracks = await _backend.getPlaylistTracks(playlistId);
    }
    await loadPlaylists();
  }

  Future<void> removeTrackFromPlaylist(int playlistId, int trackId) async {
    await _backend.removeTrackFromPlaylist(playlistId, trackId);
    if (playlistId == AppDatabase.likedSongsPlaylistId) {
      _likedTrackIds.remove(trackId);
    }
    if (_selectedPlaylist?.id == playlistId) {
      _selectedPlaylistTracks = await _backend.getPlaylistTracks(playlistId);
    }
    await loadPlaylists();
  }

  Future<void> reorderPlaylistEntries(
    int playlistId,
    int fromIndex,
    int toIndex,
  ) async {
    if (fromIndex < 0 || fromIndex >= _selectedPlaylistTracks.length) return;
    if (toIndex < 0 || toIndex >= _selectedPlaylistTracks.length) return;

    // Optimistic UI update
    final item = _selectedPlaylistTracks.removeAt(fromIndex);
    _selectedPlaylistTracks.insert(toIndex, item);
    notifyListeners();

    await _backend.reorderPlaylistTracks(playlistId, fromIndex, toIndex);
  }

  Future<bool> toggleLike(int trackId, [String? filePath]) async {
    // Optimistic in-memory update
    final wasLiked = _likedTrackIds.contains(trackId);
    if (wasLiked) {
      _likedTrackIds.remove(trackId);
    } else {
      _likedTrackIds.add(trackId);
    }
    notifyListeners();

    try {
      final isLiked = await _backend.toggleLikeTrack(trackId, filePath);
      if (isLiked) {
        _likedTrackIds.add(trackId);
      } else {
        _likedTrackIds.remove(trackId);
      }
      // Refresh Liked Songs playlist track count in background
      _playlists = await _backend.getPlaylists();
      if (_selectedPlaylist?.id == AppDatabase.likedSongsPlaylistId) {
        _selectedPlaylistTracks = await _backend.getPlaylistTracks(
          AppDatabase.likedSongsPlaylistId,
        );
      }
      notifyListeners();
      return isLiked;
    } catch (e) {
      // Revert optimistic update on failure
      if (wasLiked) {
        _likedTrackIds.add(trackId);
      } else {
        _likedTrackIds.remove(trackId);
      }
      notifyListeners();
      rethrow;
    }
  }

  Future<void> toggleLikeTrack(Track track) async {
    if (track.id == null) return;
    await toggleLike(track.id!, track.filePath);
  }

  Future<void> clearHistory() async {
    await _backend.clearHistory();
    if (_selectedPlaylist?.id == AppDatabase.historyPlaylistId) {
      _selectedPlaylistTracks.clear();
    }
    await loadPlaylists();
  }
}
