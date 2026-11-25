import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:tachyon/core/playback/domain/radio_station.dart';
import 'package:tachyon/core/store/library_store.dart';
import 'package:tachyon/features/radios/data/radio_browser_service.dart';

/// Presentation state controller managing online Radio Browser discovery,
/// async preloading on app startup, tag/country filtering, and automatic
/// stream link validation for saved stations.
class RadioController extends ChangeNotifier {
  /// Service used to query the Radio Browser API.
  final RadioBrowserService service;

  /// Library store used to read and persist saved radio stations.
  final LibraryStore store;

  /// Creates a [RadioController] backed by [service] and [store].
  RadioController({
    required this.service,
    required this.store,
  });

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------
  List<RadioStation> _discoverStations = const [];
  List<String> _popularTags = const [];
  List<String> _popularCountries = const [];

  String _selectedTag = 'All';
  String _selectedCountry = 'All';
  String _searchQuery = '';
  int _currentTabIndex = 0;

  Timer? _debounceTimer;
  int _searchRequestId = 0;

  bool _isLoading = false;
  bool _isPreloaded = false;
  bool _isRefreshing = false;
  String? _errorMessage;

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------

  /// Currently loaded stations in the Discover tab.
  List<RadioStation> get discoverStations => _discoverStations;

  /// Popular genre and tag filter values preloaded from [service].
  List<String> get popularTags => _popularTags;

  /// Popular country filter values preloaded from [service].
  List<String> get popularCountries => _popularCountries;

  /// Active genre/tag filter, or `'All'` when unfiltered.
  String get selectedTag => _selectedTag;

  /// Active country filter, or `'All'` when unfiltered.
  String get selectedCountry => _selectedCountry;

  /// Current station search query string.
  String get searchQuery => _searchQuery;

  /// Index of the active tab (`0` for saved stations, `1` for Discover).
  int get currentTabIndex => _currentTabIndex;

  /// Updates [currentTabIndex] to [index] and notifies listeners when changed.
  void setTabIndex(int index) {
    if (_currentTabIndex != index) {
      _currentTabIndex = index;
      notifyListeners();
    }
  }

  /// Whether discovery stations are currently loading.
  bool get isLoading => _isLoading;

  /// Whether initial startup preloading has completed.
  bool get isPreloaded => _isPreloaded;

  /// Whether a manual refresh and link validation pass is running.
  bool get isRefreshing => _isRefreshing;

  /// Error message from the most recent failed discovery request, if any.
  String? get errorMessage => _errorMessage;

  /// Returns whether [station] is already saved in [store].
  bool isStationSaved(RadioStation station) {
    return store.radioStations.any(
      (s) =>
          s.streamUrl == station.streamUrl ||
          (s.stationUuid != null &&
              station.stationUuid != null &&
              s.stationUuid == station.stationUuid),
    );
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  /// Asynchronously preloads top stations, genres, and countries on app startup
  /// without blocking UI rendering, and validates saved stations against the platform.
  Future<void> init() async {
    _isLoading = true;
    _errorMessage = null;

    try {
      final results = await Future.wait([
        service.getTopStations(limit: 60),
        service.getPopularTags(limit: 150),
        service.getPopularCountries(limit: 150),
      ]);

      _discoverStations = results[0] as List<RadioStation>;
      _popularTags = results[1] as List<String>;
      _popularCountries = results[2] as List<String>;
      _isPreloaded = true;

      // Validate saved stations against Radio Browser to update any expired or altered links
      await _validateSavedStations();
    } catch (e) {
      _errorMessage = e.toString();
      debugPrint('[RadioController] init error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Refreshes the discovery directory and re-validates saved stations.
  Future<void> refresh() async {
    _isRefreshing = true;
    notifyListeners();

    try {
      if (_searchQuery.isNotEmpty ||
          _selectedTag != 'All' ||
          _selectedCountry != 'All') {
        await _executeSearch();
      } else {
        final top = await service.getTopStations(limit: 60);
        _discoverStations = top;
      }

      await _validateSavedStations();
    } catch (e) {
      debugPrint('[RadioController] refresh error: $e');
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }

  /// Live search by station name or keywords with automatic debouncing.
  void search(String query) {
    _searchQuery = query;
    _debounceTimer?.cancel();
    if (query.trim().isEmpty) {
      _executeSearch();
    } else {
      _debounceTimer = Timer(const Duration(milliseconds: 320), () {
        _executeSearch();
      });
    }
  }

  /// Selects a genre/tag filter.
  Future<void> setTag(String tag) async {
    if (_selectedTag == tag) return;
    _selectedTag = tag;
    _debounceTimer?.cancel();
    await _executeSearch();
  }

  /// Selects a country filter.
  Future<void> setCountry(String country) async {
    if (_selectedCountry == country) return;
    _selectedCountry = country;
    _debounceTimer?.cancel();
    await _executeSearch();
  }

  /// Clears active search keywords and filters back to global top stations.
  Future<void> clearFilters() async {
    _debounceTimer?.cancel();
    _searchQuery = '';
    _selectedTag = 'All';
    _selectedCountry = 'All';
    await _executeSearch();
  }

  /// Saves a remote station into the local library catalog.
  Future<RadioStation?> saveToLibrary(RadioStation station) async {
    final saved = await store.saveRadioStationInStore(station);
    notifyListeners();
    return saved;
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Internal Helpers
  // ---------------------------------------------------------------------------

  Future<void> _executeSearch() async {
    final requestId = ++_searchRequestId;
    _isLoading = true;
    notifyListeners();

    try {
      final isFilterEmpty = _searchQuery.trim().isEmpty &&
          (_selectedTag == 'All' || _selectedTag.isEmpty) &&
          (_selectedCountry == 'All' || _selectedCountry.isEmpty);

      final List<RadioStation> results;
      if (isFilterEmpty) {
        results = await service.getTopStations(limit: 60);
      } else {
        results = await service.searchStations(
          name: _searchQuery.trim().isNotEmpty ? _searchQuery : null,
          tag: _selectedTag != 'All' ? _selectedTag : null,
          country: _selectedCountry != 'All' ? _selectedCountry : null,
          limit: 60,
        );
      }

      // Discard results if a newer search request has already been issued
      if (requestId != _searchRequestId) return;

      _discoverStations = results;
      _errorMessage = null;
    } catch (e) {
      if (requestId != _searchRequestId) return;
      _errorMessage = e.toString();
      debugPrint('[RadioController] _executeSearch error: $e');
    } finally {
      if (requestId == _searchRequestId) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _validateSavedStations() async {
    final saved = store.radioStations;
    if (saved.isEmpty) return;

    try {
      final updatedStations = await service.validateAndRefreshStations(saved);
      for (final updated in updatedStations) {
        await store.saveRadioStationInStore(updated);
        debugPrint(
          '[RadioController] Updated stream URL/metadata for: ${updated.name}',
        );
      }
    } catch (e) {
      debugPrint('[RadioController] Error validating saved stations: $e');
    }
  }
}
