import 'dart:convert';
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Contract for cover art extraction, directory artwork fallbacks,
/// SHA-256 disk caching, and database status synchronization.

/// Production implementation of [CoverCacheService].
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

  String computeHash(String filePath) {
    final bytes = utf8.encode(filePath);
    return sha256.convert(bytes).toString();
  }

  File getCoverFile(String filePath) {
    final hash = computeHash(filePath);
    return File(p.join(_coversDir.path, '$hash.jpg'));
  }

  bool hasCachedCover(String filePath) {
    final file = getCoverFile(filePath);
    return file.existsSync() && file.lengthSync() > 0;
  }

  Future<File?> saveCacheCover(String filePath) async {
    final targetFile = getCoverFile(filePath);

    // 1. Return immediately if already cached
    if (await targetFile.exists() && await targetFile.length() > 0) {
      return targetFile;
    }

    await init();

    // 2. Save embedded picture to cache
    try {
      final mediaFile = File(filePath);
      final metadata = readMetadata(mediaFile, getImage: true);
      final bytes = metadata.pictures.isNotEmpty
          ? metadata.pictures.first.bytes
          : null;
      if (bytes == null || bytes.isEmpty) {
        debugPrint('[CoverCache] No embedded picture found for $filePath');
        return null;
      }
      await targetFile.writeAsBytes(bytes);
      if (await targetFile.exists() && await targetFile.length() > 0) {
        return targetFile;
      }
    } catch (e) {
      debugPrint('[CoverCache] Save embedded picture failed: $e');
    }

    // 3. Fallback: Check track directory for cover/folder image files
    final dirArt = findDirectoryCoverArt(filePath);
    debugPrint('[CoverCache] dirArt=${dirArt?.path ?? "null"} for $filePath');
    if (dirArt != null) {
      try {
        await dirArt.copy(targetFile.path);
        if (await targetFile.exists() && await targetFile.length() > 0) {
          debugPrint('[CoverCache] Directory art copied → ${targetFile.path}');
          return targetFile;
        }
      } catch (e) {
        debugPrint('[CoverCache] Copy dir art failed: $e');
      }
    }

    debugPrint('[CoverCache] No cover found for $filePath');
    return null;
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

    // Case-insensitive fallback scan for Linux/Unix systems
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

  Future<void> clearCache() async {
    if (await _coversDir.exists()) {
      await _coversDir.delete(recursive: true);
      await _coversDir.create(recursive: true);
    }
  }
}
