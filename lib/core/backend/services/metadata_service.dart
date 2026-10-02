import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/constants/app_defaults.dart';
import 'package:tachyon/core/backend/services/cover_cache_service.dart';
import 'package:tachyon/features/library/domain/scan_progress.dart';
import 'package:tachyon/features/library/domain/track.dart';

/// Track metadata snapshot used to detect unchanged files during incremental scanning.
typedef TrackFileMeta = ({int modifiedAt, int fileSize});

/// Discovered audio file entity awaiting metadata extraction.
class DiscoveredAudioFile {
  final String path;
  final int size;
  final int modifiedAt;

  const DiscoveredAudioFile({
    required this.path,
    required this.size,
    required this.modifiedAt,
  });

  @override
  String toString() => 'DiscoveredAudioFile($path, $size bytes)';
}

/// Service running in the Core Backend Host Isolate responsible for metadata
/// orchestration, single-file tag extraction, thumbnail resolution, and full library scanning.
///
/// Follows a high-performance Cache-First & Isolate.run worker pool strategy:
/// 1. Queries database or disk cache first (immediate return, 0 CPU).
/// 2. If missing, delegates single-file operations to an ephemeral worker via [Isolate.run].
/// 3. Runs multi-file directory scans using a concurrent pool of [Isolate.run] workers
///    scaled to the number of CPU processors ([Platform.numberOfProcessors]).
/// 4. In each worker, extracts metadata and saves dual-quality HQ & LQ covers to disk
///    in a single pass, completely eliminating unawaited futures and redundant file reads.
/// 5. Workers write files directly to disk and return pure Dart models.
///    Zero raw byte buffers are passed between isolates.
class MetadataService {
  final AppDatabase database;
  final CoverCacheService coverCacheService;
  final int? customWorkerCount;

  MetadataService({
    required this.database,
    required this.coverCacheService,
    this.customWorkerCount,
  });

  int get workerCount =>
      customWorkerCount ?? math.max(1, Platform.numberOfProcessors);

  CancellationToken? _currentScanToken;

  static Future<Track?> _runWorkerInIsolate(
    String filePath,
    String cacheDirPath,
  ) {
    return Isolate.run(
      () => extractAndCacheTrackWorker(
        filePath: filePath,
        cacheDirPath: cacheDirPath,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Single-file operations (Isolate.run)
  // ---------------------------------------------------------------------------

  /// Extracts metadata for a single [filePath] in a dedicated worker isolate
  /// via [Isolate.run]. Does not write to SQLite (pure extraction).
  Future<Track?> extractMetadata(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync() && !await file.exists()) return null;

    final cachePath = coverCacheService.cacheDirectory.path;
    return await _runWorkerInIsolate(filePath, cachePath);
  }

  /// Retrieves metadata for a file following a Cache-First strategy:
  /// 1. Checks SQLite DB first (immediate return, 0 CPU).
  /// 2. If absent, extracts via a worker isolate using [Isolate.run].
  /// 3. Persists into SQLite DB on the calling isolate.
  /// 4. Returns the track.
  Future<Track?> getMetadata(String filePath) async {
    final existing = await database.getTrackByFilePath(filePath);
    if (existing != null) {
      return existing;
    }

    final track = await extractMetadata(filePath);
    if (track != null) {
      await database.insertTrack(track);
    }
    return track;
  }

  /// Retrieves the thumbnail image path for a file following a Cache-First strategy:
  /// 1. Checks disk cache first (immediate return, 0 CPU).
  /// 2. If absent, delegates image extraction, square center-cropping, and
  ///    dual-quality JPEG encoding to a worker isolate via [Isolate.run].
  /// 3. Updates track cover status in SQLite DB.
  /// 4. Returns string path (never raw bytes across isolate boundary).
  Future<String?> getThumbnail(
    String filePath, {
    bool isHighQuality = false,
  }) async {
    final quality = isHighQuality
        ? ThumbnailQuality.high
        : ThumbnailQuality.low;

    // 1. Return immediately if cached image file exists on disk
    if (coverCacheService.hasCachedCover(filePath, quality: quality)) {
      final file = coverCacheService.getCoverFile(filePath, quality: quality);
      return file.path;
    }

    // 2. Delegate image extraction and disk writing to a worker isolate via Isolate.run
    final cacheDirPath = coverCacheService.cacheDirectory.path;
    final paths = await Isolate.run(
      () => extractAndSaveThumbnailWorker(
        filePath: filePath,
        cacheDirPath: cacheDirPath,
      ),
    );

    if (paths != null) {
      await database.updateTrackCoverStatus(filePath, true);
      return isHighQuality ? paths['hq'] : paths['lq'];
    }

    return null;
  }

  /// Returns cached artist cover file path if available.
  Future<String?> getArtistCover(
    String artistName, {
    bool isHighQuality = false,
  }) async {
    final quality = isHighQuality
        ? ThumbnailQuality.high
        : ThumbnailQuality.low;
    if (coverCacheService.hasCachedArtistCover(artistName, quality: quality)) {
      final file = coverCacheService.getArtistCoverFile(
        artistName,
        quality: quality,
      );
      return file.path;
    }
    return null;
  }

  /// Clears thumbnail disk cache directory.
  Future<void> clearCoverCache() async {
    await coverCacheService.clearCache();
  }

  // ---------------------------------------------------------------------------
  // Multi-file operations (Isolate.run concurrency pool)
  // ---------------------------------------------------------------------------

  /// Convenience wrapper to discover audio files recursively on the caller isolate.
  Stream<DiscoveredAudioFile> discoverFiles(
    List<String> directories, {
    CancellationToken? cancellationToken,
  }) {
    return _discoverFilesLocal(
      directories,
      cancellationToken: cancellationToken,
    );
  }

  /// Starts the scan pipeline using a pool of [Isolate.run] workers proportional
  /// to CPU cores and returns a [Stream<ScanProgress>].
  Stream<ScanProgress> scanDirectories(
    List<String> directories, {
    CancellationToken? cancellationToken,
  }) {
    final controller = StreamController<ScanProgress>();
    _runScanPipeline(directories, controller, cancellationToken);
    return controller.stream;
  }

  /// Cancels any active library scan.
  void cancelScan() {
    _currentScanToken?.cancel();
    _currentScanToken = null;
  }

  // ---------------------------------------------------------------------------
  // Private: Isolate.run pool orchestration
  // ---------------------------------------------------------------------------

  Future<void> _runScanPipeline(
    List<String> directories,
    StreamController<ScanProgress> controller,
    CancellationToken? cancellationToken,
  ) async {
    cancelScan();

    final scanToken = CancellationToken();
    _currentScanToken = scanToken;

    if (cancellationToken != null) {
      if (cancellationToken.isCancelled) {
        scanToken.cancel();
      } else {
        cancellationToken.onCancel(() => scanToken.cancel());
      }
    }

    controller.onCancel = () {
      scanToken.cancel();
    };

    if (scanToken.isCancelled) {
      if (!controller.isClosed) {
        controller.add(const ScanProgress(phase: ScanPhase.cancelled));
        controller.close();
      }
      return;
    }

    final stopwatch = Stopwatch()..start();
    ScanProgress current = const ScanProgress();
    int lastEmitMs = -50;

    void sendProgress(ScanProgress p, {bool force = false}) {
      current = p.copyWith(elapsedTime: stopwatch.elapsed);
      final now = stopwatch.elapsedMilliseconds;
      if (force || now - lastEmitMs >= 50) {
        lastEmitMs = now;
        if (!controller.isClosed) controller.add(current);
      }
    }

    try {
      sendProgress(
        const ScanProgress(phase: ScanPhase.discovering),
        force: true,
      );

      // 1. File discovery
      final discoveredFiles = <DiscoveredAudioFile>[];
      await for (final file in _discoverFilesLocal(
        directories,
        cancellationToken: scanToken,
      )) {
        if (scanToken.isCancelled) break;
        discoveredFiles.add(file);
        sendProgress(
          ScanProgress(
            phase: ScanPhase.discovering,
            totalFiles: discoveredFiles.length,
            currentFile: file.path,
          ),
        );
      }

      if (scanToken.isCancelled) {
        sendProgress(
          current.copyWith(phase: ScanPhase.cancelled, clearCurrentFile: true),
          force: true,
        );
        if (!controller.isClosed) controller.close();
        return;
      }

      final totalFiles = discoveredFiles.length;
      int scannedCount = 0;
      int skippedCount = 0;
      int newCount = 0;
      int updatedCount = 0;
      int failedCount = 0;

      // 2. Incremental scan preparation
      sendProgress(
        ScanProgress(phase: ScanPhase.extracting, totalFiles: totalFiles),
        force: true,
      );

      Map<String, TrackFileMeta> existingMetas = const {};
      try {
        existingMetas = await database.getExistingTrackMetas();
      } catch (e) {
        debugPrint('[MetadataService] Failed to load existing track metas: $e');
      }

      // 3. Concurrency-bounded extraction with Isolate.run pool
      final pendingTracks = <Track>[];
      final activeTasks = <Future<void>>{};
      final poolSize = workerCount;
      final cacheDirPath = coverCacheService.cacheDirectory.path;

      Future<void> maybeInsertBatch({bool force = false}) async {
        if (pendingTracks.length >= 30 || (force && pendingTracks.isNotEmpty)) {
          final batch = List<Track>.from(pendingTracks);
          pendingTracks.clear();
          sendProgress(
            current.copyWith(phase: ScanPhase.persisting),
            force: true,
          );
          try {
            await database.batchInsertTracks(batch);
          } catch (e) {
            debugPrint('[MetadataService] batchInsert error: $e');
          }
          sendProgress(
            current.copyWith(phase: ScanPhase.extracting),
            force: true,
          );
        }
      }

      for (final file in discoveredFiles) {
        if (scanToken.isCancelled) break;

        final existing = existingMetas[file.path];
        if (existing != null &&
            existing.modifiedAt == file.modifiedAt &&
            existing.fileSize == file.size) {
          skippedCount++;
          scannedCount++;
          sendProgress(
            ScanProgress(
              phase: ScanPhase.extracting,
              scannedFiles: scannedCount,
              totalFiles: totalFiles,
              newTracks: newCount,
              updatedTracks: updatedCount,
              skippedTracks: skippedCount,
              failedTracks: failedCount,
              progress: totalFiles > 0 ? scannedCount / totalFiles : 1.0,
              currentFile: file.path,
            ),
          );
          continue;
        }

        late final Future<void> task;
        task = () async {
          if (scanToken.isCancelled) return;
          Track? track;
          try {
            track = await _runWorkerInIsolate(file.path, cacheDirPath);
          } catch (e) {
            debugPrint('[MetadataService] Worker failed for ${file.path}: $e');
          }

          if (scanToken.isCancelled) return;
          scannedCount++;

          if (track != null) {
            pendingTracks.add(track);
            if (existing != null) {
              updatedCount++;
            } else {
              newCount++;
            }
          } else {
            failedCount++;
          }

          sendProgress(
            ScanProgress(
              phase: ScanPhase.extracting,
              scannedFiles: scannedCount,
              totalFiles: totalFiles,
              newTracks: newCount,
              updatedTracks: updatedCount,
              skippedTracks: skippedCount,
              failedTracks: failedCount,
              progress: totalFiles > 0 ? scannedCount / totalFiles : 1.0,
              currentFile: file.path,
            ),
          );

          await maybeInsertBatch();
        }().whenComplete(() => activeTasks.remove(task));

        activeTasks.add(task);

        if (activeTasks.length >= poolSize) {
          await Future.any(activeTasks);
        }
      }

      if (activeTasks.isNotEmpty) {
        await Future.wait(activeTasks);
      }

      if (scanToken.isCancelled) {
        sendProgress(
          current.copyWith(phase: ScanPhase.cancelled, clearCurrentFile: true),
          force: true,
        );
        if (!controller.isClosed) controller.close();
        return;
      }

      // Flush remaining tracks
      await maybeInsertBatch(force: true);

      try {
        await database.cleanOrphanAlbumsAndArtists();
      } catch (e) {
        debugPrint('[MetadataService] Cleanup error: $e');
      }

      sendProgress(
        ScanProgress(
          phase: ScanPhase.completed,
          scannedFiles: totalFiles,
          totalFiles: totalFiles,
          newTracks: newCount,
          updatedTracks: updatedCount,
          skippedTracks: skippedCount,
          failedTracks: failedCount,
          progress: 1.0,
        ),
        force: true,
      );
      if (!controller.isClosed) controller.close();
    } catch (e, st) {
      debugPrint('[MetadataService] Pipeline failed: $e\n$st');
      sendProgress(
        current.copyWith(
          phase: ScanPhase.failed,
          errorMessage: e.toString(),
          elapsedTime: stopwatch.elapsed,
        ),
        force: true,
      );
      if (!controller.isClosed) controller.close();
    } finally {
      stopwatch.stop();
      if (_currentScanToken == scanToken) {
        _currentScanToken = null;
      }
    }
  }
}

// =============================================================================
// SHARED WORKER FUNCTIONS
// =============================================================================

/// Top-level worker function executed inside [Isolate.run].
/// Reads audio metadata and embedded pictures in a single pass, caches HQ/LQ
/// covers directly to disk, and returns the parsed [Track] model.
/// Helper to construct a fallback [Track] when metadata cannot be read
/// (e.g. extension not in [supportedFileExtensions] of audio_metadata_reader or parsing failed).
Track _buildFallbackTrack({
  required String filePath,
  required int size,
  required int modifiedAt,
}) {
  final extClean = p.extension(filePath).replaceAll('.', '').toUpperCase();
  return Track(
    filePath: filePath,
    title: p.basenameWithoutExtension(filePath),
    album: null,
    artist: null,
    artists: const [],
    albumArtist: null,
    trackNumber: null,
    discNumber: null,
    year: null,
    durationMs: 0,
    bitrate: null,
    sampleRate: null,
    channels: null,
    codec: extClean.isNotEmpty ? extClean : null,
    fileSize: size,
    modifiedAt: modifiedAt,
    lyrics: null,
    genres: const [],
  );
}

/// Worker function that runs in a dedicated isolate via [Isolate.run].
/// In a single pass:
/// 1. Reads file metadata (or falls back if format unsupported or parsing fails).
/// 2. If present, generates dual-quality HQ & LQ covers and writes them to disk.
/// 3. Returns the populated [Track] directly.
///
/// Passes zero raw byte arrays across the isolate boundary.
@pragma('vm:entry-point')
Future<Track?> extractAndCacheTrackWorker({
  required String filePath,
  required String cacheDirPath,
}) async {
  final file = File(filePath);
  if (!file.existsSync() && !await file.exists()) return null;

  int size = 0;
  int modifiedAt = 0;
  try {
    final stat = await file.stat();
    size = stat.size;
    modifiedAt = stat.modified.millisecondsSinceEpoch;
  } catch (_) {}

  try {
    final ext = p.extension(filePath).toLowerCase();
    final isSupportedByReader = supportedFileExtensions.contains(ext);

    AudioMetadata? metadata;
    if (!isSupportedByReader) {
      debugPrint(
        '[MetadataService] Extension "$ext" is not in audio_metadata_reader supportedFileExtensions. Using fallback metadata for: $filePath',
      );
    } else {
      try {
        metadata = readMetadata(file, getImage: true);
      } catch (e) {
        debugPrint(
          '[MetadataService] Error reading metadata with audio_metadata_reader for $filePath: $e. Using fallback metadata.',
        );
      }
    }

    // 2. Cache covers immediately if not already cached
    final coverCache = CoverCacheService(
      cacheDirectory: Directory(cacheDirPath),
    );
    if (!coverCache.hasCachedCover(filePath)) {
      try {
        await coverCache.saveCacheCover(
          filePath,
          artistName: metadata?.artist,
          albumName: metadata?.album,
          metadata: metadata,
        );
      } catch (_) {}
    }

    if (metadata != null) {
      return Track(
        filePath: filePath,
        title: metadata.title ?? p.basenameWithoutExtension(filePath),
        album: metadata.album,
        artist: metadata.artist,
        artists: metadata.performers,
        albumArtist: metadata.albumArtist,
        trackNumber: metadata.trackNumber,
        discNumber: metadata.discNumber,
        year: metadata.year?.year,
        durationMs: metadata.duration?.inMilliseconds ?? 0,
        bitrate: metadata.bitrate,
        sampleRate: metadata.sampleRate,
        channels: null,
        codec: null,
        fileSize: size,
        modifiedAt: modifiedAt,
        lyrics: metadata.lyrics,
        genres: metadata.genres,
      );
    }

    return _buildFallbackTrack(
      filePath: filePath,
      size: size,
      modifiedAt: modifiedAt,
    );
  } catch (e) {
    debugPrint(
      '[MetadataService] Unexpected error extracting metadata for $filePath: $e. Using fallback metadata.',
    );
    return _buildFallbackTrack(
      filePath: filePath,
      size: size,
      modifiedAt: modifiedAt,
    );
  }
}

/// Parses audio tags and metadata for a single file.
/// Backwards-compatible helper delegating to [extractAndCacheTrackWorker]
/// when [coverCacheService] is provided.
Future<Track?> extractTrackMetadata(
  String filePath, {
  CoverCacheService? coverCacheService,
  bool awaitCover = false,
}) async {
  if (coverCacheService != null) {
    return extractAndCacheTrackWorker(
      filePath: filePath,
      cacheDirPath: coverCacheService.cacheDirectory.path,
    );
  }

  final file = File(filePath);
  if (!file.existsSync() && !await file.exists()) return null;

  int size = 0;
  int modifiedAt = 0;
  try {
    final stat = await file.stat();
    size = stat.size;
    modifiedAt = stat.modified.millisecondsSinceEpoch;
  } catch (_) {}

  try {
    final ext = p.extension(filePath).toLowerCase();
    final isSupportedByReader = supportedFileExtensions.contains(ext);

    AudioMetadata? metadata;
    if (!isSupportedByReader) {
      debugPrint(
        '[MetadataService] Extension "$ext" is not in audio_metadata_reader supportedFileExtensions. Using fallback metadata for: $filePath',
      );
    } else {
      try {
        metadata = readMetadata(file, getImage: false);
      } catch (e) {
        debugPrint(
          '[MetadataService] Error reading metadata with audio_metadata_reader for $filePath: $e. Using fallback metadata.',
        );
      }
    }

    if (metadata != null) {
      return Track(
        filePath: filePath,
        title: metadata.title ?? p.basenameWithoutExtension(filePath),
        album: metadata.album,
        artist: metadata.artist,
        artists: metadata.performers,
        albumArtist: metadata.albumArtist,
        trackNumber: metadata.trackNumber,
        discNumber: metadata.discNumber,
        year: metadata.year?.year,
        durationMs: metadata.duration?.inMilliseconds ?? 0,
        bitrate: metadata.bitrate,
        sampleRate: metadata.sampleRate,
        channels: null,
        codec: null,
        fileSize: size,
        modifiedAt: modifiedAt,
        lyrics: metadata.lyrics,
        genres: metadata.genres,
      );
    }

    return _buildFallbackTrack(
      filePath: filePath,
      size: size,
      modifiedAt: modifiedAt,
    );
  } catch (e) {
    debugPrint(
      '[MetadataService] Unexpected error extracting metadata for $filePath: $e. Using fallback metadata.',
    );
    return _buildFallbackTrack(
      filePath: filePath,
      size: size,
      modifiedAt: modifiedAt,
    );
  }
}

/// Worker function that extracts artwork from file or folder using [CoverCacheService],
/// performs centered square crop (minDim x minDim), saves 100x100 LQ and max 1000x1000 HQ
/// in WebP format to disk, and returns the disk file paths. Never returns raw bytes.
@pragma('vm:entry-point')
Future<Map<String, String>?> extractAndSaveThumbnailWorker({
  required String filePath,
  required String cacheDirPath,
}) async {
  final file = File(filePath);
  if (!file.existsSync()) return null;

  final coverCache = CoverCacheService(cacheDirectory: Directory(cacheDirPath));
  final hqFile = await coverCache.saveCacheCover(filePath);
  if (hqFile != null && hqFile.existsSync() && hqFile.lengthSync() > 0) {
    final lqFile = coverCache.getCoverFile(
      filePath,
      quality: ThumbnailQuality.low,
    );
    return {'hq': hqFile.path, 'lq': lqFile.path};
  }
  return null;
}

// ---------------------------------------------------------------------------
// Local file discovery (runs on caller isolate; used by discoverFiles helper)
// ---------------------------------------------------------------------------

Stream<DiscoveredAudioFile> _discoverFilesLocal(
  List<String> directories, {
  CancellationToken? cancellationToken,
}) async* {
  final supportedSet = AppDefaults.supportedAudioExtensions
      .map((e) => e.toLowerCase().replaceAll('.', ''))
      .toSet();

  for (final dirPath in directories) {
    if (cancellationToken?.isCancelled ?? false) break;

    final dir = Directory(dirPath);
    if (!await dir.exists()) continue;

    Stream<FileSystemEntity> entityStream;
    try {
      entityStream = dir.list(recursive: true, followLinks: false);
    } catch (e) {
      debugPrint('[MetadataService] Unable to list directory $dirPath: $e');
      continue;
    }

    await for (final entity in entityStream.handleError((Object e) {
      debugPrint('[MetadataService] Error accessing filesystem entity: $e');
    })) {
      if (cancellationToken?.isCancelled ?? false) break;
      if (entity is! File) continue;

      final filename = p.basename(entity.path);
      if (filename.startsWith('.')) continue;

      final ext = p.extension(entity.path).toLowerCase().replaceAll('.', '');
      if (!supportedSet.contains(ext)) continue;

      try {
        final stat = await entity.stat();
        if (stat.size <= 0) continue;
        yield DiscoveredAudioFile(
          path: entity.path,
          size: stat.size,
          modifiedAt: stat.modified.millisecondsSinceEpoch,
        );
      } catch (_) {
        continue;
      }
    }
  }
}
