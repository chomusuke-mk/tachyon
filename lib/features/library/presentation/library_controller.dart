import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:tachyon/core/backend/backend.dart';
import 'package:tachyon/core/constants/app_defaults.dart';
import 'package:tachyon/features/library/domain/album.dart';
import 'package:tachyon/features/library/domain/artist.dart';
import 'package:tachyon/features/library/domain/genre.dart';
import 'package:tachyon/features/library/domain/scan_progress.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/library/domain/track_sort_option.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';

export 'package:tachyon/features/library/domain/track_sort_option.dart';

class LibraryController extends ChangeNotifier {
  final TachyonBackendClient _backend;
  final SettingsRepository _settingsRepository;

  LibraryController({
    required this._backend,
    required this._settingsRepository,
  }){
    _sortOption = _settingsRepository.getTrackSortOption();
    _sortAscending = _settingsRepository.getTrackSortAscending();
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
  ScanProgress _scanProgress = const ScanProgress();
  StreamSubscription<ScanProgress>? _scanSubscription;

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------
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

  ScanProgress get scanProgress => _scanProgress;
  bool get isScanning => _scanProgress.isRunning;

  // ---------------------------------------------------------------------------
  // Library Loading & Sorting
  // ---------------------------------------------------------------------------
  Future<void> loadLibrary() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _backend.getTracks(sort: _sortOption, ascending: _sortAscending),
        _backend.getAlbums(),
        _backend.getArtists(),
        _backend.getGenres(),
      ]);

      _tracks = results[0] as List<Track>;
      _albums = results[1] as List<Album>;
      _artists = results[2] as List<Artist>;
      _genres = results[3] as List<Genre>;

      _applyFilters();
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

    _isLoading = true;
    notifyListeners();

    try {
      _tracks = await _backend.getTracks(
        sort: _sortOption,
        ascending: _sortAscending,
      );
      _applyFilters();
    } catch (e) {
      _errorMessage = 'Failed to sort tracks: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
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

    Iterable<Track> result = _tracks;

    if (_selectedAlbum != null) {
      result = result.where(
        (t) =>
            t.albumId == _selectedAlbum!.id || t.album == _selectedAlbum!.name,
      );
    }

    if (_selectedArtist != null) {
      result = result.where(
        (t) =>
            t.artistId == _selectedArtist!.id ||
            t.artist == _selectedArtist!.name,
      );
    }

    if (_selectedGenre != null) {
      final targetGenre = _selectedGenre!.name.toLowerCase();
      result = result.where(
        (t) => t.genres.any((g) => g.toLowerCase() == targetGenre),
      );
    }

    _filteredTracks = result.toList();
  }

  // ---------------------------------------------------------------------------
  // Folder Explorer & Breadcrumbs
  // ---------------------------------------------------------------------------
  Future<void> navigateToFolder(String folderPath) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) return;

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

      // Cross-reference with indexed tracks
      _currentFolderTracks = _tracks
          .where((t) => currentDirPaths.contains(t.filePath))
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
    if (directories.isEmpty) return;

    cancelScan();

    _scanProgress = const ScanProgress(phase: ScanPhase.discovering);
    notifyListeners();

    _scanSubscription = _backend.scanProgressStream.listen(
      (progress) {
        _scanProgress = progress;
        notifyListeners();

        if (progress.phase == ScanPhase.completed) {
          loadLibrary();
        }
      },
      onError: (Object err) {
        _scanProgress = _scanProgress.copyWith(
          phase: ScanPhase.failed,
          errorMessage: err.toString(),
        );
        notifyListeners();
      },
      onDone: () {
        _scanSubscription = null;
      },
    );

    await _backend.startScanDirectories(directories);
  }

  void cancelScan() {
    _backend.cancelScan();
    _scanSubscription?.cancel();
    _scanSubscription = null;
    if (_scanProgress.isRunning) {
      _scanProgress = _scanProgress.copyWith(phase: ScanPhase.cancelled);
      notifyListeners();
    }
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

  /// Removes from the database all tracks whose file path starts with [folderPath].
  Future<void> deleteTracksInFolder(String folderPath) async {
    try {
      await _backend.deleteTracksInFolder(folderPath);
      await loadLibrary();
    } catch (e) {
      _errorMessage = 'Failed to delete tracks in folder: $e';
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
    cancelScan();
    super.dispose();
  }
}
