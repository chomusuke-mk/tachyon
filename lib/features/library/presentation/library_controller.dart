import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:tachyon/core/backend/backend.dart';
import 'package:tachyon/core/constants/app_defaults.dart';
import 'package:tachyon/features/library/data/library_store.dart';
import 'package:tachyon/features/library/domain/album.dart';
import 'package:tachyon/features/library/domain/artist.dart';
import 'package:tachyon/features/library/domain/genre.dart';
import 'package:tachyon/features/library/domain/scan_progress.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/library/domain/track_sort_option.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';

export 'package:tachyon/features/library/domain/track_sort_option.dart';

class LibraryController extends ChangeNotifier {
  final TachyonBackendClient backend;
  final SettingsRepository settingsRepository;
  TachyonBackendClient get _backend => backend;
  SettingsRepository get _settingsRepository => settingsRepository;

  LibraryStore _store;
  StreamSubscription<void>? _catalogSubscription;

  LibraryController({
    required this.backend,
    required this.settingsRepository,
    LibraryStore? store,
  })  : _store = store ?? LibraryStore(),
        _isLoading = store == null {
    _sortOption = _settingsRepository.getTrackSortOption();
    _sortAscending = _settingsRepository.getTrackSortAscending();

    _catalogSubscription = _backend.catalogUpdatedStream.listen((_) {
      loadLibrary();
    });

    _scanSubscription = _backend.scanProgressStream.listen((progress) {
      final wasRunning = _scanProgressNotifier.value.isRunning;
      _scanProgressNotifier.value = progress;

      if (wasRunning != progress.isRunning) {
        notifyListeners();
      }

      if (progress.stage == ScanStage.completed) {
        loadLibrary();
      }
    });

    if (store != null) {
      _syncFromStore();
    }
  }

  // ---------------------------------------------------------------------------
  // State Fields
  // ---------------------------------------------------------------------------
  bool _isDisposed = false;
  List<Track> _tracks = [];
  List<Album> _albums = [];
  List<Artist> _artists = [];
  List<Genre> _genres = [];

  bool _isLoading = false;
  String? _errorMessage;

  TrackSortOption _sortOption = TrackSortOption.title;
  bool _sortAscending = true;

  Genre? _selectedGenre;
  Artist? _selectedArtist;
  Album? _selectedAlbum;
  List<Track> _filteredTracks = [];

  // Folder Explorer State
  String? _currentFolderPath;
  List<String> _currentFolderSubdirectories = [];
  List<Track> _currentFolderTracks = [];
  List<String> _folderBreadcrumbs = [];

  // Scanning State
  final ValueNotifier<ScanProgress> _scanProgressNotifier =
      ValueNotifier<ScanProgress>(const ScanProgress());
  StreamSubscription<ScanProgress>? _scanSubscription;

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------
  LibraryStore get store => _store;

  List<Track> get tracks =>
      (_selectedGenre != null ||
          _selectedArtist != null ||
          _selectedAlbum != null)
      ? _filteredTracks
      : _tracks;

  List<Track> get allTracks => List.unmodifiable(_tracks);
  List<Album> get albums => List.unmodifiable(_albums);
  List<Artist> get artists => List.unmodifiable(_artists);
  List<Genre> get genres => List.unmodifiable(_genres);

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  TrackSortOption get sortOption => _sortOption;
  bool get sortAscending => _sortAscending;

  Genre? get selectedGenre => _selectedGenre;
  Artist? get selectedArtist => _selectedArtist;
  Album? get selectedAlbum => _selectedAlbum;

  String? get currentFolderPath => _currentFolderPath;
  List<String> get currentFolderSubdirectories =>
      List.unmodifiable(_currentFolderSubdirectories);
  List<Track> get currentFolderTracks =>
      List.unmodifiable(_currentFolderTracks);
  List<String> get folderBreadcrumbs => List.unmodifiable(_folderBreadcrumbs);

  ValueListenable<ScanProgress> get scanProgressListenable => _scanProgressNotifier;
  ScanProgress get scanProgress => _scanProgressNotifier.value;
  bool get isScanning => _scanProgressNotifier.value.isRunning;

  // ---------------------------------------------------------------------------
  // Library Loading & Sorting
  // ---------------------------------------------------------------------------
  Future<void> loadLibrary({bool autoScan = false}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final snapshot = await _backend.getCatalogSnapshot();
      _store = LibraryStore.fromSnapshot(snapshot);
      _syncFromStore();

      if (_currentFolderPath != null) {
        await navigateToFolder(_currentFolderPath!);
      }
    } catch (e, st) {
      _errorMessage = 'Failed to load library: $e';
      debugPrint('$_errorMessage\n$st');
    } finally {
      _isLoading = false;
      notifyListeners();
    }

    if (autoScan) {
      final musicDirs = _settingsRepository.getSettings().musicDirectories;
      if (musicDirs.isNotEmpty) {
        unawaited(startScan(musicDirs));
      }
    }
  }

  void _syncFromStore() {
    _tracks = _store.sortTracks(
      _store.allTracks,
      _sortOption,
      ascending: _sortAscending,
    );
    _albums = _store.allAlbums;
    _artists = _store.allArtists;
    _genres = _store.allGenres;

    if (_selectedAlbum != null && _selectedAlbum!.id != null) {
      _selectedAlbum = _store.getAlbumById(_selectedAlbum!.id!);
    }
    if (_selectedArtist != null && _selectedArtist!.id != null) {
      _selectedArtist = _store.getArtistById(_selectedArtist!.id!);
    }
    if (_selectedGenre != null && _selectedGenre!.id != null) {
      _selectedGenre = _store.getGenreById(_selectedGenre!.id!);
    }

    _applyFilters();
  }

  Future<void> setSortOption(TrackSortOption option, {bool? ascending}) async {
    if (_sortOption == option && ascending == null) {
      _sortAscending = !_sortAscending;
    } else {
      _sortOption = option;
      if (ascending != null) {
        _sortAscending = ascending;
      }
    }

    _settingsRepository.setTrackSortOption(_sortOption);
    _settingsRepository.setTrackSortAscending(_sortAscending);

    _tracks = _store.sortTracks(
      _store.allTracks,
      _sortOption,
      ascending: _sortAscending,
    );
    _applyFilters();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Filter Management
  // ---------------------------------------------------------------------------
  void filterByGenre(Genre? genre) {
    _selectedGenre = genre;
    _applyFilters();
    notifyListeners();
  }

  void filterByArtist(Artist? artist) {
    _selectedArtist = artist;
    _applyFilters();
    notifyListeners();
  }

  void filterByAlbum(Album? album) {
    _selectedAlbum = album;
    _applyFilters();
    notifyListeners();
  }

  void clearFilters() {
    _selectedGenre = null;
    _selectedArtist = null;
    _selectedAlbum = null;
    _filteredTracks.clear();
    notifyListeners();
  }

  void _applyFilters() {
    if (_selectedAlbum == null &&
        _selectedArtist == null &&
        _selectedGenre == null) {
      _filteredTracks.clear();
      return;
    }

    _filteredTracks = _store.sortTracks(
      _store.filterTracks(
        album: _selectedAlbum,
        artist: _selectedArtist,
        genre: _selectedGenre,
      ),
      _sortOption,
      ascending: _sortAscending,
    );
  }

  // ---------------------------------------------------------------------------
  // In-Memory Search
  // ---------------------------------------------------------------------------
  List<Track> searchTracks(String query) => _store.searchTracks(query);
  List<Album> searchAlbums(String query) => _store.searchAlbums(query);
  List<Artist> searchArtists(String query) => _store.searchArtists(query);

  // ---------------------------------------------------------------------------
  // Folder Explorer & Breadcrumbs
  // ---------------------------------------------------------------------------
  Future<void> navigateToFolder(String folderPath) async {
    final dir = Directory(folderPath);
    if (!dir.existsSync()) return;

    _currentFolderPath = folderPath;
    _folderBreadcrumbs = p.split(folderPath);

    try {
      final entities = dir.listSync(followLinks: false);
      final subDirs = <String>[];
      final currentDirPaths = <String>{};

      for (final entity in entities) {
        if (entity is Directory) {
          final base = p.basename(entity.path);
          if (!base.startsWith('.')) {
            subDirs.add(entity.path);
          }
        } else if (entity is File) {
          final ext = p
              .extension(entity.path)
              .toLowerCase()
              .replaceAll('.', '');
          if (AppDefaults.supportedAudioExtensions.contains(ext)) {
            currentDirPaths.add(entity.path);
          }
        }
      }

      subDirs.sort(
        (a, b) =>
            p.basename(a).toLowerCase().compareTo(p.basename(b).toLowerCase()),
      );
      _currentFolderSubdirectories = subDirs;

      // Cross-reference with indexed tracks from store in O(1)
      _currentFolderTracks = currentDirPaths
          .map((path) => _store.getTrackByPath(path))
          .whereType<Track>()
          .toList();
    } catch (e) {
      debugPrint('Error navigating folder $folderPath: $e');
    }

    notifyListeners();
  }

  Future<void> navigateUpFolder() async {
    if (_currentFolderPath == null) return;
    final parent = p.dirname(_currentFolderPath!);
    if (parent == _currentFolderPath) return;
    await navigateToFolder(parent);
  }

  // ---------------------------------------------------------------------------
  // Scanning Operations
  // ---------------------------------------------------------------------------
  Future<void> startScan(List<String> directories) async {
    _scanProgressNotifier.value =
        const ScanProgress(stage: ScanStage.gettingDatabase);
    notifyListeners();
    await _backend.startScanDirectories(directories);
  }

  void cancelScan() {
    _scanProgressNotifier.value =
        _scanProgressNotifier.value.copyWith(stage: ScanStage.cancelled);
    notifyListeners();
    _backend.cancelScan();
  }

  Future<void> deleteTrack(Track track) async {
    if (track.id == null) return;
    try {
      await _backend.deleteTrack(track.id!);
      await loadLibrary();
    } catch (e) {
      _errorMessage = 'Failed to delete track: $e';
      notifyListeners();
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
    _scanSubscription?.cancel();
    _scanSubscription = null;
    _scanProgressNotifier.dispose();
    super.dispose();
  }
}
