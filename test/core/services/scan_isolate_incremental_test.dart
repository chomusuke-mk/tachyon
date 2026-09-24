import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/services/cover_cache_service.dart';
import 'package:tachyon/core/services/metadata_extractor.dart';
import 'package:tachyon/core/services/scan_isolate.dart';
import 'package:tachyon/features/library/domain/track.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase db;
  late CoverCacheService coverCacheService;
  late MetadataExtractor extractor;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tachyon_scan_test_');
    db = AppDatabase.inMemory();
    coverCacheService = CoverCacheService(cacheDirectory: tempDir);
    extractor = MetadataExtractor(
      database: db,
      coverCacheService: coverCacheService,
    );
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ScanIsolateArgs & Incremental Scan Contract', () {
    test('ScanIsolateArgs defaults existingMetas to empty map if omitted', () {
      final port1 = ReceivePort();
      final port2 = ReceivePort();

      final args = ScanIsolateArgs(
        progressPort: port1.sendPort,
        handshakePort: port2.sendPort,
        directories: ['/path/to/music'],
        coverCachePath: '/path/to/cache',
        workerCount: 4,
      );

      expect(args.existingMetas, isEmpty);
      port1.close();
      port2.close();
    });

    test('ScanIsolateArgs retains provided existingMetas record map', () {
      final port1 = ReceivePort();
      final port2 = ReceivePort();

      final Map<String, TrackFileMeta> metas = {
        '/path/track1.mp3': (modifiedAt: 123456789, fileSize: 1024),
        '/path/track2.flac': (modifiedAt: 987654321, fileSize: 2048),
      };

      final args = ScanIsolateArgs(
        progressPort: port1.sendPort,
        handshakePort: port2.sendPort,
        directories: ['/path/to/music'],
        coverCachePath: '/path/to/cache',
        workerCount: 4,
        existingMetas: metas,
      );

      expect(args.existingMetas.length, equals(2));
      expect(args.existingMetas['/path/track1.mp3']?.modifiedAt, equals(123456789));
      expect(args.existingMetas['/path/track1.mp3']?.fileSize, equals(1024));
      expect(args.existingMetas['/path/track2.flac']?.modifiedAt, equals(987654321));
      expect(args.existingMetas['/path/track2.flac']?.fileSize, equals(2048));

      port1.close();
      port2.close();
    });

    test('MetadataExtractor queries existing track metas from DB', () async {
      const track = Track(
        uri: '/media/test.mp3',
        title: 'Test Track',
        fileSize: 4096,
        modifiedAt: 1600000000000,
        durationMs: 120000,
      );
      await db.batchInsertTracks([track]);

      final metas = await extractor.database.getExistingTrackMetas();
      expect(metas.length, equals(1));
      expect(metas['/media/test.mp3']?.fileSize, equals(4096));
      expect(metas['/media/test.mp3']?.modifiedAt, equals(1600000000000));
    });
  });
}
