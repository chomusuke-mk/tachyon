import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:haudiotagger/haudiotagger.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/constants/app_defaults.dart';
import 'package:tachyon/core/backend/services/cover_cache_service.dart';
import 'package:tachyon/features/library/domain/scan_progress.dart';

/// Track metadata snapshot used to detect unchanged files during incremental scanning.
typedef TrackFileMeta = ({int modifiedAt, int fileSize});

/// Pure metadata extraction DTO. Workers extract tags into this DTO
/// and pass it to [AppDatabase.upsertTracks] for atomic persistence.
class ExtractedTrackData {
  final String filePath;
  final String title;
  final List<String> artistNames;
  final String? albumArtistName;
  final String? albumName;
  final int? trackNumber;
  final int? discNumber;
  final int? year;
  final int durationMs;
  final int? bitrate;
  final int? sampleRate;
  final int? channels;
  final String? codec;
  final int fileSize;
  final int modifiedAt;
  final double? replayGainTrackGain;
  final double? replayGainTrackPeak;
  final List<String> genreNames;
  final String? embeddedLyrics;

  const ExtractedTrackData({
    required this.filePath,
    required this.title,
    this.artistNames = const [],
    this.albumArtistName,
    this.albumName,
    this.trackNumber,
    this.discNumber = 1,
    this.year,
    required this.durationMs,
    this.bitrate,
    this.sampleRate,
    this.channels,
    this.codec,
    required this.fileSize,
    required this.modifiedAt,
    this.replayGainTrackGain,
    this.replayGainTrackPeak,
    this.genreNames = const [],
    this.embeddedLyrics,
  });
}

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

  static Future<ExtractedTrackData?> _runWorkerInIsolate(
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
  Future<ExtractedTrackData?> extractMetadata(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync() && !await file.exists()) return null;

    final cachePath = coverCacheService.cacheDirectory.path;
    return await _runWorkerInIsolate(filePath, cachePath);
  }

  /// Retrieves metadata for a file following a Cache-First strategy:
  /// Extracts via a worker isolate using [Isolate.run], persists into SQLite DB
  /// using [AppDatabase.upsertTracks], and returns the extracted data.
  Future<ExtractedTrackData?> getMetadata(String filePath) async {
    final track = await extractMetadata(filePath);
    if (track != null) {
      database.upsertTracks([track]);
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
      database.updateTrackCoverStatus(filePath, true);
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
        existingMetas = database.getExistingTrackMetas();
      } catch (e) {
        debugPrint('[MetadataService] Failed to load existing track metas: $e');
      }

      // 3. Concurrency-bounded extraction with Isolate.run pool
      final pendingTracks = <ExtractedTrackData>[];
      final activeTasks = <Future<void>>{};
      final poolSize = workerCount;
      final cacheDirPath = coverCacheService.cacheDirectory.path;

      Future<void> maybeInsertBatch({bool force = false}) async {
        if (pendingTracks.length >= 30 || (force && pendingTracks.isNotEmpty)) {
          final batch = List<ExtractedTrackData>.from(pendingTracks);
          pendingTracks.clear();
          sendProgress(
            current.copyWith(phase: ScanPhase.persisting),
            force: true,
          );
          try {
            database.upsertTracks(batch);
          } catch (e) {
            debugPrint('[MetadataService] upsertTracks error: $e');
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
          ExtractedTrackData? track;
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

double? _parseReplayGain(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  final str = value.toString().replaceAll(RegExp(r'[^0-9.-]'), '');
  return double.tryParse(str);
}

/// Helper to construct a fallback [ExtractedTrackData] when metadata cannot be read.
ExtractedTrackData _buildFallbackTrackData({
  required String filePath,
  required int size,
  required int modifiedAt,
}) {
  final extClean = p.extension(filePath).replaceAll('.', '').toUpperCase();
  return ExtractedTrackData(
    filePath: filePath,
    title: p.basenameWithoutExtension(filePath),
    durationMs: 0,
    codec: extClean.isNotEmpty ? extClean : null,
    fileSize: size,
    modifiedAt: modifiedAt,
  );
}

/// Worker function that runs in a dedicated isolate via [Isolate.run].
/// In a single pass:
/// 1. Reads file metadata (or falls back if format unsupported or parsing fails).
/// 2. If present, generates dual-quality HQ & LQ covers and writes them to disk.
/// 3. Returns the populated [ExtractedTrackData] directly.
///
/// Passes zero raw byte arrays across the isolate boundary.
@pragma('vm:entry-point')
Future<ExtractedTrackData?> extractAndCacheTrackWorker({
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
    final isSupportedByReader = CoverCacheService.supportedTagExtensions
        .contains(ext);

    Tag? tag;
    AudioProperties? properties;
    if (!isSupportedByReader) {
      debugPrint(
        '[MetadataService] Extension "$ext" is not in haudiotagger supported extensions. Using fallback metadata for: $filePath',
      );
    } else {
      try {
        tag = await Haudiotagger.read(filePath);
      } catch (e) {
        debugPrint(
          '[MetadataService] Error reading metadata with haudiotagger for $filePath: $e. Using fallback metadata.',
        );
      }
      try {
        properties = await Haudiotagger.readProperties(filePath);
      } catch (_) {}
    }

    // 2. Cache covers immediately if not already cached
    final coverCache = CoverCacheService(
      cacheDirectory: Directory(cacheDirPath),
    );
    if (!coverCache.hasCachedCover(filePath)) {
      try {
        await coverCache.saveCacheCover(
          filePath,
          artistName: tag?.trackArtist ?? tag?.albumArtist,
          albumName: tag?.album,
          tag: tag,
        );
      } catch (_) {}
    }

    if (tag != null) {
      final durationMs = properties?.durationMicros != null
          ? (properties!.durationMicros!.toInt() / 1000).round()
          : (tag.duration != null ? tag.duration! * 1000 : 0);

      final artists = <String>[];
      if (tag.trackArtist != null && tag.trackArtist!.isNotEmpty) {
        artists.addAll(tag.trackArtist!.split(', ').map((e) => e.trim()).where((e) => e.isNotEmpty));
      } else if (tag.albumArtist != null && tag.albumArtist!.isNotEmpty) {
        artists.addAll(tag.albumArtist!.split(', ').map((e) => e.trim()).where((e) => e.isNotEmpty));
      }

      final genres = <String>[];
      if (tag.genre != null && tag.genre!.trim().isNotEmpty) {
        genres.add(tag.genre!.trim());
      }

      return ExtractedTrackData(
        filePath: filePath,
        title: tag.title ?? p.basenameWithoutExtension(filePath),
        albumName: tag.album,
        artistNames: artists,
        albumArtistName: tag.albumArtist,
        genreNames: genres,
        trackNumber: tag.trackNumber,
        discNumber: tag.discNumber,
        year: tag.year,
        durationMs: durationMs,
        bitrate: properties?.bitrate,
        sampleRate: properties?.sampleRate,
        channels: properties?.channels,
        codec: properties?.codec ?? (ext.replaceAll('.', '').toUpperCase()),
        fileSize: size,
        modifiedAt: modifiedAt,
        embeddedLyrics: tag.lyrics,
        replayGainTrackGain: _parseReplayGain(tag.replayGainTrackGain),
        replayGainTrackPeak: _parseReplayGain(tag.replayGainTrackPeak),
      );
    }

    if (properties != null) {
      final durationMs = properties.durationMicros != null
          ? (properties.durationMicros!.toInt() / 1000).round()
          : 0;

      return ExtractedTrackData(
        filePath: filePath,
        title: p.basenameWithoutExtension(filePath),
        durationMs: durationMs,
        bitrate: properties.bitrate,
        sampleRate: properties.sampleRate,
        channels: properties.channels,
        codec: properties.codec,
        fileSize: size,
        modifiedAt: modifiedAt,
      );
    }

    return _buildFallbackTrackData(
      filePath: filePath,
      size: size,
      modifiedAt: modifiedAt,
    );
  } catch (e) {
    debugPrint(
      '[MetadataService] Unexpected error extracting metadata for $filePath: $e. Using fallback metadata.',
    );
    return _buildFallbackTrackData(
      filePath: filePath,
      size: size,
      modifiedAt: modifiedAt,
    );
  }
}

/// Parses audio tags and metadata for a single file.
Future<ExtractedTrackData?> extractTrackMetadata(
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
    final isSupportedByReader = CoverCacheService.supportedTagExtensions
        .contains(ext);

    Tag? tag;
    AudioProperties? properties;
    if (!isSupportedByReader) {
      debugPrint(
        '[MetadataService] Extension "$ext" is not in haudiotagger supported extensions. Using fallback metadata for: $filePath',
      );
    } else {
      try {
        tag = await Haudiotagger.read(filePath);
      } catch (e) {
        debugPrint(
          '[MetadataService] Error reading metadata with haudiotagger for $filePath: $e. Using fallback metadata.',
        );
      }
      try {
        properties = await Haudiotagger.readProperties(filePath);
      } catch (_) {}
    }

    if (tag != null) {
      final durationMs = properties?.durationMicros != null
          ? (properties!.durationMicros!.toInt() / 1000).round()
          : (tag.duration != null ? tag.duration! * 1000 : 0);

      final artists = <String>[];
      if (tag.trackArtist != null && tag.trackArtist!.isNotEmpty) {
        artists.addAll(tag.trackArtist!.split(', ').map((e) => e.trim()).where((e) => e.isNotEmpty));
      } else if (tag.albumArtist != null && tag.albumArtist!.isNotEmpty) {
        artists.addAll(tag.albumArtist!.split(', ').map((e) => e.trim()).where((e) => e.isNotEmpty));
      }

      final genres = <String>[];
      if (tag.genre != null && tag.genre!.trim().isNotEmpty) {
        genres.add(tag.genre!.trim());
      }

      return ExtractedTrackData(
        filePath: filePath,
        title: tag.title ?? p.basenameWithoutExtension(filePath),
        albumName: tag.album,
        artistNames: artists,
        albumArtistName: tag.albumArtist,
        genreNames: genres,
        trackNumber: tag.trackNumber,
        discNumber: tag.discNumber,
        year: tag.year,
        durationMs: durationMs,
        bitrate: properties?.bitrate,
        sampleRate: properties?.sampleRate,
        channels: properties?.channels,
        codec: properties?.codec ?? (ext.replaceAll('.', '').toUpperCase()),
        fileSize: size,
        modifiedAt: modifiedAt,
        embeddedLyrics: tag.lyrics,
        replayGainTrackGain: _parseReplayGain(tag.replayGainTrackGain),
        replayGainTrackPeak: _parseReplayGain(tag.replayGainTrackPeak),
      );
    }

    if (properties != null) {
      final durationMs = properties.durationMicros != null
          ? (properties.durationMicros!.toInt() / 1000).round()
          : 0;

      return ExtractedTrackData(
        filePath: filePath,
        title: p.basenameWithoutExtension(filePath),
        durationMs: durationMs,
        bitrate: properties.bitrate,
        sampleRate: properties.sampleRate,
        channels: properties.channels,
        codec: properties.codec,
        fileSize: size,
        modifiedAt: modifiedAt,
      );
    }

    return _buildFallbackTrackData(
      filePath: filePath,
      size: size,
      modifiedAt: modifiedAt,
    );
  } catch (e) {
    debugPrint(
      '[MetadataService] Unexpected error extracting metadata for $filePath: $e. Using fallback metadata.',
    );
    return _buildFallbackTrackData(
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
