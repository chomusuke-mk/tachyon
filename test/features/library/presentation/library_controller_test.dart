import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/services/metadata_extractor.dart';
import 'package:tachyon/features/library/domain/scan_progress.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';

class FakeMetadataExtractor implements MetadataExtractor {
  StreamController<ScanProgress>? progressController;
  List<String>? scannedDirectories;
  CancellationToken? lastToken;

  @override
  Future<Track?> extractMetadata(String filePath) async {
    return null;
  }

  @override
  Stream<ScanProgress> scanDirectories(
    List<String> directories, {
    CancellationToken? cancellationToken,
  }) {
    scannedDirectories = directories;
    lastToken = cancellationToken;
    progressController = StreamController<ScanProgress>();
    return progressController!.stream;
  }

  @override
  Future<String?> extractCoverArt(String filePath, String cacheDir) async {
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase db;
  late FakeMetadataExtractor fakeExtractor;
  late LibraryController controller;

  const track1 = Track(
    uri: 'file:///music/rock/song_a.flac',
    title: 'Alpha Song',
    artist: 'Artist One',
    album: 'Album One',
    genres: ['Rock'],
    durationMs: 180000,
    fileSize: 10485760,
    modifiedAt: 1600000000,
  );

  const track2 = Track(
    uri: 'file:///music/jazz/song_b.mp3',
    title: 'Beta Song',
    artist: 'Artist Two',
    album: 'Album Two',
    genres: ['Jazz'],
    durationMs: 240000,
    fileSize: 8388608,
    modifiedAt: 1610000000,
  );

  setUp(() async {
    db = AppDatabaseImpl.inMemory();
    await db.init();
    fakeExtractor = FakeMetadataExtractor();
    controller = LibraryController(
      database: db,
      metadataExtractor: fakeExtractor,
    );
  });

  tearDown(() async {
    controller.dispose();
    await db.close();
  });

  group('LibraryController Initial State', () {
    test('initializes with empty collections and default sort', () {
      expect(controller.tracks, isEmpty);
      expect(controller.albums, isEmpty);
      expect(controller.artists, isEmpty);
      expect(controller.genres, isEmpty);
      expect(controller.isLoading, isFalse);
      expect(controller.isScanning, isFalse);
      expect(controller.sortOption, equals(TrackSortOption.title));
      expect(controller.sortAscending, isTrue);
      expect(controller.selectedGenre, isNull);
      expect(controller.selectedArtist, isNull);
      expect(controller.selectedAlbum, isNull);
    });
  });

  group('LibraryController Loading & Sorting', () {
    test('loadLibrary loads tracks, albums, artists, genres from database', () async {
      await db.insertOrUpdateTrack(track1);
      await db.insertOrUpdateTrack(track2);

      await controller.loadLibrary();

      expect(controller.allTracks.length, equals(2));
      expect(controller.tracks.length, equals(2));
      expect(controller.artists.length, equals(2));
      expect(controller.albums.length, equals(2));
      expect(controller.genres.length, equals(2));
    });

    test('setSortOption updates sort option and reloads ordered tracks', () async {
      await db.insertOrUpdateTrack(track1);
      await db.insertOrUpdateTrack(track2);
      await controller.loadLibrary();

      expect(controller.tracks.first.title, equals('Alpha Song'));

      await controller.setSortOption(TrackSortOption.duration);
      expect(controller.sortOption, equals(TrackSortOption.duration));
      expect(controller.tracks.first.title, equals('Alpha Song'));

      await controller.setSortOption(TrackSortOption.duration, ascending: false);
      expect(controller.sortAscending, isFalse);
      expect(controller.tracks.first.title, equals('Beta Song'));
    });
  });

  group('LibraryController Filtering', () {
    setUp(() async {
      await db.insertOrUpdateTrack(track1);
      await db.insertOrUpdateTrack(track2);
      await controller.loadLibrary();
    });

    test('filterByGenre filters tracks matching selected genre', () {
      final rockGenre = controller.genres.firstWhere((g) => g.name == 'Rock');
      controller.filterByGenre(rockGenre);

      expect(controller.selectedGenre?.name, equals('Rock'));
      expect(controller.tracks.length, equals(1));
      expect(controller.tracks.first.title, equals('Alpha Song'));
    });

    test('filterByArtist filters tracks matching selected artist', () {
      final artistTwo = controller.artists.firstWhere((a) => a.name == 'Artist Two');
      controller.filterByArtist(artistTwo);

      expect(controller.selectedArtist?.name, equals('Artist Two'));
      expect(controller.tracks.length, equals(1));
      expect(controller.tracks.first.title, equals('Beta Song'));
    });

    test('filterByAlbum filters tracks matching selected album', () {
      final albumOne = controller.albums.firstWhere((a) => a.name == 'Album One');
      controller.filterByAlbum(albumOne);

      expect(controller.selectedAlbum?.name, equals('Album One'));
      expect(controller.tracks.length, equals(1));
      expect(controller.tracks.first.title, equals('Alpha Song'));
    });

    test('clearFilters resets all filtering state', () {
      final rockGenre = controller.genres.firstWhere((g) => g.name == 'Rock');
      controller.filterByGenre(rockGenre);
      expect(controller.tracks.length, equals(1));

      controller.clearFilters();
      expect(controller.selectedGenre, isNull);
      expect(controller.selectedArtist, isNull);
      expect(controller.selectedAlbum, isNull);
      expect(controller.tracks.length, equals(2));
    });
  });

  group('LibraryController Scanning', () {
    test('startScan sets scanning progress and reloads when finished', () async {
      expect(controller.isScanning, isFalse);

      controller.startScan(['/music']);
      expect(controller.isScanning, isTrue);
      expect(fakeExtractor.scannedDirectories, equals(['/music']));

      // Emit progress
      fakeExtractor.progressController?.add(
        const ScanProgress(
          phase: ScanPhase.extracting,
          scannedFiles: 10,
          totalFiles: 20,
          currentFile: '/music/song.mp3',
        ),
      );
      await pumpEventQueue(times: 20);
      expect(controller.scanProgress.scannedFiles, equals(10));
      expect(controller.isScanning, isTrue);

      // Emit completion
      fakeExtractor.progressController?.add(
        const ScanProgress(
          phase: ScanPhase.completed,
          scannedFiles: 20,
          totalFiles: 20,
        ),
      );
      await pumpEventQueue(times: 20);
      expect(controller.isScanning, isFalse);
    });

    test('cancelScan invokes cancellation token and stops scan', () {
      controller.startScan(['/music']);
      expect(controller.isScanning, isTrue);

      controller.cancelScan();
      expect(fakeExtractor.lastToken?.isCancelled, isTrue);
      expect(controller.isScanning, isFalse);
    });
  });

  group('LibraryController Deletion Operations', () {
    setUp(() async {
      await db.insertOrUpdateTrack(track1);
      await db.insertOrUpdateTrack(track2);
      await controller.loadLibrary();
    });

    test('deleteTrack removes track from database and in-memory list', () async {
      final loadedTrack = controller.allTracks.firstWhere((t) => t.title == 'Alpha Song');
      await controller.deleteTrack(loadedTrack);

      expect(controller.allTracks.length, equals(1));
      expect(controller.allTracks.first.title, equals('Beta Song'));
      final dbTracks = await db.getAllTracks();
      expect(dbTracks.length, equals(1));
    });
  });

  group('LibraryController Folder Navigation', () {
    test('navigateToFolder and navigateUpFolder manage breadcrumbs and path', () async {
      final tempDir = Directory.systemTemp.createTempSync('tachyon_test_folder_');
      final subDir = Directory('${tempDir.path}/sub')..createSync();
      try {
        await controller.navigateToFolder(subDir.path);
        expect(controller.currentFolderPath, equals(subDir.path));
        expect(controller.folderBreadcrumbs.isNotEmpty, isTrue);

        await controller.navigateUpFolder();
        expect(controller.currentFolderPath, equals(tempDir.path));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}
