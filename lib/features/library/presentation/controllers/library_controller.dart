import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:tachyon/core/metadata/domain/scan_progress.dart';
import 'package:tachyon/core/metadata/metadata_service.dart';
import 'package:tachyon/core/storage/persistent_binary_storage.dart';
import 'package:tachyon/core/store/domain/album.dart';
import 'package:tachyon/core/store/domain/album_sort_option.dart';
import 'package:tachyon/core/store/domain/artist.dart';
import 'package:tachyon/core/store/domain/artist_sort_option.dart';
import 'package:tachyon/core/store/domain/genre.dart';
import 'package:tachyon/core/store/domain/track.dart';
import 'package:tachyon/core/store/domain/track_sort_option.dart';
import 'package:tachyon/core/store/library_store.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/core/lifecycle/memory_optimizer.dart';

export 'package:tachyon/core/store/domain/album_sort_option.dart';
export 'package:tachyon/core/store/domain/artist_sort_option.dart';
export 'package:tachyon/core/store/domain/track_sort_option.dart';

/// State controller for the music library, sorting, filters, folder browsing,
/// and directory scanning.
class LibraryController extends ChangeNotifier {
  /// Repository for persisting library sorting, folder view, and source settings.
  final SettingsRepository settingsRepository;

  /// Optional service used to scan directories and report scan progress.
  final MetadataService? metadataService;

  final LibraryStore _store;

  /// Creates a [LibraryController] initialized with persisted preferences.
  ///
  /// Uses [store] if provided, otherwise creates a new [LibraryStore]. When
  /// [metadataService] is supplied, subscribes to its scan progress stream.
  LibraryController({
    required this.settingsRepository,
    LibraryStore? store,
    this.metadataService,
  }) : _store = store ?? LibraryStore(),
       _isLoading = store == null {
    _sortOption = settingsRepository.getTrackSortOption();
    _sortAscending = settingsRepository.getTrackSortAscending();
    _albumSortOption = settingsRepository.getAlbumSortOption();
    _albumSortAscending = settingsRepository.getAlbumSortAscending();
    _artistSortOption = settingsRepository.getArtistSortOption();
    _artistSortAscending = settingsRepository.getArtistSortAscending();
    _isFolderGridView = settingsRepository.getCardView('folders', defaultValue: false);

    _store.addListener(_onStoreChanged);

    _scanSubscription = metadataService?.progressStream.listen((progress) {
      final wasRunning = _scanProgressNotifier.value.isRunning;
      _scanProgressNotifier.value = progress;

      if (wasRunning != progress.isRunning) {
        notifyListeners();
      }

      if (progress.stage == ScanStage.completed) {
        _syncFromStore();
        notifyListeners();
        MemoryOptimizer.trim();
      }
    });

    if (store != null) {
      _syncFromStore();
    }
  }

  void _onStoreChanged() {
    if (_isDisposed) return;
    if (identical(_store.tracks, _lastStoreTracksRef) &&
        identical(_store.albums, _lastStoreAlbumsRef) &&
        identical(_store.artists, _lastStoreArtistsRef) &&
        identical(_store.genres, _lastStoreGenresRef)) {
      return;
    }
    _syncFromStore();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // State Fields
  // ---------------------------------------------------------------------------
  bool _isDisposed = false;
  Future<void>? _inFlightLoad;
  List<Track>? _lastStoreTracksRef;
  List<Album>? _lastStoreAlbumsRef;
  List<Artist>? _lastStoreArtistsRef;
  List<Genre>? _lastStoreGenresRef;
  List<Track> _tracks = const [];
  List<Album> _albums = const [];
  List<Artist> _artists = const [];
  List<Genre> _genres = const [];

  bool _isLoading = false;
  String? _errorMessage;

  TrackSortOption _sortOption = TrackSortOption.title;
  bool _sortAscending = true;
  AlbumSortOption _albumSortOption = AlbumSortOption.title;
  bool _albumSortAscending = true;
  ArtistSortOption _artistSortOption = ArtistSortOption.name;
  bool _artistSortAscending = true;

  Genre? _selectedGenre;
  Artist? _selectedArtist;
  Album? _selectedAlbum;
  List<Track> _filteredTracks = [];

  // Folder Navigation State
  final List<String> _folderNavigationStack = [];
  List<String> _currentFolderSubdirectories = [];
  List<Track> _currentFolderTracks = [];
  bool _isFolderLoading = false;
  bool _isFolderGridView = false;

  // Scanning State
  final ValueNotifier<ScanProgress> _scanProgressNotifier =
      ValueNotifier<ScanProgress>(const ScanProgress());
  StreamSubscription<ScanProgress>? _scanSubscription;

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------

  /// Underlying in-memory [LibraryStore] holding tracks, albums, artists, and genres.
  LibraryStore get store => _store;

  /// Tracks matching the active filters, or all sorted library tracks when no
  /// filter is set.
  List<Track> get tracks =>
      (_selectedGenre != null ||
          _selectedArtist != null ||
          _selectedAlbum != null)
      ? _filteredTracks
      : _tracks;

  /// Unmodifiable list of library albums sorted by [albumSortOption].
  List<Album> get albums => _albums;

  /// Unmodifiable list of library artists sorted by [artistSortOption].
  List<Artist> get artists => _artists;

  /// List of genres present in the library.
  List<Genre> get genres => _genres;

  /// Whether the library is currently loading from the database.
  bool get isLoading => _isLoading;

  /// Error message from the most recent failed library operation, if any.
  String? get errorMessage => _errorMessage;

  /// Active field used to sort [tracks].
  TrackSortOption get trackSortOption => _sortOption;

  /// Whether [tracks] are sorted in ascending order.
  bool get trackSortAscending => _sortAscending;

  /// Active field used to sort [albums].
  AlbumSortOption get albumSortOption => _albumSortOption;

  /// Whether [albums] are sorted in ascending order.
  bool get albumSortAscending => _albumSortAscending;

  /// Active field used to sort [artists].
  ArtistSortOption get artistSortOption => _artistSortOption;

  /// Whether [artists] are sorted in ascending order.
  bool get artistSortAscending => _artistSortAscending;

  /// Currently selected genre filter, or `null` when unfiltered.
  Genre? get selectedGenre => _selectedGenre;

  /// Currently selected artist filter, or `null` when unfiltered.
  Artist? get selectedArtist => _selectedArtist;

  /// Currently selected album filter, or `null` when unfiltered.
  Album? get selectedAlbum => _selectedAlbum;

  /// Path of the currently open directory in the folder explorer, or `null` at root.
  String? get currentFolderPath => _folderNavigationStack.lastOrNull;

  /// Unmodifiable list of subdirectories inside [currentFolderPath].
  List<String> get currentFolderSubdirectories =>
      List.unmodifiable(_currentFolderSubdirectories);

  /// Unmodifiable list of tracks directly inside [currentFolderPath].
  List<Track> get currentFolderTracks =>
      List.unmodifiable(_currentFolderTracks);

  /// Unmodifiable navigation stack of directory paths leading to [currentFolderPath].
  List<String> get folderBreadcrumbs =>
      List.unmodifiable(_folderNavigationStack);

  /// Whether the contents of [currentFolderPath] are currently loading.
  bool get isFolderLoading => _isFolderLoading;

  /// Whether the folder explorer displays items in a grid instead of a list.
  bool get isFolderGridView => _isFolderGridView;

  /// Whether the folder explorer is currently at the root level.
  bool get isAtFolderRoot => _folderNavigationStack.isEmpty;

  /// Listenable emitting live [ScanProgress] updates during directory scans.
  ValueListenable<ScanProgress> get scanProgressListenable =>
      _scanProgressNotifier;

  /// Most recent [ScanProgress] snapshot.
  ScanProgress get scanProgress => _scanProgressNotifier.value;

  /// Whether a library directory scan is currently running.
  bool get isScanning => _scanProgressNotifier.value.isRunning;

  // ---------------------------------------------------------------------------
  // Library Loading & Sorting
  // ---------------------------------------------------------------------------

  /// Loads library data from the database and syncs sorted collections.
  ///
  /// Deduplicates concurrent calls. If [autoScan] is `true`, starts
  /// [scanDirectories] after loading completes.
  Future<void> loadLibrary({bool autoScan = false}) async {
    if (_inFlightLoad != null) {
      await _inFlightLoad;
      if (autoScan) {
        unawaited(scanDirectories());
      }
      return;
    }

    final future = _performLoadLibrary();
    _inFlightLoad = future;
    try {
      await future;
    } finally {
      if (identical(_inFlightLoad, future)) {
        _inFlightLoad = null;
      }
    }

    if (autoScan) {
      unawaited(scanDirectories());
    }
  }

  Future<void> _performLoadLibrary() async {
    final wasEmpty = _tracks.isEmpty;
    _isLoading = true;
    _errorMessage = null;
    if (wasEmpty) {
      notifyListeners();
    }

    try {
      await _store.reloadFromDatabase();
      _syncFromStore();
      MemoryOptimizer.trim();

      if (_folderNavigationStack.isNotEmpty) {
        await _loadCurrentFolderContent();
      }
    } catch (e, st) {
      _errorMessage = 'Failed to load library: $e';
      debugPrint('$_errorMessage\n$st');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _syncFromStore() {
    _lastStoreTracksRef = _store.tracks;
    _lastStoreAlbumsRef = _store.albums;
    _lastStoreArtistsRef = _store.artists;
    _lastStoreGenresRef = _store.genres;
    _tracks = List<Track>.unmodifiable(
      _store.sortTracks(
        _lastStoreTracksRef!,
        _sortOption,
        ascending: _sortAscending,
      ),
    );
    _albums = List<Album>.unmodifiable(
      _store.sortAlbums(
        _lastStoreAlbumsRef!,
        _albumSortOption,
        ascending: _albumSortAscending,
      ),
    );
    _artists = List<Artist>.unmodifiable(
      _store.sortArtists(
        _lastStoreArtistsRef!,
        _artistSortOption,
        ascending: _artistSortAscending,
      ),
    );
    _genres = _lastStoreGenresRef!;

    if (_selectedAlbum != null && _selectedAlbum!.id != null) {
      _selectedAlbum = _store.getAlbumById(_selectedAlbum!.id!);
    }
    if (_selectedArtist != null && _selectedArtist!.id != null) {
      _selectedArtist = _store.getArtistById(_selectedArtist!.id!);
    }
    if (_selectedGenre != null && _selectedGenre!.id != null) {
      _selectedGenre = _store.getGenreById(_selectedGenre!.id!);
    }

    if (_folderNavigationStack.isNotEmpty) {
      final currentFolder = _folderNavigationStack.last;
      final refreshed = List<Track>.from(_store.getTracksInDirectory(currentFolder));
      refreshed.sort((a, b) {
        final discComp = (a.discNumber ?? 1).compareTo(b.discNumber ?? 1);
        if (discComp != 0) return discComp;
        final trackComp = (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0);
        if (trackComp != 0) return trackComp;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
      _currentFolderTracks = refreshed;
    }

    _applyFilters();
  }

  /// Updates the track sort [option] and optional [ascending] direction.
  ///
  /// When [ascending] is omitted and [option] matches [trackSortOption],
  /// toggles the current sort direction. Persists the choice in [settingsRepository].
  Future<void> setTrackSortOption(TrackSortOption option, {bool? ascending}) async {
    if (_sortOption == option && ascending == null) {
      _sortAscending = !_sortAscending;
    } else {
      _sortOption = option;
      if (ascending != null) {
        _sortAscending = ascending;
      }
    }

    settingsRepository.setTrackSortOption(_sortOption);
    settingsRepository.setTrackSortAscending(_sortAscending);

    _tracks = List<Track>.unmodifiable(
      _store.sortTracks(
        _store.tracks,
        _sortOption,
        ascending: _sortAscending,
      ),
    );
    _applyFilters();
    notifyListeners();
  }

  /// Updates the album sort [option] and optional [ascending] direction.
  ///
  /// When [ascending] is omitted and [option] matches [albumSortOption],
  /// toggles the current sort direction. Persists the choice in [settingsRepository].
  Future<void> setAlbumSortOption(
    AlbumSortOption option, {
    bool? ascending,
  }) async {
    if (_albumSortOption == option && ascending == null) {
      _albumSortAscending = !_albumSortAscending;
    } else {
      _albumSortOption = option;
      if (ascending != null) {
        _albumSortAscending = ascending;
      }
    }

    settingsRepository.setAlbumSortOption(_albumSortOption);
    settingsRepository.setAlbumSortAscending(_albumSortAscending);

    _albums = List<Album>.unmodifiable(
      _store.sortAlbums(
        _store.albums,
        _albumSortOption,
        ascending: _albumSortAscending,
      ),
    );
    notifyListeners();
  }

  /// Updates the artist sort [option] and optional [ascending] direction.
  ///
  /// When [ascending] is omitted and [option] matches [artistSortOption],
  /// toggles the current sort direction. Persists the choice in [settingsRepository].
  Future<void> setArtistSortOption(
    ArtistSortOption option, {
    bool? ascending,
  }) async {
    if (_artistSortOption == option && ascending == null) {
      _artistSortAscending = !_artistSortAscending;
    } else {
      _artistSortOption = option;
      if (ascending != null) {
        _artistSortAscending = ascending;
      }
    }

    settingsRepository.setArtistSortOption(_artistSortOption);
    settingsRepository.setArtistSortAscending(_artistSortAscending);

    _artists = List<Artist>.unmodifiable(
      _store.sortArtists(
        _store.artists,
        _artistSortOption,
        ascending: _artistSortAscending,
      ),
    );
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Filter Management
  // ---------------------------------------------------------------------------

  /// Filters [tracks] by [genre], or clears the genre filter when `null`.
  void filterByGenre(Genre? genre) {
    _selectedGenre = genre;
    _applyFilters();
    notifyListeners();
  }

  /// Filters [tracks] by [artist], or clears the artist filter when `null`.
  void filterByArtist(Artist? artist) {
    _selectedArtist = artist;
    _applyFilters();
    notifyListeners();
  }

  /// Filters [tracks] by [album], or clears the album filter when `null`.
  void filterByAlbum(Album? album) {
    _selectedAlbum = album;
    _applyFilters();
    notifyListeners();
  }

  /// Clears all active genre, artist, and album filters.
  void clearFilters() {
    _selectedGenre = null;
    _selectedArtist = null;
    _selectedAlbum = null;
    _filteredTracks = const [];
    notifyListeners();
  }

  void _applyFilters() {
    if (_selectedAlbum == null &&
        _selectedArtist == null &&
        _selectedGenre == null) {
      _filteredTracks = const [];
      return;
    }

    _filteredTracks = List<Track>.unmodifiable(
      _store.sortTracks(
        _store.filterTracks(
          album: _selectedAlbum,
          artist: _selectedArtist,
          genre: _selectedGenre,
        ),
        _sortOption,
        ascending: _sortAscending,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Folder Explorer & Navigation Stack
  // ---------------------------------------------------------------------------

  /// Toggles [isFolderGridView] and persists the preference in [settingsRepository].
  void toggleFolderGridView() {
    _isFolderGridView = !_isFolderGridView;
    settingsRepository.setCardView('folders', _isFolderGridView);
    notifyListeners();
  }

  /// Navigates the folder explorer to [folderPath] and loads its contents.
  ///
  /// Does nothing if [folderPath] does not exist. Reuses existing breadcrumb
  /// ancestors when navigating back into an ancestor directory.
  Future<void> navigateToFolder(String folderPath) async {
    final normalized = p.normalize(folderPath);
    if (!PersistentBinaryStorage.directoryExistsSync(normalized)) return;

    final existingIndex = _folderNavigationStack.indexOf(normalized);
    if (existingIndex != -1) {
      _folderNavigationStack.removeRange(
        existingIndex + 1,
        _folderNavigationStack.length,
      );
    } else {
      if (_folderNavigationStack.isEmpty) {
        final musicDirs = settingsRepository.getSettings().musicDirectories;
        String? matchingRoot;
        for (final root in musicDirs) {
          final normRoot = p.normalize(root);
          if (normalized == normRoot || p.isWithin(normRoot, normalized)) {
            matchingRoot = normRoot;
            break;
          }
        }

        if (matchingRoot != null) {
          if (matchingRoot != normalized) {
            final rel = p.relative(normalized, from: matchingRoot);
            final parts = p.split(rel);
            var currentAcc = matchingRoot;
            _folderNavigationStack.add(currentAcc);
            for (final part in parts) {
              currentAcc = p.normalize(p.join(currentAcc, part));
              _folderNavigationStack.add(currentAcc);
            }
          } else {
            _folderNavigationStack.add(matchingRoot);
          }
        } else {
          final parent = p.dirname(normalized);
          if (parent != normalized &&
              PersistentBinaryStorage.directoryExistsSync(parent)) {
            _folderNavigationStack.add(parent);
          }
          _folderNavigationStack.add(normalized);
        }
      } else {
        _folderNavigationStack.add(normalized);
      }
    }

    await _loadCurrentFolderContent();
  }

  /// Navigates one level up in the folder stack, returning to root if empty.
  Future<void> navigateUpFolder() async {
    if (_folderNavigationStack.isEmpty) return;

    _folderNavigationStack.removeLast();
    if (_folderNavigationStack.isEmpty) {
      _currentFolderSubdirectories = [];
      _currentFolderTracks = [];
      _isFolderLoading = false;
      notifyListeners();
      return;
    }

    await _loadCurrentFolderContent();
  }

  /// Navigates directly to the directory at [index] in [folderBreadcrumbs].
  ///
  /// Resets to root if [index] is out of bounds.
  Future<void> navigateToBreadcrumbIndex(int index) async {
    if (index < 0 || index >= _folderNavigationStack.length) {
      await resetFolderNavigation();
      return;
    }
    if (index == _folderNavigationStack.length - 1) return;

    _folderNavigationStack.removeRange(
      index + 1,
      _folderNavigationStack.length,
    );
    await _loadCurrentFolderContent();
  }

  /// Clears the folder navigation stack and returns to the root folder view.
  Future<void> resetFolderNavigation() async {
    _folderNavigationStack.clear();
    _currentFolderSubdirectories = [];
    _currentFolderTracks = [];
    _isFolderLoading = false;
    notifyListeners();
  }

  Future<void> _loadCurrentFolderContent() async {
    final current = _folderNavigationStack.lastOrNull;
    if (current == null) {
      _isFolderLoading = false;
      notifyListeners();
      return;
    }

    if (!PersistentBinaryStorage.directoryExistsSync(current)) {
      _folderNavigationStack.removeLast();
      if (_folderNavigationStack.isEmpty) {
        _currentFolderSubdirectories = [];
        _currentFolderTracks = [];
        _isFolderLoading = false;
        notifyListeners();
      } else {
        await _loadCurrentFolderContent();
      }
      return;
    }

    // Boundary check: ensure folder is within configured musicDirectories
    final musicDirs = settingsRepository.getSettings().musicDirectories;
    final root = _folderNavigationStack.firstOrNull;
    if (root != null && musicDirs.isNotEmpty) {
      final normRoot = p.normalize(root);
      final isAllowed = musicDirs.any((d) {
        final nd = p.normalize(d);
        return normRoot == nd || p.isWithin(nd, normRoot);
      });
      if (!isAllowed) {
        await resetFolderNavigation();
        return;
      }
    }

    // 1. Immediate: show breadcrumb and trigger loader
    _isFolderLoading = true;
    _currentFolderSubdirectories = [];
    _currentFolderTracks = [];
    notifyListeners();

    // 2. Subdirectories listing
    final subDirs = PersistentBinaryStorage.listSubdirectoriesSync(current);

    // 3. Resolve tracks from in-memory _store in O(1)
    final tracks = List<Track>.from(_store.getTracksInDirectory(current));
    tracks.sort((a, b) {
      final discComp = (a.discNumber ?? 1).compareTo(b.discNumber ?? 1);
      if (discComp != 0) return discComp;
      final trackComp = (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0);
      if (trackComp != 0) return trackComp;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    _currentFolderSubdirectories = subDirs;
    _currentFolderTracks = tracks;
    _isFolderLoading = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Scanning Operations
  // ---------------------------------------------------------------------------

  /// Scans the user's configured music directories and individual music
  /// files or links from [SettingsRepository].
  ///
  /// When all sources have been removed, scans with empty lists to purge
  /// removed tracks.
  Future<void> scanDirectories() async {
    if (isScanning) return;
    final currentSettings = settingsRepository.getSettings();
    final directories = currentSettings.musicDirectories;
    final files = currentSettings.musicFiles;
    _scanProgressNotifier.value = const ScanProgress(
      stage: ScanStage.gettingDatabase,
    );
    notifyListeners();
    if (metadataService != null) {
      await metadataService!
          .scanDirectories(directories, files: files)
          .drain<void>();
    }
  }

  /// Requests cancellation of the active directory scan, if any.
  void cancelScan() {
    _scanProgressNotifier.value = _scanProgressNotifier.value.copyWith(
      stage: ScanStage.cancelled,
    );
    notifyListeners();
    metadataService?.cancelScan();
  }

  /// Deletes [track] from the store and refreshes the library and folder view.
  Future<void> deleteTrack(Track track) async {
    if (track.id == null) return;
    try {
      await _store.deleteTrackInStore(track.id!);
      _syncFromStore();
      if (_folderNavigationStack.isNotEmpty) {
        await _loadCurrentFolderContent();
      }
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to delete track: $e';
      notifyListeners();
    }
  }

  /// Clears all tracks, albums, artists, and genres from the library.
  Future<void> clearLibrary() async {
    try {
      await _store.clearAllDataInStore();
      _syncFromStore();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to clear library: $e';
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
    _store.removeListener(_onStoreChanged);
    _scanSubscription?.cancel();
    _scanSubscription = null;
    _scanProgressNotifier.dispose();
    super.dispose();
  }
}
