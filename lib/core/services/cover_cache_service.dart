import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:tachyon/core/utils/platform_utils.dart';

import '../database/app_database.dart';
import 'process_executor.dart';

/// Contract for cover art extraction, directory artwork fallbacks,
/// SHA-256 disk caching, and database status synchronization.
abstract class CoverCacheService {
  /// Base directory where extracted cover images are cached.
  Directory get cacheDirectory;

  /// Default asset path when no embedded or directory cover exists.
  String get defaultCoverAsset;

  /// Initializes the cache directory structure on disk.
  Future<void> init();

  /// Computes the deterministic 64-character SHA-256 hex string for [filePath].
  String computeHash(String filePath);

  /// Returns the expected cached cover [File] handle for [filePath].
  File getCoverFile(String filePath);

  /// Returns `true` if a non-empty cached cover exists on disk for [filePath].
  bool hasCachedCover(String filePath);

  /// Extracts embedded cover art via ffmpeg or searches for directory fallback artwork.
  /// If artwork is found, it is stored at `<cacheDirectory>/covers/<HASH>.jpg`.
  /// Returns the cached [File] if available, or `null` if no artwork exists.
  Future<File?> extractAndCacheCover(
    String filePath, {
    bool hasAttachedPic = false,
  });

  /// Scans the folder containing [filePath] for common album art image filenames
  /// (`cover.jpg`, `folder.jpg`, `album.jpg`, `front.jpg`, case-insensitively).
  File? findDirectoryCoverArt(String filePath);

  /// Updates the `has_cover` column in the SQLite [AppDatabase] for track [filePath].
  Future<void> updateTrackCoverStatus(
    AppDatabase db,
    String filePath,
    bool hasCover,
  );

  /// Clears all cached cover files from the disk cache.
  Future<void> clearCache();
}

/// Production implementation of [CoverCacheService].
class CoverCacheServiceImpl implements CoverCacheService {
  @override
  final Directory cacheDirectory;
  final String? ffmpegBinaryPath;
  final ProcessExecutor executor;

  @override
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

  CoverCacheServiceImpl({
    required this.cacheDirectory,
    this.ffmpegBinaryPath,
    this.executor = const NativeProcessExecutor(),
    this.defaultCoverAsset = 'assets/images/default_album.jpg',
  });

  Directory get _coversDir => Directory(p.join(cacheDirectory.path, 'covers'));

  @override
  Future<void> init() async {
    if (!await _coversDir.exists()) {
      await _coversDir.create(recursive: true);
    }
  }

  @override
  String computeHash(String filePath) {
    final bytes = utf8.encode(filePath);
    return sha256.convert(bytes).toString();
  }

  @override
  File getCoverFile(String filePath) {
    final hash = computeHash(filePath);
    return File(p.join(_coversDir.path, '$hash.jpg'));
  }

  @override
  bool hasCachedCover(String filePath) {
    final file = getCoverFile(filePath);
    return file.existsSync() && file.lengthSync() > 0;
  }

  @override
  Future<File?> extractAndCacheCover(
    String filePath, {
    bool hasAttachedPic = false,
  }) async {
    final targetFile = getCoverFile(filePath);

    // 1. Return immediately if already cached
    if (await targetFile.exists() && await targetFile.length() > 0) {
      return targetFile;
    }

    await init();

    // 2. Extract embedded cover art via ffmpeg if video/attached_pic stream was detected
    if (hasAttachedPic) {
      try {
        final ffmpeg =
            ffmpegBinaryPath ?? await PlatformUtils.resolveExecutable('ffmpeg');

        final result = await executor.run(ffmpeg, [
          '-y',
          '-v',
          'quiet',
          '-i',
          filePath,
          '-an',
          '-vcodec',
          'copy',
          targetFile.path,
        ]);

        if (result.exitCode == 0 &&
            await targetFile.exists() &&
            await targetFile.length() > 0) {
          return targetFile;
        }

        // Clean up empty or corrupted zero-byte artifact if ffmpeg failed
        if (await targetFile.exists()) {
          await targetFile.delete();
        }
      } catch (_) {
        // Fallback to directory art if process execution fails
      }
    }

    // 3. Fallback: Check track directory for cover/folder image files
    final dirArt = findDirectoryCoverArt(filePath);
    if (dirArt != null) {
      try {
        await dirArt.copy(targetFile.path);
        if (await targetFile.exists() && await targetFile.length() > 0) {
          return targetFile;
        }
      } catch (_) {}
    }

    return null;
  }

  @override
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

  @override
  Future<void> updateTrackCoverStatus(
    AppDatabase db,
    String filePath,
    bool hasCover,
  ) async {
    await db.database.rawUpdate(
      'UPDATE tracks SET has_cover = ? WHERE uri = ?',
      [hasCover ? 1 : 0, filePath],
    );
  }

  @override
  Future<void> clearCache() async {
    if (await _coversDir.exists()) {
      await _coversDir.delete(recursive: true);
      await _coversDir.create(recursive: true);
    }
  }
}
