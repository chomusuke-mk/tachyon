import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tachyon/features/library/data/library_store.dart';
import 'package:tachyon/features/library/domain/album.dart';
import 'package:tachyon/features/library/domain/artist.dart';
import 'package:tachyon/features/library/domain/track.dart';

enum SearchFilterCategory { all, tracks, albums, artists }

class TachyonSearchController extends ChangeNotifier {
  final LibraryStore Function()? storeSupplier;
  final LibraryStore? store;

  TachyonSearchController({
    this.store,
    this.storeSupplier,
  });

  LibraryStore get _currentStore {
    final supplier = storeSupplier;
    if (supplier != null) {
      return supplier();
    }
    final directStore = store;
    if (directStore != null) {
      return directStore;
    }
    return LibraryStore();
  }

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

  bool get hasResults {
    switch (_category) {
      case SearchFilterCategory.all:
        return _matchedTracks.isNotEmpty ||
            _matchedAlbums.isNotEmpty ||
            _matchedArtists.isNotEmpty;
      case SearchFilterCategory.tracks:
        return _matchedTracks.isNotEmpty;
      case SearchFilterCategory.albums:
        return _matchedAlbums.isNotEmpty;
      case SearchFilterCategory.artists:
        return _matchedArtists.isNotEmpty;
    }
  }

  // ---------------------------------------------------------------------------
  // Operations
  // ---------------------------------------------------------------------------
  void onQueryChanged(String newQuery, {bool debounce = true}) {
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

    _debounceTimer?.cancel();
    if (debounce) {
      _isSearching = true;
      notifyListeners();
      _debounceTimer = Timer(const Duration(milliseconds: 150), () {
        _performSearch(newQuery.trim());
      });
    } else {
      _performSearch(newQuery.trim());
    }
  }

  void _performSearch(String cleanQuery) {
    final store = _currentStore;
    _matchedTracks = store.searchTracks(cleanQuery);
    _matchedAlbums = store.searchAlbums(cleanQuery);
    _matchedArtists = store.searchArtists(cleanQuery);
    _isSearching = false;
    notifyListeners();
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
