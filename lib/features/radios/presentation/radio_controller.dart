import 'package:flutter/foundation.dart';
import 'package:tachyon/core/playback/domain/radio_station.dart';
import 'package:tachyon/core/store/library_store.dart';
import 'package:tachyon/features/radios/data/radio_browser_service.dart';

/// Presentation state controller managing online Radio Browser discovery,
/// async preloading on app startup, tag/country filtering, and automatic
/// stream link validation for saved stations.
class RadioController extends ChangeNotifier {
  final RadioBrowserService service;
  final LibraryStore store;

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

  bool _isLoading = false;
  bool _isPreloaded = false;
  bool _isRefreshing = false;
  String? _errorMessage;

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------
  List<RadioStation> get discoverStations => _discoverStations;
  List<String> get popularTags => _popularTags;
  List<String> get popularCountries => _popularCountries;

  String get selectedTag => _selectedTag;
  String get selectedCountry => _selectedCountry;
  String get searchQuery => _searchQuery;

  bool get isLoading => _isLoading;
  bool get isPreloaded => _isPreloaded;
  bool get isRefreshing => _isRefreshing;
  String? get errorMessage => _errorMessage;

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
        service.getPopularTags(limit: 30),
        service.getPopularCountries(limit: 30),
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

  /// Live search by station name or keywords.
  Future<void> search(String query) async {
    _searchQuery = query;
    await _executeSearch();
  }

  /// Selects a genre/tag filter.
  Future<void> setTag(String tag) async {
    if (_selectedTag == tag) return;
    _selectedTag = tag;
    await _executeSearch();
  }

  /// Selects a country filter.
  Future<void> setCountry(String country) async {
    if (_selectedCountry == country) return;
    _selectedCountry = country;
    await _executeSearch();
  }

  /// Clears active search keywords and filters back to global top stations.
  Future<void> clearFilters() async {
    _searchQuery = '';
    _selectedTag = 'All';
    _selectedCountry = 'All';
    _isLoading = true;
    notifyListeners();

    try {
      _discoverStations = await service.getTopStations(limit: 60);
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Saves a remote station into the local library catalog.
  Future<RadioStation?> saveToLibrary(RadioStation station) async {
    final saved = await store.saveRadioStationInStore(station);
    notifyListeners();
    return saved;
  }

  // ---------------------------------------------------------------------------
  // Internal Helpers
  // ---------------------------------------------------------------------------

  Future<void> _executeSearch() async {
    _isLoading = true;
    notifyListeners();

    try {
      final isFilterEmpty = _searchQuery.trim().isEmpty &&
          (_selectedTag == 'All' || _selectedTag.isEmpty) &&
          (_selectedCountry == 'All' || _selectedCountry.isEmpty);

      if (isFilterEmpty) {
        _discoverStations = await service.getTopStations(limit: 60);
      } else {
        _discoverStations = await service.searchStations(
          name: _searchQuery.trim().isNotEmpty ? _searchQuery : null,
          tag: _selectedTag != 'All' ? _selectedTag : null,
          country: _selectedCountry != 'All' ? _selectedCountry : null,
          limit: 60,
        );
      }
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
      debugPrint('[RadioController] _executeSearch error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
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
