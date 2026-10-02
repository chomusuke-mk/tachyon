import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/backend/services/cover_cache_service.dart';
import 'package:tachyon/core/backend/services/metadata_service.dart';
import 'package:tachyon/features/library/domain/track.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase db;
  late CoverCacheService coverCacheService;
  late MetadataService metadataService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tachyon_scan_test_');
    db = AppDatabase.inMemory();
    coverCacheService = CoverCacheService(cacheDirectory: tempDir);
    metadataService = MetadataService(
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

  group('MetadataService Incremental Scan Contract', () {
    test('TrackFileMeta record stores modifiedAt and fileSize accurately', () {
      final Map<String, TrackFileMeta> metas = {
        '/path/track1.mp3': (modifiedAt: 123456789, fileSize: 1024),
        '/path/track2.flac': (modifiedAt: 987654321, fileSize: 2048),
      };

      expect(metas.length, equals(2));
      expect(metas['/path/track1.mp3']?.modifiedAt, equals(123456789));
      expect(metas['/path/track1.mp3']?.fileSize, equals(1024));
      expect(metas['/path/track2.flac']?.modifiedAt, equals(987654321));
      expect(metas['/path/track2.flac']?.fileSize, equals(2048));
    });

    test('MetadataService queries existing track metas from DB', () async {
      const track = Track(
        filePath: '/media/test.mp3',
        title: 'Test Track',
        fileSize: 4096,
        modifiedAt: 1600000000000,
        durationMs: 120000,
      );
      await db.batchInsertTracks([track]);

      final metas = await metadataService.database.getExistingTrackMetas();
      expect(metas.length, equals(1));
      expect(metas['/media/test.mp3']?.fileSize, equals(4096));
      expect(metas['/media/test.mp3']?.modifiedAt, equals(1600000000000));
    });
  });
}
