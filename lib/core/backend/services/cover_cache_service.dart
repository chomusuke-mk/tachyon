import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'package:tachyon/features/library/domain/thumbnail_quality.dart';

export 'package:tachyon/features/library/domain/thumbnail_quality.dart';

/// Service for cover and artist art extraction, directory artwork fallbacks,
/// dual-quality SHA-256 disk caching, and non-distorting center-crop generation
/// (80x80 square for low quality, maximum 500x500 square for high quality).
class CoverCacheService {
  final Directory cacheDirectory;
  final String defaultCoverAsset;

  CoverCacheService({
    required this.cacheDirectory,
    this.defaultCoverAsset = 'assets/images/default_album.jpg',
  });

  Directory get _coversDir => Directory(p.join(cacheDirectory.path, 'covers'));

  Future<void> init() async {
    if (!await _coversDir.exists()) {
      await _coversDir.create(recursive: true);
    }
  }

  String computeHash(String input) {
    final bytes = utf8.encode(input);
    return sha256.convert(bytes).toString();
  }

  File getCoverFile(
    String filePath, {
    ThumbnailQuality quality = ThumbnailQuality.low,
  }) {
    final hash = computeHash(filePath);
    final lqFile = File(p.join(_coversDir.path, '${hash}_lq.jpg'));
    final hqFile = File(p.join(_coversDir.path, '${hash}_hq.jpg'));
    final legacyFile = File(p.join(_coversDir.path, '$hash.jpg'));

    if (quality == ThumbnailQuality.low) {
      if (lqFile.existsSync() && lqFile.lengthSync() > 0) return lqFile;
      if (hqFile.existsSync() && hqFile.lengthSync() > 0) return hqFile;
      if (legacyFile.existsSync() && legacyFile.lengthSync() > 0) return legacyFile;
      return lqFile;
    } else {
      if (hqFile.existsSync() && hqFile.lengthSync() > 0) return hqFile;
      if (legacyFile.existsSync() && legacyFile.lengthSync() > 0) return legacyFile;
      if (lqFile.existsSync() && lqFile.lengthSync() > 0) return lqFile;
      return hqFile;
    }
  }

  File getArtistCoverFile(
    String artistName, {
    ThumbnailQuality quality = ThumbnailQuality.low,
  }) {
    final hash = computeHash('artist:${artistName.trim().toLowerCase()}');
    final lqFile = File(p.join(_coversDir.path, '${hash}_lq.jpg'));
    final hqFile = File(p.join(_coversDir.path, '${hash}_hq.jpg'));
    final legacyFile = File(p.join(_coversDir.path, '$hash.jpg'));

    if (quality == ThumbnailQuality.low) {
      if (lqFile.existsSync() && lqFile.lengthSync() > 0) return lqFile;
      if (hqFile.existsSync() && hqFile.lengthSync() > 0) return hqFile;
      if (legacyFile.existsSync() && legacyFile.lengthSync() > 0) return legacyFile;
      return lqFile;
    } else {
      if (hqFile.existsSync() && hqFile.lengthSync() > 0) return hqFile;
      if (legacyFile.existsSync() && legacyFile.lengthSync() > 0) return legacyFile;
      if (lqFile.existsSync() && lqFile.lengthSync() > 0) return lqFile;
      return hqFile;
    }
  }

  bool hasCachedCover(
    String filePath, {
    ThumbnailQuality quality = ThumbnailQuality.low,
  }) {
    final file = getCoverFile(filePath, quality: quality);
    return file.existsSync() && file.lengthSync() > 0;
  }

  bool hasCachedArtistCover(
    String artistName, {
    ThumbnailQuality quality = ThumbnailQuality.low,
  }) {
    final file = getArtistCoverFile(artistName, quality: quality);
    return file.existsSync() && file.lengthSync() > 0;
  }

  /// Extracts and caches track and artist artwork in both high quality (max 500x500)
  /// and low quality (80x80 center-cropped square) formats without distortion.
  Future<File?> saveCacheCover(
    String filePath, {
    String? artistName,
    String? albumName,
    bool force = false,
  }) async {
    final hash = computeHash(filePath);
    final lqFile = File(p.join(_coversDir.path, '${hash}_lq.jpg'));
    final hqFile = File(p.join(_coversDir.path, '${hash}_hq.jpg'));
    final legacyFile = File(p.join(_coversDir.path, '$hash.jpg'));

    // 1. Return immediately if already cached
    if (!force) {
      final hasLq = await lqFile.exists() && await lqFile.length() > 0;
      final hasHq = await hqFile.exists() && await hqFile.length() > 0;
      if (hasLq && hasHq) {
        return hqFile;
      }
    }

    await init();

    Uint8List? coverBytes;
    Uint8List? artistBytes;

    // 2. Read embedded pictures from file tags
    try {
      final mediaFile = File(filePath);
      final metadata = readMetadata(mediaFile, getImage: true);

      // Search for front cover
      for (final pic in metadata.pictures) {
        if (pic.pictureType == PictureType.coverFront) {
          coverBytes = pic.bytes;
          break;
        }
      }
      // Fallback: first non-artist picture or first available
      if (coverBytes == null && metadata.pictures.isNotEmpty) {
        for (final pic in metadata.pictures) {
          if (pic.pictureType != PictureType.leadArtist &&
              pic.pictureType != PictureType.artistPerformer &&
              pic.pictureType != PictureType.bandArtistLogotype) {
            coverBytes = pic.bytes;
            break;
          }
        }
        coverBytes ??= metadata.pictures.first.bytes;
      }

      // Search for artist picture
      for (final pic in metadata.pictures) {
        if (pic.pictureType == PictureType.leadArtist ||
            pic.pictureType == PictureType.artistPerformer ||
            pic.pictureType == PictureType.bandArtistLogotype) {
          artistBytes = pic.bytes;
          break;
        }
      }

      artistName ??= metadata.artist;
      albumName ??= metadata.album;
    } catch (e) {
      debugPrint('[CoverCache] Error reading embedded pictures from $filePath: $e');
    }

    // 5. Write dual quality track/album cover
    if (coverBytes != null && coverBytes.isNotEmpty) {
      await _writeDualQualityImages(coverBytes, hqFile, lqFile, legacyFile);
    }

    // 6. Write dual quality artist image if available
    if (artistBytes != null &&
        artistBytes.isNotEmpty &&
        artistName != null &&
        artistName.trim().isNotEmpty) {
      final aHash = computeHash('artist:${artistName.trim().toLowerCase()}');
      final aLqFile = File(p.join(_coversDir.path, '${aHash}_lq.jpg'));
      final aHqFile = File(p.join(_coversDir.path, '${aHash}_hq.jpg'));
      final aLegacyFile = File(p.join(_coversDir.path, '$aHash.jpg'));
      await _writeDualQualityImages(artistBytes, aHqFile, aLqFile, aLegacyFile);
    }

    if (await hqFile.exists() && await hqFile.length() > 0) {
      return hqFile;
    }
    if (await legacyFile.exists() && await legacyFile.length() > 0) {
      return legacyFile;
    }
    return null;
  }

  static Future<void> _writeDualQualityImages(
    Uint8List rawBytes,
    File hqFile,
    File lqFile,
    File legacyFile,
  ) async {
    try {
      final decoded = img.decodeImage(rawBytes);
      if (decoded != null) {
        // Take min(width, height) and center-crop square to prevent any vertical or horizontal stretching
        final minDim = math.min(decoded.width, decoded.height);
        final cropX = (decoded.width - minDim) ~/ 2;
        final cropY = (decoded.height - minDim) ~/ 2;

        final squareImage = img.copyCrop(
          decoded,
          x: cropX,
          y: cropY,
          width: minDim,
          height: minDim,
        );

        // 1. High Quality: maximum 500x500 square
        img.Image hqImage;
        if (minDim > 500) {
          hqImage = img.copyResize(
            squareImage,
            width: 500,
            height: 500,
            interpolation: img.Interpolation.linear,
          );
        } else {
          hqImage = squareImage;
        }
        final hqBytes = img.encodeJpg(hqImage, quality: 85);
        await hqFile.writeAsBytes(hqBytes);
        if (!await legacyFile.exists() || await legacyFile.length() == 0) {
          await legacyFile.writeAsBytes(hqBytes);
        }

        // 2. Low Quality: 80x80 square
        img.Image lqImage;
        if (minDim == 80) {
          lqImage = squareImage;
        } else {
          lqImage = img.copyResize(
            squareImage,
            width: 80,
            height: 80,
            interpolation: img.Interpolation.linear,
          );
        }
        final lqBytes = img.encodeJpg(lqImage, quality: 75);
        await lqFile.writeAsBytes(lqBytes);
      } else {
        await hqFile.writeAsBytes(rawBytes);
        await lqFile.writeAsBytes(rawBytes);
        if (!await legacyFile.exists() || await legacyFile.length() == 0) {
          await legacyFile.writeAsBytes(rawBytes);
        }
      }
    } catch (e) {
      debugPrint('[CoverCache] Error generating dual quality images: $e');
      try {
        if (!await lqFile.exists()) await lqFile.writeAsBytes(rawBytes);
        if (!await hqFile.exists()) await hqFile.writeAsBytes(rawBytes);
      } catch (_) {}
    }
  }

  Future<void> clearCache() async {
    if (await _coversDir.exists()) {
      await _coversDir.delete(recursive: true);
      await _coversDir.create(recursive: true);
    }
  }
}
