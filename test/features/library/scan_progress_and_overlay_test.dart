import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tachyon/core/backend/direct_backend_client.dart';
import 'package:tachyon/core/backend/services/metadata_service.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/library/data/library_store.dart';
import 'package:tachyon/features/library/domain/scan_progress.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/shell/scan_progress_overlay.dart';
import 'package:tachyon/shared/utils/cover_utils.dart';

class _TestLocaleRepository extends LocaleRepository {
  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async {
    final file = File('i18n/$localeCode.jsonc');
    if (!file.existsSync()) return {};
    final content = file.readAsStringSync();
    final json = jsoncDecode(content) as Map<String, dynamic>;
    return json.map((key, value) => MapEntry(key, value.toString().trim()));
  }
}

void main() {
  group('ScanProgress Domain Model', () {
    test('Default values and lifecycle properties', () {
      const progress = ScanProgress();
      expect(progress.stage, ScanStage.idle);
      expect(progress.progressLabel, isNull);
      expect(progress.progressValue, isNull);
      expect(progress.errorMessage, isNull);
      expect(progress.isRunning, isFalse);
      expect(progress.isDone, isFalse);

      const running = ScanProgress(
        stage: ScanStage.extracting,
        progressLabel: '15/100',
        progressValue: 0.15,
      );
      expect(running.isRunning, isTrue);
      expect(running.isDone, isFalse);

      const completed = ScanProgress(
        stage: ScanStage.completed,
        progressValue: 1.0,
      );
      expect(completed.isRunning, isFalse);
      expect(completed.isDone, isTrue);

      const failed = ScanProgress(
        stage: ScanStage.failed,
        errorMessage: 'Disk error',
      );
      expect(failed.isRunning, isFalse);
      expect(failed.isDone, isTrue);

      const cancelled = ScanProgress(stage: ScanStage.cancelled);
      expect(cancelled.isRunning, isFalse);
      expect(cancelled.isDone, isTrue);
    });

    test('JSON serialization round-trip', () {
      const original = ScanProgress(
        stage: ScanStage.extracting,
        progressLabel: '20/50',
        progressValue: 0.4,
        errorMessage: null,
      );

      final json = original.toJson();
      expect(json['stage'], 'extracting');
      expect(json['progressLabel'], '20/50');
      expect(json['progressValue'], 0.4);
      expect(json['errorMessage'], isNull);

      final deserialized = ScanProgress.fromJson(json);
      expect(deserialized, equals(original));
      expect(deserialized.stage, ScanStage.extracting);
      expect(deserialized.progressLabel, '20/50');
      expect(deserialized.progressValue, 0.4);
    });

    test('copyWith works correctly', () {
      const original = ScanProgress(
        stage: ScanStage.discovering,
        progressLabel: '10/20',
        progressValue: 0.5,
      );

      final updated = original.copyWith(
        stage: ScanStage.comparing,
        clearProgressLabel: true,
      );

      expect(updated.stage, ScanStage.comparing);
      expect(updated.progressLabel, isNull);
      expect(updated.progressValue, 0.5);
    });
  });

  group('MetadataService & Concurrency Guard', () {
    late Directory tempDir;
    late AppDatabase database;
    late MetadataService metadataService;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('tachyon_scan_test_');
      CoverUtils.init(tempDir);
      database = AppDatabase.inMemory();
      metadataService = MetadataService(
        database: database,
        cacheDirPath: tempDir.path,
        customWorkerCount: 2,
      );
    });

    tearDown(() {
      metadataService.cancelScan();
      database.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('concurrent scan requests are queued and executed sequentially', () async {
      expect(metadataService.isScanning, isFalse);

      final stream1 = metadataService.scanDirectories([]);
      expect(metadataService.isScanning, isTrue);

      // Attempt second scan while first is in progress
      final stream2 = metadataService.scanDirectories([]);

      // First scan completes
      final stream1Events = await stream1.toList();
      expect(stream1Events.last.stage, ScanStage.completed);

      // Second scan was queued and completes sequentially
      final stream2Events = await stream2.toList();
      expect(stream2Events.last.stage, ScanStage.completed);

      expect(metadataService.isScanning, isFalse);
    });

    test('Scanning empty directories purges stored tracks', () async {
      // Seed a track in database
      database.upsertTracks([
        ExtractedTrackData(
          filePath: '/fake/music/song1.mp3',
          title: 'Song 1',
          artistNames: ['Artist 1'],
          durationMs: 120000,
          fileSize: 1024,
          modifiedAt: 100,
        ),
      ]);
      expect(database.getCatalogSnapshot().tracks.length, 1);

      // Scan empty list of directories
      final events = await metadataService.scanDirectories([]).toList();
      expect(events.last.stage, ScanStage.completed);

      // Verify track was purged
      expect(database.getCatalogSnapshot().tracks, isEmpty);
    });
  });

  group('LibraryController Concurrency & Empty List', () {
    late AppDatabase database;
    late DirectTachyonBackendClient backend;
    late LibraryController libraryController;
    late Directory tempDir;
    late SettingsRepository settingsRepository;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('tachyon_lib_ctrl_test_');
      CoverUtils.init(tempDir);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      settingsRepository = SettingsRepository(prefs);

      database = AppDatabase.inMemory();
      final metadataService = MetadataService(
        database: database,
        cacheDirPath: tempDir.path,
        customWorkerCount: 1,
      );
      backend = DirectTachyonBackendClient(
        database: database,
        metadataService: metadataService,
      );
      libraryController = LibraryController(
        backend: backend,
        settingsRepository: settingsRepository,
        store: LibraryStore(),
      );
    });

    tearDown(() {
      libraryController.dispose();
      backend.dispose();
      database.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('scanDirectories() with empty settings does not return early and executes scan', () async {
      database.upsertTracks([
        ExtractedTrackData(
          filePath: '/fake/music/song.mp3',
          title: 'Song',
          artistNames: ['Artist'],
          durationMs: 120000,
          fileSize: 1024,
          modifiedAt: 100,
        ),
      ]);
      expect(database.getCatalogSnapshot().tracks.length, 1);

      await settingsRepository.saveSettings(
        settingsRepository.getSettings().copyWith(musicDirectories: []),
      );
      await libraryController.scanDirectories();

      // Wait for completion
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(database.getCatalogSnapshot().tracks, isEmpty);
    });

    test('scanDirectories ignores subsequent calls while scanning', () async {
      final completer = Completer<void>();
      // Trigger scan
      unawaited(libraryController.scanDirectories().then((_) => completer.complete()));
      expect(libraryController.isScanning, isTrue);

      // Second call while scanning should be ignored
      await libraryController.scanDirectories();
      expect(libraryController.isScanning, isTrue);

      await completer.future;
    });

    test('scanDirectories() triggers scan using settings.musicDirectories', () async {
      await settingsRepository.saveSettings(
        settingsRepository.getSettings().copyWith(musicDirectories: ['/configured/folder']),
      );

      expect(libraryController.isScanning, isFalse);

      unawaited(libraryController.scanDirectories());
      expect(libraryController.isScanning, isTrue);
    });

    test('scanDirectories() executes scan with empty list when musicDirectories is empty to purge library', () async {
      database.upsertTracks([
        ExtractedTrackData(
          filePath: '/fake/music/song.mp3',
          title: 'Song',
          artistNames: ['Artist'],
          durationMs: 120000,
          fileSize: 1024,
          modifiedAt: 100,
        ),
      ]);
      expect(database.getCatalogSnapshot().tracks.length, 1);

      await settingsRepository.saveSettings(
        settingsRepository.getSettings().copyWith(musicDirectories: []),
      );

      await libraryController.scanDirectories();

      // Wait for completion
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(database.getCatalogSnapshot().tracks, isEmpty);
    });
  });

  group('ScanProgressOverlay Widget Tests', () {
    late LocaleController localeController;
    late AppDatabase database;
    late DirectTachyonBackendClient backend;
    late LibraryController libraryController;
    late Directory tempDir;
    late SettingsRepository settingsRepository;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('tachyon_overlay_test_');
      CoverUtils.init(tempDir);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      settingsRepository = SettingsRepository(prefs);

      localeController = LocaleController(_TestLocaleRepository(), 'es');
      await localeController.whenReady;

      database = AppDatabase.inMemory();
      backend = DirectTachyonBackendClient(database: database);
      libraryController = LibraryController(
        backend: backend,
        settingsRepository: settingsRepository,
        store: LibraryStore(),
      );
    });

    tearDown(() {
      libraryController.dispose();
      backend.dispose();
      database.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    Widget createTestWidget() {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<LocaleController>.value(
            value: localeController,
          ),
          ChangeNotifierProvider<LibraryController>.value(
            value: libraryController,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Center(child: Text('Main Content')),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: ScanProgressOverlay(),
                ),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('Renders nothing when not scanning', (tester) async {
      await tester.pumpWidget(createTestWidget());
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.stop_rounded), findsNothing);
    });

    testWidgets('Renders stage text, progress label, indicator, and stop button when scanning', (tester) async {
      await tester.pumpWidget(createTestWidget());
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Start scan
      unawaited(libraryController.scanDirectories());
      await tester.pump();

      // Simulate scan progress event
      backend.emitScanProgress(
        const ScanProgress(
          stage: ScanStage.extracting,
          progressLabel: '15/100',
          progressValue: 0.15,
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
      expect(find.text('Obteniendo metadatos 15/100'), findsOneWidget);

      final indicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(indicator.value, 0.15);

      // Tap stop button
      await tester.tap(find.byIcon(Icons.stop_rounded));
      await tester.pump();

      // Controller should register cancellation
      expect(libraryController.scanProgress.stage, ScanStage.cancelled);
    });
  });
}
