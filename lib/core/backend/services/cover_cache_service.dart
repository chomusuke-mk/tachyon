import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:haudiotagger/haudiotagger.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'package:tachyon/features/library/domain/thumbnail_quality.dart';
import 'package:tachyon/core/constants/app_defaults.dart';

export 'package:tachyon/features/library/domain/thumbnail_quality.dart';

/// Service for cover and artist art extraction, directory artwork fallbacks,
/// dual-quality SHA-256 disk caching, and non-distorting center-crop generation
/// (100x100 square for low quality, maximum 1000x1000 square for high quality in WebP format).
class CoverCacheService {
  final Directory cacheDirectory;
  final String defaultCoverAsset;

  static const List<String> directoryCoverCandidates = [
    'cover.webp',
    'cover.jpg',
    'cover.jpeg',
    'cover.png',
    'folder.webp',
    'folder.jpg',
    'folder.jpeg',
    'folder.png',
    'album.webp',
    'album.jpg',
    'album.jpeg',
    'album.png',
    'front.webp',
    'front.jpg',
    'front.jpeg',
    'front.png',
  ];

  static const List<String> directoryArtistCandidates = [
    'artist.webp',
    'artist.jpg',
    'artist.jpeg',
    'artist.png',
    'band.webp',
    'band.jpg',
    'band.jpeg',
    'band.png',
  ];

  static const Set<String> supportedTagExtensions = {
    '.mp3',
    '.flac',
    '.m4a',
    '.mp4',
    '.aac',
    '.ogg',
    '.oga',
    '.opus',
    '.wav',
    '.aif',
    '.aiff',
    '.aifc',
    '.ape',
    '.wv',
    '.mpc',
    '.spx',
  };

  CoverCacheService({
    required this.cacheDirectory,
    this.defaultCoverAsset = 'assets/images/default_album.webp',
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

  File _resolveFile(String hash, ThumbnailQuality quality) {
    final suffix = switch (quality) {
      ThumbnailQuality.low => 'lq',
      ThumbnailQuality.medium => 'mq',
      ThumbnailQuality.high => 'hq',
    };
    return File(p.join(_coversDir.path, '${hash}_$suffix.jpg'));
  }

  File getCoverFile(
    String filePath, {
    ThumbnailQuality quality = ThumbnailQuality.low,
  }) {
    final hash = computeHash(filePath);
    return _resolveFile(hash, quality);
  }

  File getArtistCoverFile(
    String artistName, {
    ThumbnailQuality quality = ThumbnailQuality.low,
  }) {
    final hash = computeHash('artist:${artistName.trim().toLowerCase()}');
    return _resolveFile(hash, quality);
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

  /// Extracts and caches track and artist artwork in both high quality (max 1000x1000)
  /// and low quality (100x100 center-cropped square) WebP formats without distortion.
  Future<File?> saveCacheCover(
    String filePath, {
    String? artistName,
    String? albumName,
    bool force = false,
    Tag? tag,
  }) async {
    final hash = computeHash(filePath);
    final lqFile = File(p.join(_coversDir.path, '${hash}_lq.jpg'));
    final mqFile = File(p.join(_coversDir.path, '${hash}_mq.jpg'));
    final hqFile = File(p.join(_coversDir.path, '${hash}_hq.jpg'));

    // 1. Return immediately if already cached
    if (!force) {
      final hasLq = await lqFile.exists() && await lqFile.length() > 0;
      final hasMq = await mqFile.exists() && await mqFile.length() > 0;
      final hasHq = await hqFile.exists() && await hqFile.length() > 0;
      if (hasLq && hasMq && hasHq) {
        return hqFile;
      }
    }

    await init();

    Uint8List? coverBytes;
    Uint8List? artistBytes;

    // 2. Read embedded pictures from file tags
    final ext = p.extension(filePath).toLowerCase();
    if (tag != null || supportedTagExtensions.contains(ext)) {
      try {
        final parsedTag = tag ?? await Haudiotagger.read(filePath);
        if (parsedTag != null) {
          // Search for front cover
          for (final pic in parsedTag.pictures) {
            if (pic.pictureType == PictureType.coverFront) {
              coverBytes = pic.bytes;
              break;
            }
          }
          // Fallback: first non-artist picture or first available
          if (coverBytes == null && parsedTag.pictures.isNotEmpty) {
            for (final pic in parsedTag.pictures) {
              if (pic.pictureType != PictureType.leadArtist &&
                  pic.pictureType != PictureType.artist &&
                  pic.pictureType != PictureType.band &&
                  pic.pictureType != PictureType.bandLogo) {
                coverBytes = pic.bytes;
                break;
              }
            }
            coverBytes ??= parsedTag.pictures.first.bytes;
          }

          // Search for artist picture
          for (final pic in parsedTag.pictures) {
            if (pic.pictureType == PictureType.leadArtist ||
                pic.pictureType == PictureType.artist ||
                pic.pictureType == PictureType.band ||
                pic.pictureType == PictureType.bandLogo) {
              artistBytes = pic.bytes;
              break;
            }
          }

          artistName ??= parsedTag.trackArtist ?? parsedTag.albumArtist;
          albumName ??= parsedTag.album;
        }
      } catch (e) {
        debugPrint(
          '[CoverCache] Error reading embedded pictures from $filePath: $e',
        );
      }
    }

    // 3. Directory cover art fallback
    if (coverBytes == null || coverBytes.isEmpty) {
      final dirArt = findDirectoryCoverArt(filePath);
      if (dirArt != null) {
        try {
          coverBytes = await dirArt.readAsBytes();
        } catch (_) {}
      }
    }
    // 4. Directory artist art fallback
    if (artistBytes == null || artistBytes.isEmpty) {
      final dirArtist = findDirectoryArtistArt(filePath);
      if (dirArtist != null) {
        try {
          artistBytes = await dirArtist.readAsBytes();
        } catch (_) {}
      }
    }

    // 5. Write triple quality track/album cover
    if (coverBytes != null && coverBytes.isNotEmpty) {
      await _writeTripleQualityImages(coverBytes, hqFile, mqFile, lqFile);
    }

    // 6. Write triple quality artist image if available
    if (artistBytes != null &&
        artistBytes.isNotEmpty &&
        artistName != null &&
        artistName.trim().isNotEmpty) {
      final aHash = computeHash('artist:${artistName.trim().toLowerCase()}');
      final aLqFile = File(p.join(_coversDir.path, '${aHash}_lq.jpg'));
      final aMqFile = File(p.join(_coversDir.path, '${aHash}_mq.jpg'));
      final aHqFile = File(p.join(_coversDir.path, '${aHash}_hq.jpg'));
      await _writeTripleQualityImages(artistBytes, aHqFile, aMqFile, aLqFile);
    }

    if (await hqFile.exists() && await hqFile.length() > 0) {
      return hqFile;
    }
    return null;
  }

  @visibleForTesting
  static Future<void> writeTripleQualityImages(
    Uint8List rawBytes,
    File hqFile,
    File mqFile,
    File lqFile,
  ) =>
      _writeTripleQualityImages(rawBytes, hqFile, mqFile, lqFile);

  static Future<void> _writeTripleQualityImages(
    Uint8List rawBytes,
    File hqFile,
    File mqFile,
    File lqFile,
  ) async {
    try {
      final decoded = img.decodeImage(rawBytes);
      if (decoded != null) {
        // Take min(width, height) and center-crop square to prevent distortion
        final minDim = math.min(decoded.width, decoded.height);
        final cropX = (decoded.width - minDim) ~/ 2;
        final cropY = (decoded.height - minDim) ~/ 2;

        final squareImage = (cropX == 0 &&
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

        // 1. High Quality: 800x800 square
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

        // 2. Cascade downsample to Medium Quality: 250x250 square (from hqImage for massive CPU saving)
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

        // 3. Cascade downsample to Low Quality: 50x50 square (from mqImage)
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

        // Highly optimized JPEG encoding with quality levels tuned for size & speed
        final hqBytes = img.encodeJpg(hqImage, quality: 82);
        final mqBytes = img.encodeJpg(mqImage, quality: 78);
        final lqBytes = img.encodeJpg(lqImage, quality: 72);

        if (!hqFile.parent.existsSync()) {
          hqFile.parent.createSync(recursive: true);
        }

        await Future.wait([
          hqFile.writeAsBytes(hqBytes),
          mqFile.writeAsBytes(mqBytes),
          lqFile.writeAsBytes(lqBytes),
        ]);
      } else {
        if (!hqFile.parent.existsSync()) {
          hqFile.parent.createSync(recursive: true);
        }
        await Future.wait([
          hqFile.writeAsBytes(rawBytes),
          mqFile.writeAsBytes(rawBytes),
          lqFile.writeAsBytes(rawBytes),
        ]);
      }
    } catch (e) {
      debugPrint('[CoverCache] Error generating triple quality images: $e');
      try {
        if (!await lqFile.exists()) await lqFile.writeAsBytes(rawBytes);
        if (!await mqFile.exists()) await mqFile.writeAsBytes(rawBytes);
        if (!await hqFile.exists()) await hqFile.writeAsBytes(rawBytes);
      } catch (_) {}
    }
  }

  File? findDirectoryCoverArt(String filePath) {
    final parentDir = Directory(p.dirname(filePath));
    if (!parentDir.existsSync()) return null;
    // Fast check for exact lowercase matches
    for (final name in directoryCoverCandidates) {
      final candidate = File(p.join(parentDir.path, name));
      if (candidate.existsSync() && candidate.lengthSync() > 0) {
        return candidate;
      }
    }
    // Case-insensitive fallback scan
    try {
      final entries = parentDir.listSync(followLinks: false);
      final candidateSet = directoryCoverCandidates.toSet();
      for (final entry in entries) {
        if (entry is File) {
          final baseName = p.basename(entry.path).toLowerCase();
          if (candidateSet.contains(baseName) && entry.lengthSync() > 0) {
            return entry;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  File? findDirectoryArtistArt(String filePath) {
    final parentDir = Directory(p.dirname(filePath));
    if (!parentDir.existsSync()) return null;
    for (final name in directoryArtistCandidates) {
      final candidate = File(p.join(parentDir.path, name));
      if (candidate.existsSync() && candidate.lengthSync() > 0) {
        return candidate;
      }
    }
    try {
      final entries = parentDir.listSync(followLinks: false);
      final candidateSet = directoryArtistCandidates.toSet();
      for (final entry in entries) {
        if (entry is File) {
          final baseName = p.basename(entry.path).toLowerCase();
          if (candidateSet.contains(baseName) && entry.lengthSync() > 0) {
            return entry;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> clearCache() async {
    if (await _coversDir.exists()) {
      await _coversDir.delete(recursive: true);
      await _coversDir.create(recursive: true);
    }
  }
}
