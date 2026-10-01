import 'dart:convert';
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

enum ThumbnailQuality {
  low,
  high,
}

/// Service for cover and artist art extraction, directory artwork fallbacks,
/// dual-quality SHA-256 disk caching, and non-distorting center-crop generation.
class CoverCacheService {
  final Directory cacheDirectory;
  final String defaultCoverAsset;

  static const List<String> directoryCoverCandidates = [
    'cover.jpg',
    'cover.jpeg',
    'cover.png',
    'folder.jpg',
    'folder.jpeg',
    'folder.png',
    'album.jpg',
    'album.jpeg',
    'album.png',
    'front.jpg',
    'front.jpeg',
    'front.png',
  ];

  static const List<String> directoryArtistCandidates = [
    'artist.jpg',
    'artist.jpeg',
    'artist.png',
    'band.jpg',
    'band.jpeg',
    'band.png',
  ];

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

  /// Extracts and caches track and artist artwork in both high quality (original)
  /// and low quality (160x160 center-cropped square) formats without distortion.
  Future<File?> saveCacheCover(
    String filePath, {
    String? artistName,
    String? albumName,
  }) async {
    final hash = computeHash(filePath);
    final lqFile = File(p.join(_coversDir.path, '${hash}_lq.jpg'));
    final hqFile = File(p.join(_coversDir.path, '${hash}_hq.jpg'));
    final legacyFile = File(p.join(_coversDir.path, '$hash.jpg'));

    // 1. Return immediately if already cached
    final hasLq = await lqFile.exists() && await lqFile.length() > 0;
    final hasHq = await hqFile.exists() && await hqFile.length() > 0;
    if (hasLq && hasHq) {
      return hqFile;
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
      // 1. Write high-quality original image
      await hqFile.writeAsBytes(rawBytes);
      if (!await legacyFile.exists() || await legacyFile.length() == 0) {
        await legacyFile.writeAsBytes(rawBytes);
      }

      // 2. Generate center-cropped 160x160 square thumbnail
      final decoded = img.decodeImage(rawBytes);
      if (decoded != null) {
        final square = img.copyResizeCropSquare(decoded, size: 160);
        final lqBytes = img.encodeJpg(square, quality: 80);
        await lqFile.writeAsBytes(lqBytes);
      } else {
        await lqFile.writeAsBytes(rawBytes);
      }
    } catch (e) {
      debugPrint('[CoverCache] Error generating dual quality images: $e');
      try {
        if (!await lqFile.exists()) await lqFile.writeAsBytes(rawBytes);
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
