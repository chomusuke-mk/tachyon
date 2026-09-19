import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/library/domain/album.dart';
import 'package:tachyon/features/library/domain/artist.dart';
import 'package:tachyon/features/library/domain/track.dart';

enum SearchFilterCategory { all, tracks, albums, artists }

class TachyonSearchController extends ChangeNotifier {
  final AppDatabase _database;

  TachyonSearchController({required this._database});

  // ---------------------------------------------------------------------------
  // State Fields
  // ---------------------------------------------------------------------------
  String _query = '';
  SearchFilterCategory _category = SearchFilterCategory.all;

  List<Track> _matchedTracks = [];
  List<Album> _matchedAlbums = [];
  List<Artist> _matchedArtists = [];

  bool _isSearching = false;
  Timer? _debounceTimer;

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------
  String get query => _query;
  SearchFilterCategory get category => _category;

  List<Track> get matchedTracks => List.unmodifiable(_matchedTracks);
  List<Album> get matchedAlbums => List.unmodifiable(_matchedAlbums);
  List<Artist> get matchedArtists => List.unmodifiable(_matchedArtists);

  bool get isSearching => _isSearching;
  bool get isEmptyQuery => _query.trim().isEmpty;
  bool get hasResults =>
      _matchedTracks.isNotEmpty ||
      _matchedAlbums.isNotEmpty ||
      _matchedArtists.isNotEmpty;

  // ---------------------------------------------------------------------------
  // Operations
  // ---------------------------------------------------------------------------
  void onQueryChanged(String newQuery) {
    _query = newQuery;

    if (newQuery.trim().isEmpty) {
      _debounceTimer?.cancel();
      _matchedTracks = [];
      _matchedAlbums = [];
      _matchedArtists = [];
      _isSearching = false;
      notifyListeners();
      return;
    }

    _isSearching = true;
    notifyListeners();

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      _performSearch(newQuery.trim());
    });
  }

  Future<void> _performSearch(String cleanQuery) async {
    try {
      final wildcard = '%$cleanQuery%';

      // Concurrent execution of multi-domain searches in SQLite
      final trackFuture = _database.searchTracks(cleanQuery);

      final albumFuture = _database.database.rawQuery(
        '''
        SELECT al.id, al.name, al.artist_id, al.artist_name, al.year, COUNT(t.id) AS track_count
        FROM albums al
        LEFT JOIN tracks t ON t.album_id = al.id
        WHERE al.name LIKE ? OR al.artist_name LIKE ?
        GROUP BY al.id
        ORDER BY al.name COLLATE NOCASE ASC
        LIMIT 25
      ''',
        [wildcard, wildcard],
      );

      final artistFuture = _database.database.rawQuery(
        '''
        SELECT ar.id, ar.name, COUNT(DISTINCT t.id) AS track_count, COUNT(DISTINCT al.id) AS album_count
        FROM artists ar
        LEFT JOIN tracks t ON t.artist_id = ar.id
        LEFT JOIN albums al ON al.artist_id = ar.id
        WHERE ar.name LIKE ?
        GROUP BY ar.id
        ORDER BY ar.name COLLATE NOCASE ASC
        LIMIT 25
      ''',
        [wildcard],
      );

      final results = await Future.wait([
        trackFuture,
        albumFuture,
        artistFuture,
      ]);

      _matchedTracks = results[0] as List<Track>;
      _matchedAlbums = (results[1] as List<Map<String, dynamic>>)
          .map((r) => Album.fromDbMap(r))
          .toList();
      _matchedArtists = (results[2] as List<Map<String, dynamic>>)
          .map((r) => Artist.fromDbMap(r))
          .toList();
    } catch (e) {
      debugPrint('Search query failed: $e');
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  void setCategory(SearchFilterCategory category) {
    if (_category == category) return;
    _category = category;
    notifyListeners();
  }

  void clear() {
    _debounceTimer?.cancel();
    _query = '';
    _matchedTracks = [];
    _matchedAlbums = [];
    _matchedArtists = [];
    _isSearching = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}
