import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tachyon/core/store/domain/album.dart';
import 'package:tachyon/core/store/domain/artist.dart';
import 'package:tachyon/core/store/domain/track.dart';
import 'package:tachyon/core/store/library_store.dart';

/// Category filters available for narrowing library search results.
enum SearchFilterCategory {
  /// Shows matching tracks, albums, and artists.
  all,

  /// Shows only matching tracks.
  tracks,

  /// Shows only matching albums.
  albums,

  /// Shows only matching artists.
  artists,
}

/// State controller managing debounced library searches across tracks, albums, and artists.
class TachyonSearchController extends ChangeNotifier {
  /// Optional lazy supplier returning the current [LibraryStore].
  final LibraryStore Function()? storeSupplier;

  /// Direct [LibraryStore] instance used when [storeSupplier] is not provided.
  final LibraryStore? store;

  /// Creates a [TachyonSearchController] using [store] or [storeSupplier].
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
    throw StateError('LibraryStore must be provided to TachyonSearchController');
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

  /// Raw search query entered by the user.
  String get query => _query;

  /// Active [SearchFilterCategory] filter applied to displayed results.
  SearchFilterCategory get category => _category;

  /// Unmodifiable list of tracks matching [query].
  List<Track> get matchedTracks => List.unmodifiable(_matchedTracks);

  /// Unmodifiable list of albums matching [query].
  List<Album> get matchedAlbums => List.unmodifiable(_matchedAlbums);

  /// Unmodifiable list of artists matching [query].
  List<Artist> get matchedArtists => List.unmodifiable(_matchedArtists);

  /// Whether a debounced search is currently pending execution.
  bool get isSearching => _isSearching;

  /// Whether the trimmed [query] is empty.
  bool get isEmptyQuery => _query.trim().isEmpty;

  /// Whether any results exist for the active [category].
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

  /// Updates [query] to [newQuery] and runs a library search.
  ///
  /// When [debounce] is `true`, delays execution by 150 ms to coalesce rapid
  /// typing; otherwise executes immediately. Clears results if [newQuery] is blank.
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

  /// Sets the active filter [category] and notifies listeners when changed.
  void setCategory(SearchFilterCategory category) {
    if (_category == category) return;
    _category = category;
    notifyListeners();
  }

  /// Clears [query], cancels any pending search timer, and resets all results.
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
