import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:tachyon/core/backend/services/cover_cache_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory musicDir;
  late CoverCacheService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tachyon_cover_test_');
    musicDir = await Directory.systemTemp.createTemp('tachyon_music_test_');
    service = CoverCacheService(cacheDirectory: tempDir);
    await service.init();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
    if (await musicDir.exists()) {
      await musicDir.delete(recursive: true);
    }
  });

  group('CoverCacheService Dual Quality and Center-Crop', () {
    test('getCoverFile returns correct paths based on ThumbnailQuality', () {
      final trackPath = p.join(musicDir.path, 'song.mp3');
      final hash = service.computeHash(trackPath);

      final lqFile = service.getCoverFile(trackPath, quality: ThumbnailQuality.low);
      final hqFile = service.getCoverFile(trackPath, quality: ThumbnailQuality.high);

      expect(lqFile.path, endsWith('${hash}_lq.webp'));
      expect(hqFile.path, endsWith('${hash}_hq.webp'));
    });

    test('getArtistCoverFile generates distinct hash for artist', () {
      final aLq = service.getArtistCoverFile('Queen', quality: ThumbnailQuality.low);
      final aHq = service.getArtistCoverFile('Queen', quality: ThumbnailQuality.high);

      final expectedHash = service.computeHash('artist:queen');
      expect(aLq.path, endsWith('${expectedHash}_lq.webp'));
      expect(aHq.path, endsWith('${expectedHash}_hq.webp'));
    });

    test('saveCacheCover creates both max 1000x1000 square HQ and 100x100 center-cropped LQ images in WebP', () async {
      // Create a rectangular dummy test cover (400 x 200) to test center-crop without distortion
      final testImage = img.Image(width: 400, height: 200);
      img.fill(testImage, color: img.ColorRgb8(255, 0, 0));
      final jpgBytes = img.encodeJpg(testImage);

      final coverFile = File(p.join(musicDir.path, 'cover.jpg'));
      await coverFile.writeAsBytes(jpgBytes);

      // Also create artist.jpg in the same directory (large: 1400x1200 to test max 1000x1000 clamping)
      final artistImage = img.Image(width: 1400, height: 1200);
      img.fill(artistImage, color: img.ColorRgb8(0, 0, 255));
      final artistJpgBytes = img.encodeJpg(artistImage);
      final artistFile = File(p.join(musicDir.path, 'artist.jpg'));
      await artistFile.writeAsBytes(artistJpgBytes);

      final trackPath = p.join(musicDir.path, 'test_song.mp3');
      final dummyAudio = File(trackPath);
      await dummyAudio.writeAsString('not a real audio file');

      final saved = await service.saveCacheCover(
        trackPath,
        artistName: 'Test Artist',
        albumName: 'Test Album',
      );

      expect(saved, isNotNull);
      expect(await saved!.exists(), isTrue);

      // Verify track cover: both HQ and LQ exist as WebP
      final hash = service.computeHash(trackPath);
      final lqDisk = File(p.join(tempDir.path, 'covers', '${hash}_lq.webp'));
      final hqDisk = File(p.join(tempDir.path, 'covers', '${hash}_hq.webp'));

      expect(await lqDisk.exists(), isTrue);
      expect(await hqDisk.exists(), isTrue);

      // Decode the generated LQ image and verify it is a 100x100 square
      final decodedLq = img.decodeImage(await lqDisk.readAsBytes());
      expect(decodedLq, isNotNull);
      expect(decodedLq!.width, equals(100));
      expect(decodedLq.height, equals(100));

      // Decode the HQ image and verify it is a square center-cropped image (min(400, 200) = 200x200 <= 1000)
      final decodedHq = img.decodeImage(await hqDisk.readAsBytes());
      expect(decodedHq, isNotNull);
      expect(decodedHq!.width, equals(200));
      expect(decodedHq.height, equals(200));

      // Verify artist cover was generated from artist.jpg (1400x1200 -> min(1400,1200)=1200 -> clamped to 1000x1000)
      final artistHash = service.computeHash('artist:test artist');
      final artistLqDisk = File(p.join(tempDir.path, 'covers', '${artistHash}_lq.webp'));
      final artistHqDisk = File(p.join(tempDir.path, 'covers', '${artistHash}_hq.webp'));

      expect(await artistLqDisk.exists(), isTrue);
      expect(await artistHqDisk.exists(), isTrue);

      final decodedArtistLq = img.decodeImage(await artistLqDisk.readAsBytes());
      expect(decodedArtistLq, isNotNull);
      expect(decodedArtistLq!.width, equals(100));
      expect(decodedArtistLq.height, equals(100));

      final decodedArtistHq = img.decodeImage(await artistHqDisk.readAsBytes());
      expect(decodedArtistHq, isNotNull);
      expect(decodedArtistHq!.width, equals(1000));
      expect(decodedArtistHq.height, equals(1000));
    });
  });
}
