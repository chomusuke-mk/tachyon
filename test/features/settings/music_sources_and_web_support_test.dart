import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miniaudio_player/miniaudio_player.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tachyon/core/constants/app_defaults.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/metadata/metadata_service.dart';
import 'package:tachyon/core/metadata/metadata_utils.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/core/storage/persistent_binary_storage.dart';
import 'package:tachyon/core/store/library_store.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';
import 'package:tachyon/features/settings/presentation/settings_screen.dart';

/// Generates a valid 16-bit mono 8000 Hz PCM WAV buffer in memory.
Uint8List _createValidWavBytes({int durationMs = 150}) {
  const sampleRate = 8000;
  const numChannels = 1;
  const bitsPerSample = 16;
  final numSamples = (sampleRate * durationMs) ~/ 1000;
  final dataSize = numSamples * numChannels * (bitsPerSample ~/ 8);
  final fileSize = 36 + dataSize;

  final buffer = ByteData(44 + dataSize);
  // "RIFF"
  buffer.setUint8(0, 0x52);
  buffer.setUint8(1, 0x49);
  buffer.setUint8(2, 0x46);
  buffer.setUint8(3, 0x46);
  buffer.setUint32(4, fileSize, Endian.little);
  // "WAVE"
  buffer.setUint8(8, 0x57);
  buffer.setUint8(9, 0x41);
  buffer.setUint8(10, 0x56);
  buffer.setUint8(11, 0x45);
  // "fmt "
  buffer.setUint8(12, 0x66);
  buffer.setUint8(13, 0x6D);
  buffer.setUint8(14, 0x74);
  buffer.setUint8(15, 0x20);
  buffer.setUint32(16, 16, Endian.little); // PCM chunk size
  buffer.setUint16(20, 1, Endian.little); // AudioFormat = 1 (PCM)
  buffer.setUint16(22, numChannels, Endian.little);
  buffer.setUint32(24, sampleRate, Endian.little);
  buffer.setUint32(
    28,
    sampleRate * numChannels * (bitsPerSample ~/ 8),
    Endian.little,
  );
  buffer.setUint16(32, numChannels * (bitsPerSample ~/ 8), Endian.little);
  buffer.setUint16(34, bitsPerSample, Endian.little);
  // "data"
  buffer.setUint8(36, 0x64);
  buffer.setUint8(37, 0x61);
  buffer.setUint8(38, 0x74);
  buffer.setUint8(39, 0x61);
  buffer.setUint32(40, dataSize, Endian.little);

  return buffer.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await MiniaudioPlayer.ensureInitialized();
  });

  group('Web Parity & Zero Forbidden Imports in lib/', () {
    test(
      'No non-*_io.dart file in lib/ imports dart:io, dart:isolate, or dart:ffi',
      () {
        final libDir = io.Directory('lib');
        expect(libDir.existsSync(), isTrue);

        final violations = <String>[];
        for (final entity in libDir.listSync(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is! io.File || !entity.path.endsWith('.dart')) continue;
          final normalizedPath = p.normalize(entity.path);
          final isIoSpecific = normalizedPath.endsWith('_io.dart');
          final content = entity.readAsStringSync();

          if (content.contains("import 'dart:isolate'") ||
              content.contains('import "dart:isolate"')) {
            violations.add('$normalizedPath imports dart:isolate');
          }

          if (!isIoSpecific) {
            if (content.contains("import 'dart:io'") ||
                content.contains('import "dart:io"')) {
              violations.add('$normalizedPath imports dart:io');
            }
            if (content.contains("import 'dart:ffi'") ||
                content.contains('import "dart:ffi"')) {
              violations.add('$normalizedPath imports dart:ffi');
            }
            if (content.contains("package:http/io_client.dart")) {
              violations.add(
                '$normalizedPath imports package:http/io_client.dart',
              );
            }
          }
        }

        expect(
          violations,
          isEmpty,
          reason:
              'Found non-web-compatible imports in shared lib/ files:\n${violations.join('\n')}',
        );
      },
    );
  });

  group('Fuentes de música: Folder + Individual File Protection & Lifecycle', () {
    late io.Directory tempRoot;
    late io.Directory folderA;
    late io.Directory folderB;
    late AppDatabase db;
    late LibraryStore store;
    late MetadataService metadataService;
    late SettingsRepository settingsRepo;
    late SettingsController settingsController;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      settingsRepo = SettingsRepository(prefs);
      settingsController = SettingsController(repository: settingsRepo);
      await settingsController.init();

      tempRoot = await io.Directory.systemTemp.createTemp(
        'tachyon_music_sources_test_',
      );
      folderA = await io.Directory(p.join(tempRoot.path, 'folder_a')).create();
      folderB = await io.Directory(p.join(tempRoot.path, 'folder_b')).create();

      final coversDir = await io.Directory(
        p.join(tempRoot.path, 'covers'),
      ).create();
      final tempDir = await io.Directory(
        p.join(tempRoot.path, 'temp'),
      ).create();
      MetadataUtils.init(coversDir.path, tempDir.path);

      db = AppDatabase.inMemory();
      store = LibraryStore(db);
      await store.reloadFromDatabase();
      metadataService = MetadataService(
        database: db,
        store: store,
        customWorkerCount: 2,
      );
    });

    tearDown(() async {
      metadataService.dispose();
      settingsController.dispose();
      store.dispose();
      await db.close();
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test(
      'File added individually inside a folder is NOT deleted when the folder is removed, unless the file itself no longer exists',
      () async {
        final wavBytes = _createValidWavBytes();
        final trackInFolderOnly = io.File(
          p.join(folderA.path, 'folder_only.wav'),
        );
        final protectedTrackInFolder = io.File(
          p.join(folderA.path, 'protected_song.wav'),
        );
        final standaloneTrack = io.File(
          p.join(folderB.path, 'standalone_song.wav'),
        );

        await trackInFolderOnly.writeAsBytes(wavBytes, flush: true);
        await protectedTrackInFolder.writeAsBytes(wavBytes, flush: true);
        await standaloneTrack.writeAsBytes(wavBytes, flush: true);

        // 1. Add folderA as a folder, and protectedTrackInFolder + standaloneTrack as individual files
        expect(
          await settingsController.addMusicDirectory(folderA.path),
          isTrue,
        );
        expect(
          await settingsController.addMusicFile(protectedTrackInFolder.path),
          isTrue,
        );
        expect(
          await settingsController.addMusicFile(standaloneTrack.path),
          isTrue,
        );

        // Run scan with folderA + individual files
        await metadataService
            .scanDirectories(
              settingsController.musicDirectories,
              files: settingsController.musicFiles,
            )
            .drain<void>();

        expect(store.tracks.length, 3);
        final pathsAfterFirstScan = store.tracks.map((t) => t.filePath).toSet();
        expect(
          pathsAfterFirstScan,
          containsAll([
            trackInFolderOnly.path,
            protectedTrackInFolder.path,
            standaloneTrack.path,
          ]),
        );

        // 2. Remove folderA from musicDirectories and rescan
        await settingsController.removeMusicDirectory(folderA.path);
        expect(settingsController.musicDirectories, isEmpty);

        await metadataService
            .scanDirectories(
              settingsController.musicDirectories,
              files: settingsController.musicFiles,
            )
            .drain<void>();

        // folder_only.wav must be deleted, while protected_song.wav (inside folderA!)
        // and standalone_song.wav must remain in the database and store!
        final pathsAfterFolderRemoval =
            store.tracks.map((t) => t.filePath).toSet();
        expect(pathsAfterFolderRemoval.length, 2);
        expect(
          pathsAfterFolderRemoval.contains(trackInFolderOnly.path),
          isFalse,
        );
        expect(
          pathsAfterFolderRemoval.contains(protectedTrackInFolder.path),
          isTrue,
        );
        expect(
          pathsAfterFolderRemoval.contains(standaloneTrack.path),
          isTrue,
        );

        // 3. Delete protected_song.wav from disk and rescan: now that it no longer exists,
        // it must be purged from the database even if still listed in musicFiles
        await protectedTrackInFolder.delete();
        await metadataService
            .scanDirectories(
              settingsController.musicDirectories,
              files: settingsController.musicFiles,
            )
            .drain<void>();

        final pathsAfterDiskDeletion =
            store.tracks.map((t) => t.filePath).toSet();
        expect(pathsAfterDiskDeletion, equals({standaloneTrack.path}));
      },
    );

    test(
      'SettingsController validates and persists local files, OPFS URIs, and HTTP/HTTPS links',
      () async {
        final wavFile = io.File(p.join(folderA.path, 'local.wav'));
        await wavFile.writeAsBytes(_createValidWavBytes(), flush: true);

        // Local existing file -> true
        expect(await settingsController.addMusicFile(wavFile.path), isTrue);
        // Non-existent local file -> false
        expect(
          await settingsController.addMusicFile(
            p.join(folderA.path, 'missing.wav'),
          ),
          isFalse,
        );
        // Valid HTTPS link -> true
        const remoteUrl = 'https://cdn.example.com/music/track_01.mp3';
        expect(await settingsController.addMusicFile(remoteUrl), isTrue);
        // Invalid URL -> false
        expect(await settingsController.addMusicFile('http://'), isFalse);

        // OPFS virtual audio file -> true
        final opfsUri = await PersistentBinaryStorage.savePickedAudioFile(
          'web_picked.wav',
          _createValidWavBytes(),
        );
        expect(opfsUri, isNotNull);
        expect(await settingsController.addMusicFile(opfsUri!), isTrue);

        expect(
          settingsController.musicFiles,
          containsAll([wavFile.path, remoteUrl, opfsUri]),
        );
        expect(
          settingsRepo.getMusicFiles(),
          containsAll([wavFile.path, remoteUrl, opfsUri]),
        );

        await settingsController.removeMusicFile(remoteUrl);
        expect(settingsController.musicFiles.contains(remoteUrl), isFalse);
      },
    );
  });

  group('SettingsScreen Fuentes de música UI & Modal Manager', () {
    late AppDatabase db;
    late LibraryStore store;
    late MetadataService metadataService;
    late SettingsRepository settingsRepo;
    late SettingsController settingsController;
    late LibraryController libraryController;
    late PlaybackController playbackController;
    late LocaleController localeController;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        's_music_directories': ['/music/AlbumFolder'],
        's_music_files': [
          '/music/single_1.mp3',
          'https://stream.example.org/song_2.flac',
          '/music/single_3.wav',
          'https://stream.example.org/song_4.ogg',
          '/music/single_5.opus',
        ],
      });
      final prefs = await SharedPreferences.getInstance();
      settingsRepo = SettingsRepository(prefs);
      db = AppDatabase.inMemory();
      store = LibraryStore(db);
      await store.reloadFromDatabase();
      metadataService = MetadataService(database: db, store: store);
      playbackController = PlaybackController(
        store: store,
        settingsRepository: settingsRepo,
        metadataService: metadataService,
      );
      settingsController = SettingsController(
        repository: settingsRepo,
        playbackController: playbackController,
      );
      await settingsController.init();
      libraryController = LibraryController(
        settingsRepository: settingsRepo,
        store: store,
        metadataService: null,
      );
      localeController = LocaleController(LocaleRepository(), 'es');
    });

    tearDown(() async {
      libraryController.dispose();
      settingsController.dispose();
      playbackController.dispose();
      metadataService.dispose();
      store.dispose();
      await db.close();
    });

    Widget buildTestSettingsScreen() {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<LibraryStore>.value(value: store),
          Provider<MetadataService>.value(value: metadataService),
          Provider<SettingsRepository>.value(value: settingsRepo),
          ChangeNotifierProvider<SettingsController>.value(
            value: settingsController,
          ),
          ChangeNotifierProvider<LibraryController>.value(
            value: libraryController,
          ),
          ChangeNotifierProvider<PlaybackController>.value(
            value: playbackController,
          ),
          ChangeNotifierProvider<LocaleController>.value(
            value: localeController,
          ),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      );
    }

    testWidgets(
      'Renders Fuentes de música with Folders, compact 3-file preview, Add File dialog, and searchable Modal Manager without overflow',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 820));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(buildTestSettingsScreen());
        await tester.pumpAndSettle();

        // Verify Folders and compact 3-item preview of files/links
        expect(find.text('/music/AlbumFolder'), findsOneWidget);
        expect(find.text('single_1.mp3'), findsOneWidget);
        expect(find.text('song_2.flac'), findsOneWidget);
        expect(find.text('single_3.wav'), findsOneWidget);
        // 4th and 5th files are hidden from the inline preview to avoid clutter
        expect(find.text('song_4.ogg'), findsNothing);
        expect(find.text('single_5.opus'), findsNothing);

        // Open the "Ver todos (5)" modal manager
        final viewAllBtn = find.byKey(const Key('btn_view_all_music_files'));
        expect(viewAllBtn, findsOneWidget);
        await tester.tap(viewAllBtn);
        await tester.pumpAndSettle();

        final modalFinder = find.byKey(const Key('modal_manage_music_files'));
        expect(modalFinder, findsOneWidget);
        expect(
          find.descendant(of: modalFinder, matching: find.text('song_4.ogg')),
          findsOneWidget,
        );

        // Filter by Local files only
        await tester.tap(find.byKey(const Key('chip_filter_local_files')));
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: modalFinder, matching: find.text('single_1.mp3')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: modalFinder, matching: find.text('single_3.wav')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: modalFinder,
            matching: find.text('single_5.opus'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: modalFinder, matching: find.text('song_2.flac')),
          findsNothing,
        );

        // Filter by Links only
        await tester.tap(find.byKey(const Key('chip_filter_link_files')));
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: modalFinder, matching: find.text('song_2.flac')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: modalFinder, matching: find.text('song_4.ogg')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: modalFinder, matching: find.text('single_1.mp3')),
          findsNothing,
        );

        // Search inside modal
        await tester.enterText(
          find.byKey(const Key('input_filter_music_files')),
          'song_4',
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: modalFinder, matching: find.text('song_4.ogg')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: modalFinder, matching: find.text('song_2.flac')),
          findsNothing,
        );

        // Close modal
        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pumpAndSettle();

        // Open "Añadir archivo" dialog and add a new HTTP audio link
        final addFileBtn = find.byKey(const Key('btn_add_music_file'));
        expect(addFileBtn, findsOneWidget);
        await tester.tap(addFileBtn);
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('input_music_file_or_url')),
          'https://audio.example.com/new_track.mp3',
        );
        await tester.tap(find.byKey(const Key('btn_confirm_add_music_file')));
        await tester.pumpAndSettle();

        expect(
          settingsController.musicFiles,
          contains('https://audio.example.com/new_track.mp3'),
        );
      },
    );

    test(
      'AppDefaults.defaultWebSampleAudioUrls contains the 28 canonical miniaudio_player_assets tracks and launch.json has COOP/COEP headers',
      () {
        expect(AppDefaults.defaultWebSampleAudioUrls.length, 28);
        for (final url in AppDefaults.defaultWebSampleAudioUrls) {
          expect(
            url,
            startsWith(
              'https://raw.githubusercontent.com/chomusuke-mk/miniaudio_player_assets/main/',
            ),
          );
          final uri = Uri.tryParse(url);
          expect(uri, isNotNull);
          expect(uri!.host, 'raw.githubusercontent.com');
        }

        final launchJson = io.File('.vscode/launch.json').readAsStringSync();
        expect(
          launchJson,
          contains('--web-header=Cross-Origin-Opener-Policy=same-origin'),
        );
        expect(
          launchJson,
          contains('--web-header=Cross-Origin-Embedder-Policy=require-corp'),
        );
      },
    );
  });
}
