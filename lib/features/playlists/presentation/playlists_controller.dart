import 'package:flutter/foundation.dart';

import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/library/domain/playlist.dart';
import 'package:tachyon/features/library/domain/track.dart';

class PlaylistsController extends ChangeNotifier {
  final AppDatabase _database;

  PlaylistsController({required this._database});

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
      _playlists = await _database.getAllPlaylists();

      // Pre-cache liked track IDs for O(1) synchronous UI lookups
      final likedTrackIds = await _database.getTrackIdsForPlaylist(
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
          _selectedPlaylistTracks = await _database.getTracksForPlaylist(
            found.id!,
          );
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
        _selectedPlaylistTracks = await _database.getTracksForPlaylist(
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

    final id = await _database.createPlaylist(clean);
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

    await _database.database.update(
      'playlists',
      {'name': clean},
      where: 'id = ?',
      whereArgs: [playlistId],
    );
    await loadPlaylists();
  }

  Future<void> deletePlaylist(int playlistId) async {
    if (playlistId == AppDatabase.likedSongsPlaylistId ||
        playlistId == AppDatabase.historyPlaylistId) {
      return; // Protected system playlist
    }

    await _database.deletePlaylist(playlistId);
    if (_selectedPlaylist?.id == playlistId) {
      _selectedPlaylist = null;
      _selectedPlaylistTracks.clear();
    }
    await loadPlaylists();
  }

  Future<void> addTrackToPlaylist(int playlistId, int trackId) async {
    await _database.addTrackToPlaylist(playlistId, trackId);
    if (playlistId == AppDatabase.likedSongsPlaylistId) {
      _likedTrackIds.add(trackId);
    }
    if (_selectedPlaylist?.id == playlistId) {
      _selectedPlaylistTracks = await _database.getTracksForPlaylist(
        playlistId,
      );
    }
    await loadPlaylists();
  }

  Future<void> removeTrackFromPlaylist(int playlistId, int trackId) async {
    await _database.removeTrackFromPlaylist(playlistId, trackId);
    if (playlistId == AppDatabase.likedSongsPlaylistId) {
      _likedTrackIds.remove(trackId);
    }
    if (_selectedPlaylist?.id == playlistId) {
      _selectedPlaylistTracks = await _database.getTracksForPlaylist(
        playlistId,
      );
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

    await _database.reorderPlaylistEntries(playlistId, fromIndex, toIndex);
  }

  Future<void> toggleLikeTrack(Track track) async {
    if (track.id == null) return;
    final trackId = track.id!;

    // Optimistic in-memory update
    final wasLiked = _likedTrackIds.contains(trackId);
    if (wasLiked) {
      _likedTrackIds.remove(trackId);
    } else {
      _likedTrackIds.add(trackId);
    }
    notifyListeners();

    try {
      await _database.toggleLikeTrack(trackId, track.uri);
      // Refresh Liked Songs playlist track count in background
      _playlists = await _database.getAllPlaylists();
      if (_selectedPlaylist?.id == AppDatabase.likedSongsPlaylistId) {
        _selectedPlaylistTracks = await _database.getTracksForPlaylist(
          AppDatabase.likedSongsPlaylistId,
        );
      }
      notifyListeners();
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

  Future<void> clearHistory() async {
    await _database.clearHistory();
    if (_selectedPlaylist?.id == AppDatabase.historyPlaylistId) {
      _selectedPlaylistTracks.clear();
    }
    await loadPlaylists();
  }
}
