import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:tachyon/core/constants/app_defaults.dart';
import 'package:tachyon/features/library/domain/thumbnail_quality.dart';

export 'package:tachyon/features/library/domain/thumbnail_quality.dart';

/// Set of cached files representing low, medium, and high quality artwork.
class CoverFileSet {
  final File lq;
  final File mq;
  final File hq;

  const CoverFileSet({required this.lq, required this.mq, required this.hq});

  File getByQuality(ThumbnailQuality quality) => switch (quality) {
    ThumbnailQuality.low => lq,
    ThumbnailQuality.medium => mq,
    ThumbnailQuality.high => hq,
  };

  Future<bool> existsAll() async {
    return (await lq.exists() && await lq.length() > 0) &&
        (await mq.exists() && await mq.length() > 0) &&
        (await hq.exists() && await hq.length() > 0);
  }

  bool existsAllSync() {
    return lq.existsSync() &&
        lq.lengthSync() > 0 &&
        mq.existsSync() &&
        mq.lengthSync() > 0 &&
        hq.existsSync() &&
        hq.lengthSync() > 0;
  }
}

/// Service for cover, album, and artist artwork extraction, directory fallbacks,
/// standardized SHA-256 disk caching, and non-distorting center-crop generation
/// in triple JPEG quality (low: 50x50, medium: 250x250, high: 800x800).
abstract final class CoverUtils {
  static Directory cacheDirectory = Directory('');
  static bool _isInitialized = false;

  static bool get isInitialized => _isInitialized;

  static Directory get _coversDir =>
      Directory(p.join(cacheDirectory.path, 'covers'));

  static Directory get _tempDir =>
      Directory(p.join(cacheDirectory.path, 'covers_tmp'));

  static void init(Directory cacheDir) {
    cacheDirectory = cacheDir;
    _isInitialized = true;
    if (!cacheDir.existsSync()) {
      cacheDir.createSync(recursive: true);
    }
    if (!_tempDir.existsSync()) {
      _tempDir.createSync(recursive: true);
    }
  }

  /// Cleans all leftover temporary files in `covers_tmp`.
  static Future<void> clearTemp() async {
    if (!_isInitialized) {
      debugPrint(
        '[CoverUtils] Cache directory is not initialized. Cannot clear temp files.',
      );
    }
    try {
      if (await _tempDir.exists()) {
        final entries = _tempDir.listSync(followLinks: false);
        for (final entry in entries) {
          try {
            entry.deleteSync(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Standardized Hash Calculation
  // ---------------------------------------------------------------------------

  static String computeBytesHash(Uint8List bytes) {
    return sha256.convert(bytes).toString();
  }

  static String computeStringHash(String input) {
    return sha256.convert(utf8.encode(input)).toString();
  }

  static String computeHash(String input) => computeStringHash(input);

  static String hashTrack(String filePath) => computeStringHash(filePath);

  static String hashAlbum(String albumName) =>
      computeStringHash('album:${albumName.trim().toLowerCase()}');

  static String hashArtist(String artistName) =>
      computeStringHash('artist:${artistName.trim().toLowerCase()}');

  // ---------------------------------------------------------------------------
  // File Resolution
  // ---------------------------------------------------------------------------

  static CoverFileSet getFilesForHash(String hash) {
    if (!_isInitialized) {
      throw Exception(
        '[CoverUtils] Cache directory is not initialized. Cannot get cover files.',
      );
    }
    return CoverFileSet(
      lq: File(p.join(_coversDir.path, '${hash}_lq.jpg')),
      mq: File(p.join(_coversDir.path, '${hash}_mq.jpg')),
      hq: File(p.join(_coversDir.path, '${hash}_hq.jpg')),
    );
  }

  static CoverFileSet getTrackFiles(String filePath) =>
      getFilesForHash(hashTrack(filePath));

  static CoverFileSet getAlbumFiles(String albumName) =>
      getFilesForHash(hashAlbum(albumName));

  static CoverFileSet getArtistFiles(String artistName) =>
      getFilesForHash(hashArtist(artistName));

  static File getCoverFile(
    String thumbnailHash, {
    ThumbnailQuality quality = ThumbnailQuality.low,
  }) => getFilesForHash(thumbnailHash).getByQuality(quality);

  static File getArtistCoverFile(
    String thumbnailHash, {
    ThumbnailQuality quality = ThumbnailQuality.low,
  }) => getCoverFile(thumbnailHash, quality: quality);

  static File getAlbumCoverFile(
    String thumbnailHash, {
    ThumbnailQuality quality = ThumbnailQuality.low,
  }) => getCoverFile(thumbnailHash, quality: quality);

  static bool hasCachedCover(
    String thumbnailHash, {
    ThumbnailQuality quality = ThumbnailQuality.low,
  }) {
    final file = getCoverFile(thumbnailHash, quality: quality);
    return file.existsSync() && file.lengthSync() > 0;
  }

  static bool hasCachedArtistCover(
    String thumbnailHash, {
    ThumbnailQuality quality = ThumbnailQuality.low,
  }) => hasCachedCover(thumbnailHash, quality: quality);

  static bool hasCachedAlbumCover(
    String thumbnailHash, {
    ThumbnailQuality quality = ThumbnailQuality.low,
  }) => hasCachedCover(thumbnailHash, quality: quality);

  // ---------------------------------------------------------------------------
  // Cover Extraction & Disk Caching
  // ---------------------------------------------------------------------------

  /// Saves raw image bytes addressed by its content hash in triple JPEG quality.
  static Future<File?> saveThumbnailBytes(
    String thumbnailHash,
    Uint8List rawBytes, {
    bool force = false,
  }) async {
    final fileSet = getFilesForHash(thumbnailHash);
    if (!force && fileSet.existsAllSync()) {
      return fileSet.hq;
    }
    await writeTripleQualityImages(rawBytes, [fileSet.hq], [fileSet.mq], [
      fileSet.lq,
    ], tempDirectory: _tempDir);
    return fileSet.hq;
  }

  // ---------------------------------------------------------------------------
  // Triple-Quality Image Processing
  // ---------------------------------------------------------------------------

  /// Center-crops to square and writes 3 downsampled JPEG qualities (HQ: 800x800, MQ: 250x250, LQ: 50x50)
  /// atomically using a temporary file in [tempDirectory].
  static Future<void> writeTripleQualityImages(
    Uint8List rawBytes,
    Iterable<File> hqFiles,
    Iterable<File> mqFiles,
    Iterable<File> lqFiles, {
    Directory? tempDirectory,
  }) async {
    final uniqueHq = {for (final f in hqFiles) f.path: f}.values.toList();
    final uniqueMq = {for (final f in mqFiles) f.path: f}.values.toList();
    final uniqueLq = {for (final f in lqFiles) f.path: f}.values.toList();

    if (uniqueHq.isEmpty && uniqueMq.isEmpty && uniqueLq.isEmpty) return;

    try {
      final decoded = img.decodeImage(rawBytes);
      if (decoded != null) {
        final minDim = math.min(decoded.width, decoded.height);
        final cropX = (decoded.width - minDim) ~/ 2;
        final cropY = (decoded.height - minDim) ~/ 2;

        final squareImage =
            (cropX == 0 &&
                cropY == 0 &&
                decoded.width == minDim &&
                decoded.height == minDim)
            ? decoded
            : img.copyCrop(
                decoded,
                x: cropX,
                y: cropY,
                width: minDim,
                height: minDim,
              );

        // 1. High Quality: 800x800
        final img.Image hqImage;
        if (minDim > AppDefaults.highQualityResolution) {
          hqImage = img.copyResize(
            squareImage,
            width: AppDefaults.highQualityResolution,
            height: AppDefaults.highQualityResolution,
            interpolation: img.Interpolation.linear,
          );
        } else {
          hqImage = squareImage;
        }

        // 2. Medium Quality: 250x250 (cascaded downsampling from hqImage)
        final img.Image mqImage;
        if (hqImage.width > AppDefaults.mediumQualityResolution) {
          mqImage = img.copyResize(
            hqImage,
            width: AppDefaults.mediumQualityResolution,
            height: AppDefaults.mediumQualityResolution,
            interpolation: img.Interpolation.linear,
          );
        } else {
          mqImage = hqImage;
        }

        // 3. Low Quality: 50x50 (cascaded downsampling from mqImage)
        final img.Image lqImage;
        if (mqImage.width > AppDefaults.lowQualityResolution) {
          lqImage = img.copyResize(
            mqImage,
            width: AppDefaults.lowQualityResolution,
            height: AppDefaults.lowQualityResolution,
            interpolation: img.Interpolation.linear,
          );
        } else {
          lqImage = mqImage;
        }

        final hqBytes = img.encodeJpg(hqImage, quality: 82);
        final mqBytes = img.encodeJpg(mqImage, quality: 78);
        final lqBytes = img.encodeJpg(lqImage, quality: 72);

        final writeFutures = <Future<void>>[];
        for (final f in uniqueHq) {
          writeFutures.add(_safeAtomicWrite(f, hqBytes));
        }
        for (final f in uniqueMq) {
          writeFutures.add(_safeAtomicWrite(f, mqBytes));
        }
        for (final f in uniqueLq) {
          writeFutures.add(_safeAtomicWrite(f, lqBytes));
        }
        await Future.wait(writeFutures);
      } else {
        final writeFutures = <Future<void>>[];
        for (final f in [...uniqueHq, ...uniqueMq, ...uniqueLq]) {
          writeFutures.add(_safeAtomicWrite(f, rawBytes));
        }
        await Future.wait(writeFutures);
      }
    } catch (e) {
      debugPrint('[CoverCache] Error generating triple quality images: $e');
      try {
        final writeFutures = <Future<void>>[];
        for (final f in [...uniqueHq, ...uniqueMq, ...uniqueLq]) {
          writeFutures.add(() async {
            if (!await f.exists()) {
              await _safeAtomicWrite(f, rawBytes);
            }
          }());
        }
        await Future.wait(writeFutures);
      } catch (_) {}
    }
  }

  /// Writes [bytes] atomically to a temporary file in [tempDirectory] before renaming to [targetFile].
  static Future<void> _safeAtomicWrite(File targetFile, Uint8List bytes) async {
    if (await targetFile.exists() && await targetFile.length() > 0) {
      return;
    }

    final parent = targetFile.parent;
    if (!parent.existsSync()) {
      try {
        parent.createSync(recursive: true);
      } catch (_) {}
    }

    final tDir = Directory(p.join(parent.path, 'covers_tmp'));
    if (!tDir.existsSync()) {
      try {
        tDir.createSync(recursive: true);
      } catch (_) {}
    }

    final rand = math.Random().nextInt(1 << 30);
    final fileName = p.basename(targetFile.path);
    final tempFile = File(p.join(tDir.path, '${fileName}_${pid}_$rand.tmp'));

    try {
      await tempFile.writeAsBytes(bytes, flush: true);
      await tempFile.rename(targetFile.path);
    } catch (_) {
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
      if (await targetFile.exists() && await targetFile.length() > 0) {
        return;
      }
      try {
        await targetFile.writeAsBytes(bytes, flush: true);
      } catch (_) {}
    }
  }

  static Future<void> clearCache() async {
    if (!_isInitialized) {
      debugPrint(
        '[CoverUtils] Cache directory is not initialized. Cannot clear cache.',
      );
      return;
    }
    if (await _coversDir.exists()) {
      await _coversDir.delete(recursive: true);
      await _coversDir.create(recursive: true);
    }
    await clearTemp();
  }

  static List<File> listCachedCoverFiles() {
    if (!_isInitialized) {
      debugPrint(
        '[CoverUtils] Cache directory is not initialized. Cannot get cached cover files.',
      );
      return [];
    }
    if (!_coversDir.existsSync()) {
      return [];
    }
    final files = _coversDir.listSync(recursive: true, followLinks: false);
    return files.whereType<File>().toList();
  }
}
