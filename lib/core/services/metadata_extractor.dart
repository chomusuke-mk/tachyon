import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:tachyon/core/utils/platform_utils.dart';

import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/library/domain/scan_progress.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/core/services/cover_cache_service.dart';

import 'ffprobe_metadata_parser.dart';
import 'process_executor.dart';

/// Concurrency limiter implementing a bounded worker pool.
class ConcurrencyLimiter {
  final int maxConcurrent;
  int _activeCount = 0;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  ConcurrencyLimiter(this.maxConcurrent) {
    assert(maxConcurrent >= 1, 'maxConcurrent must be at least 1');
  }

  int get activeCount => _activeCount;

  Future<R> run<R>(Future<R> Function() operation) async {
    while (_activeCount >= maxConcurrent) {
      final completer = Completer<void>();
      _waiters.add(completer);
      await completer.future;
    }

    _activeCount++;
    try {
      return await operation();
    } finally {
      _activeCount--;
      if (_waiters.isNotEmpty) {
        _waiters.removeFirst().complete();
      }
    }
  }
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

/// Internal progress tracker with 20 Hz throttled stream dispatching.
class ThrottledProgressEmitter {
  final StreamController<ScanProgress> controller;
  final Stopwatch stopwatch = Stopwatch();
  ScanProgress _current = const ScanProgress();
  int _lastEmitTimestampMs = -minEmitIntervalMs;
  static const int minEmitIntervalMs =
      50; // 20 Hz throttle threshold (zero UI jank)

  ThrottledProgressEmitter(this.controller) {
    stopwatch.start();
  }

  ScanProgress get current => _current;

  void emit(ScanProgress progress, {bool force = false}) {
    _current = progress.copyWith(elapsedTime: stopwatch.elapsed);
    final now = stopwatch.elapsedMilliseconds;
    if (force || (now - _lastEmitTimestampMs) >= minEmitIntervalMs) {
      _lastEmitTimestampMs = now;
      if (!controller.isClosed) {
        controller.add(_current);
      }
    }
  }

  void close() {
    stopwatch.stop();
    if (!controller.isClosed) {
      controller.close();
    }
  }
}

/// High-level contract for library file scanning, metadata extraction,
/// and embedded cover art extraction.
abstract class MetadataExtractor {
  Future<Track?> extractMetadata(String filePath);

  Stream<ScanProgress> scanDirectories(
    List<String> directories, {
    CancellationToken? cancellationToken,
  });

  Future<String?> extractCoverArt(String filePath, String cacheDir);
}

/// Production implementation of [MetadataExtractor] with bounded isolate worker pool,
/// incremental change detection, 20 Hz UI progress throttle, and chunked DB commits.
class MetadataExtractorImpl implements MetadataExtractor {
  final AppDatabase database;
  final ProcessExecutor executor;
  final PlatformContext platform;
  final FfprobeMetadataParser parser;
  final CoverCacheService? coverCacheService;
  final int? customWorkerCount;

  MetadataExtractorImpl({
    required this.database,
    this.executor = const NativeProcessExecutor(),
    this.platform = const NativePlatformContext(),
    this.parser = const FfprobeMetadataParser(),
    this.coverCacheService,
    this.customWorkerCount,
  });

  int get workerCount =>
      customWorkerCount ?? (platform.numberOfProcessors ~/ 2).clamp(1, 8);

  @override
  Future<Track?> extractMetadata(String filePath) async {
    final file = File(filePath);
    if (!platform.fileExists(filePath) && !await file.exists()) {
      return null;
    }

    int size = 0;
    int modifiedAt = 0;
    try {
      final stat = await file.stat();
      size = stat.size;
      modifiedAt = stat.modified.millisecondsSinceEpoch;
    } catch (_) {}

    final ffprobePath = await PlatformUtils.resolveExecutable('ffprobe');
    return _extractSingleFile(
      ffprobePath,
      DiscoveredAudioFile(path: filePath, size: size, modifiedAt: modifiedAt),
    );
  }

  @override
  Stream<ScanProgress> scanDirectories(
    List<String> directories, {
    CancellationToken? cancellationToken,
  }) {
    final controller = StreamController<ScanProgress>();
    _runPipeline(directories, controller, cancellationToken);
    return controller.stream;
  }

  Future<void> _runPipeline(
    List<String> directories,
    StreamController<ScanProgress> controller,
    CancellationToken? cancellationToken,
  ) async {
    final emitter = ThrottledProgressEmitter(controller);

    try {
      final ffprobePath = await PlatformUtils.resolveExecutable('ffprobe');

      emitter.emit(
        const ScanProgress(phase: ScanPhase.discovering),
        force: true,
      );

      // 1. Snapshot existing tracks from SQLite for instant incremental lookup
      final existingMetaMap = await _loadExistingTrackMetas();

      // 2. Traversal & Discovery
      final discoveredFiles = <DiscoveredAudioFile>[];
      await for (final file in discoverFiles(
        directories,
        cancellationToken: cancellationToken,
      )) {
        if (cancellationToken?.isCancelled ?? false) break;
        discoveredFiles.add(file);
        emitter.emit(
          emitter.current.copyWith(
            phase: ScanPhase.discovering,
            totalFiles: discoveredFiles.length,
            currentFile: file.path,
          ),
        );
      }

      if (cancellationToken?.isCancelled ?? false) {
        emitter.emit(
          emitter.current.copyWith(phase: ScanPhase.cancelled),
          force: true,
        );
        emitter.close();
        return;
      }

      final totalFiles = discoveredFiles.length;
      int scannedCount = 0;
      int skippedCount = 0;
      int newCount = 0;
      int updatedCount = 0;
      int failedCount = 0;

      emitter.emit(
        emitter.current.copyWith(
          phase: ScanPhase.extracting,
          scannedFiles: 0,
          totalFiles: totalFiles,
          progress: 0.0,
        ),
        force: true,
      );

      // 3. Concurrency-bounded Worker Pool for Extraction
      final limiter = ConcurrencyLimiter(workerCount);
      final pendingInserts = <Track>[];
      final tasks = <Future<void>>[];

      for (final file in discoveredFiles) {
        if (cancellationToken?.isCancelled ?? false) break;

        final existing = existingMetaMap[file.path];

        // Incremental cache check: identical size and modification timestamp
        if (existing != null &&
            existing.fileSize == file.size &&
            existing.modifiedAt == file.modifiedAt) {
          scannedCount++;
          skippedCount++;
          emitter.emit(
            emitter.current.copyWith(
              phase: ScanPhase.extracting,
              scannedFiles: scannedCount,
              skippedTracks: skippedCount,
              progress: totalFiles > 0 ? scannedCount / totalFiles : 1.0,
              currentFile: file.path,
            ),
          );
          continue;
        }

        final isUpdate = existing != null;

        tasks.add(
          limiter.run(() async {
            if (cancellationToken?.isCancelled ?? false) return;

            final track = await _extractSingleFile(ffprobePath, file);
            scannedCount++;

            if (track != null) {
              pendingInserts.add(track);
              if (isUpdate) {
                updatedCount++;
              } else {
                newCount++;
              }
            } else {
              failedCount++;
            }

            emitter.emit(
              emitter.current.copyWith(
                phase: ScanPhase.extracting,
                scannedFiles: scannedCount,
                newTracks: newCount,
                updatedTracks: updatedCount,
                failedTracks: failedCount,
                skippedTracks: skippedCount,
                progress: totalFiles > 0 ? scannedCount / totalFiles : 1.0,
                currentFile: file.path,
              ),
            );

            // Flush batch if threshold reached
            if (pendingInserts.length >= 30) {
              final batch = List<Track>.from(pendingInserts);
              pendingInserts.clear();
              await _persistBatch(batch, emitter);
            }
          }),
        );
      }

      await Future.wait(tasks);

      if (cancellationToken?.isCancelled ?? false) {
        emitter.emit(
          emitter.current.copyWith(phase: ScanPhase.cancelled),
          force: true,
        );
        emitter.close();
        return;
      }

      // Flush any remaining tracks
      if (pendingInserts.isNotEmpty) {
        final remainingBatch = List<Track>.from(pendingInserts);
        pendingInserts.clear();
        await _persistBatch(remainingBatch, emitter);
      }

      // 4. Mark completion
      emitter.emit(
        emitter.current.copyWith(
          phase: ScanPhase.completed,
          scannedFiles: totalFiles,
          totalFiles: totalFiles,
          newTracks: newCount,
          updatedTracks: updatedCount,
          skippedTracks: skippedCount,
          failedTracks: failedCount,
          progress: 1.0,
          currentFile: null,
        ),
        force: true,
      );
    } catch (e, st) {
      debugPrint('Scan pipeline failed: $e\n$st');
      emitter.emit(
        emitter.current.copyWith(
          phase: ScanPhase.failed,
          errorMessage: e.toString(),
        ),
        force: true,
      );
    } finally {
      emitter.close();
    }
  }

  /// Traverses directories searching for supported audio files.
  Stream<DiscoveredAudioFile> discoverFiles(
    List<String> directories, {
    CancellationToken? cancellationToken,
  }) async* {
    final supportedSet = [
      'mp3',
      'flac',
      'wav',
      'aac',
      'ogg',
      'm4a',
      'mka',
      'opus',
    ].map((e) => e.toLowerCase().replaceAll('.', '')).toSet();

    for (final dirPath in directories) {
      if (cancellationToken?.isCancelled ?? false) break;

      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;

      Stream<FileSystemEntity> entityStream;
      try {
        entityStream = dir.list(recursive: true, followLinks: false);
      } catch (e) {
        debugPrint('Warning: Unable to list directory $dirPath: $e');
        continue;
      }

      await for (final entity in entityStream.handleError((e) {
        debugPrint('Error accessing filesystem entity: $e');
      })) {
        if (cancellationToken?.isCancelled ?? false) break;

        if (entity is! File) continue;

        // Ignore hidden files / directories (e.g. .git, .thumbnails)
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

  Future<Track?> _extractSingleFile(
    String ffprobePath,
    DiscoveredAudioFile file,
  ) async {
    try {
      final result = await executor
          .run(ffprobePath, [
            '-v',
            'quiet',
            '-print_format',
            'json',
            '-show_format',
            '-show_streams',
            file.path,
          ])
          .timeout(const Duration(seconds: 15));

      if (result.exitCode != 0) {
        debugPrint(
          'ffprobe exited with code ${result.exitCode} for ${file.path}',
        );
        return null;
      }

      final jsonStr = result.stdout.toString();
      return parser.parse(
        jsonString: jsonStr,
        filePath: file.path,
        fileSize: file.size,
        modifiedAt: file.modifiedAt,
      );
    } catch (e) {
      debugPrint('Metadata extraction failed for ${file.path}: $e');
      return null;
    }
  }

  Future<void> _persistBatch(
    List<Track> batch,
    ThrottledProgressEmitter emitter,
  ) async {
    emitter.emit(
      emitter.current.copyWith(phase: ScanPhase.persisting),
      force: true,
    );
    await database.batchInsertTracks(batch);
    // Yield to event loop between transactions to prevent UI starving
    await Future.delayed(Duration.zero);
    emitter.emit(
      emitter.current.copyWith(phase: ScanPhase.extracting),
      force: true,
    );
  }

  Future<Map<String, ({int fileSize, int modifiedAt})>>
  _loadExistingTrackMetas() async {
    try {
      final rows = await database.database.rawQuery(
        'SELECT uri, file_size, modified_at FROM tracks;',
      );
      final map = <String, ({int fileSize, int modifiedAt})>{};
      for (final r in rows) {
        final uri = r['uri'] as String;
        final size = r['file_size'] as int;
        final modified = r['modified_at'] as int;
        map[uri] = (fileSize: size, modifiedAt: modified);
      }
      return map;
    } catch (e) {
      debugPrint('Warning: Could not pre-query existing track metadata: $e');
      return {};
    }
  }

  @override
  Future<String?> extractCoverArt(String filePath, String cacheDir) async {
    final service =
        coverCacheService ??
        CoverCacheServiceImpl(
          cacheDirectory: Directory(cacheDir),
          executor: executor,
        );

    final file = await service.extractAndCacheCover(
      filePath,
      hasAttachedPic: true,
    );
    return file?.path;
  }
}
