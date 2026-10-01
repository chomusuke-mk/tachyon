import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:tachyon/core/services/cover_cache_service.dart';

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

      expect(lqFile.path, endsWith('${hash}_lq.jpg'));
      expect(hqFile.path, endsWith('${hash}_hq.jpg'));
    });

    test('getArtistCoverFile generates distinct hash for artist', () {
      final aLq = service.getArtistCoverFile('Queen', quality: ThumbnailQuality.low);
      final aHq = service.getArtistCoverFile('Queen', quality: ThumbnailQuality.high);

      final expectedHash = service.computeHash('artist:queen');
      expect(aLq.path, endsWith('${expectedHash}_lq.jpg'));
      expect(aHq.path, endsWith('${expectedHash}_hq.jpg'));
    });

    test('saveCacheCover creates both max 500x500 square HQ and 80x80 center-cropped LQ images', () async {
      // Create a rectangular dummy test cover (400 x 200) to test center-crop without distortion
      final testImage = img.Image(width: 400, height: 200);
      img.fill(testImage, color: img.ColorRgb8(255, 0, 0));
      final jpgBytes = img.encodeJpg(testImage);

      final coverFile = File(p.join(musicDir.path, 'cover.jpg'));
      await coverFile.writeAsBytes(jpgBytes);

      // Also create artist.jpg in the same directory (large: 800x600 to test max 500x500 clamping)
      final artistImage = img.Image(width: 800, height: 600);
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

      // Verify track cover: both HQ and LQ exist
      final hash = service.computeHash(trackPath);
      final lqDisk = File(p.join(tempDir.path, 'covers', '${hash}_lq.jpg'));
      final hqDisk = File(p.join(tempDir.path, 'covers', '${hash}_hq.jpg'));

      expect(await lqDisk.exists(), isTrue);
      expect(await hqDisk.exists(), isTrue);

      // Decode the generated LQ image and verify it is an 80x80 square
      final decodedLq = img.decodeImage(await lqDisk.readAsBytes());
      expect(decodedLq, isNotNull);
      expect(decodedLq!.width, equals(80));
      expect(decodedLq.height, equals(80));

      // Decode the HQ image and verify it is a square center-cropped image (min(400, 200) = 200x200 <= 500)
      final decodedHq = img.decodeImage(await hqDisk.readAsBytes());
      expect(decodedHq, isNotNull);
      expect(decodedHq!.width, equals(200));
      expect(decodedHq.height, equals(200));

      // Verify artist cover was generated from artist.jpg (800x600 -> min(800,600)=600 -> clamped to 500x500)
      final artistHash = service.computeHash('artist:test artist');
      final artistLqDisk = File(p.join(tempDir.path, 'covers', '${artistHash}_lq.jpg'));
      final artistHqDisk = File(p.join(tempDir.path, 'covers', '${artistHash}_hq.jpg'));

      expect(await artistLqDisk.exists(), isTrue);
      expect(await artistHqDisk.exists(), isTrue);

      final decodedArtistLq = img.decodeImage(await artistLqDisk.readAsBytes());
      expect(decodedArtistLq!.width, equals(80));
      expect(decodedArtistLq.height, equals(80));

      final decodedArtistHq = img.decodeImage(await artistHqDisk.readAsBytes());
      expect(decodedArtistHq!.width, equals(500));
      expect(decodedArtistHq.height, equals(500));
    });
  });
}
