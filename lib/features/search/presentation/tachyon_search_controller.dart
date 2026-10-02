import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tachyon/core/backend/backend.dart';
import 'package:tachyon/features/library/domain/album.dart';
import 'package:tachyon/features/library/domain/artist.dart';
import 'package:tachyon/features/library/domain/track.dart';

enum SearchFilterCategory { all, tracks, albums, artists }

class TachyonSearchController extends ChangeNotifier {
  final TachyonBackendClient _backend;

  TachyonSearchController({required this._backend});

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
      final results = await _backend.search(cleanQuery);
      _matchedTracks = (results['tracks'] as List? ?? []).cast<Track>();
      _matchedAlbums = (results['albums'] as List? ?? []).cast<Album>();
      _matchedArtists = (results['artists'] as List? ?? []).cast<Artist>();
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
