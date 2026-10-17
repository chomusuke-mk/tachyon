import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:tachyon/core/constants/app_defaults.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/library/domain/scan_progress.dart';
import 'package:tachyon/shared/utils/memory_optimizer.dart';
import 'package:tachyon/shared/utils/metadata_utils.dart';

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

class _QueuedScan {
  final List<String> directories;
  final StreamController<ScanProgress> controller;
  final CancellationToken? cancellationToken;

  const _QueuedScan({
    required this.directories,
    required this.controller,
    this.cancellationToken,
  });
}

/// Service running in the Core Backend Host Isolate responsible for metadata
/// orchestration, single-file tag extraction, thumbnail resolution, and full library scanning.
///
/// Follows a high-performance Cache-First & Isolate worker pool strategy:
/// 1. Queries database or disk cache first (immediate return, 0 CPU).
/// 2. If missing, delegates extraction to dedicated worker isolates.
/// 3. Runs multi-file directory scans using a concurrent pool of [Isolate] workers
///    scaled to the number of CPU processors ([Platform.numberOfProcessors]).
/// 4. In each worker, extracts metadata and saves triple-quality (LQ, MQ, HQ) covers
///    to disk in a single pass.
/// 5. Workers write files directly to disk and return pure Dart models.
///    Zero raw byte buffers are passed between isolates.
class MetadataService {
  final AppDatabase database;
  final int? customWorkerCount;

  MetadataService({required this.database, this.customWorkerCount});

  int get workerCount =>
      customWorkerCount ?? math.max(1, Platform.numberOfProcessors);

  CancellationToken? _currentScanToken;

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

  final List<_QueuedScan> _scanQueue = [];
  final StreamController<ScanProgress> _progressController =
      StreamController<ScanProgress>.broadcast();

  /// Stream of all scan progress events across all running and queued scans.
  Stream<ScanProgress> get progressStream => _progressController.stream;

  /// Whether a scan is currently running.
  bool get isScanning =>
      _currentScanToken != null && !_currentScanToken!.isCancelled;

  /// Starts the scan pipeline using a pool of [Isolate] workers proportional
  /// to CPU cores and returns a [Stream<ScanProgress>].
  ///
  /// If a scan is already running, the request is queued and executed
  /// automatically once the active scan completes.
  Stream<ScanProgress> scanDirectories(
    List<String> directories, {
    CancellationToken? cancellationToken,
  }) {
    final controller = StreamController<ScanProgress>();
    if (isScanning) {
      final queued = _QueuedScan(
        directories: directories,
        controller: controller,
        cancellationToken: cancellationToken,
      );
      _scanQueue.add(queued);
      controller.onCancel = () {
        _scanQueue.remove(queued);
      };
      return controller.stream;
    }
    _runScanPipeline(directories, controller, cancellationToken);
    return controller.stream;
  }

  /// Cancels any active library scan and cancels all queued scan requests.
  void cancelScan() {
    _currentScanToken?.cancel();
    _currentScanToken = null;
    for (final item in _scanQueue) {
      if (!item.controller.isClosed) {
        item.controller.add(const ScanProgress(stage: ScanStage.cancelled));
        item.controller.close();
      }
    }
    _scanQueue.clear();
    if (!_progressController.isClosed) {
      _progressController.add(const ScanProgress(stage: ScanStage.cancelled));
    }
  }

  /// Disposes resources, cancels any pending or active scans, and closes the progress stream.
  void dispose() {
    cancelScan();
    _progressController.close();
  }

  void _processNextQueuedScan() {
    if (_scanQueue.isEmpty) return;
    while (_scanQueue.isNotEmpty) {
      final next = _scanQueue.removeAt(0);
      if (next.cancellationToken?.isCancelled == true) {
        if (!next.controller.isClosed) {
          next.controller.add(const ScanProgress(stage: ScanStage.cancelled));
          next.controller.close();
        }
        continue;
      }
      _runScanPipeline(
        next.directories,
        next.controller,
        next.cancellationToken,
      );
      break;
    }
  }

  // ---------------------------------------------------------------------------
  // Private: Isolate pool orchestration
  // ---------------------------------------------------------------------------

  Future<void> _runScanPipeline(
    List<String> directories,
    StreamController<ScanProgress> controller,
    CancellationToken? cancellationToken,
  ) async {
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
      if (_currentScanToken == scanToken) {
        _currentScanToken = null;
      }
      if (!controller.isClosed) {
        controller.add(const ScanProgress(stage: ScanStage.cancelled));
        controller.close();
      }
      if (!_progressController.isClosed) {
        _progressController.add(const ScanProgress(stage: ScanStage.cancelled));
      }
      return;
    }

    final stopwatch = Stopwatch()..start();
    ScanProgress current = const ScanProgress();
    int lastEmitMs = -50;

    void sendProgress(ScanProgress p, {bool force = false}) {
      current = p;
      final now = stopwatch.elapsedMilliseconds;
      if (force || now - lastEmitMs >= 50) {
        lastEmitMs = now;
        if (!controller.isClosed) controller.add(current);
        if (!_progressController.isClosed) _progressController.add(current);
      }
    }

    try {
      // Estado inicial: Obteniendo base de datos...
      sendProgress(
        const ScanProgress(stage: ScanStage.gettingDatabase),
        force: true,
      );

      // Etapa 1: Obteniendo canciones... (desde base de datos)
      sendProgress(
        const ScanProgress(stage: ScanStage.gettingTracks),
        force: true,
      );

      final trackStored = database.getStoredTracks();

      if (scanToken.isCancelled) {
        sendProgress(
          const ScanProgress(stage: ScanStage.cancelled),
          force: true,
        );
        if (!controller.isClosed) controller.close();
        return;
      }

      // Etapa 2: Buscando archivos...
      sendProgress(
        const ScanProgress(stage: ScanStage.discovering),
        force: true,
      );

      final trackDiscover = <DiscoveredAudioFile>[];
      await for (final file in _discoverFilesLocal(
        directories,
        cancellationToken: scanToken,
      )) {
        if (scanToken.isCancelled) break;
        trackDiscover.add(file);
      }

      if (scanToken.isCancelled) {
        sendProgress(
          const ScanProgress(stage: ScanStage.cancelled),
          force: true,
        );
        if (!controller.isClosed) controller.close();
        return;
      }

      // Etapa 3: Comparando...
      sendProgress(const ScanProgress(stage: ScanStage.comparing), force: true);

      final storedByPath = {for (final s in trackStored) s.filePath: s};
      final toExtract = <DiscoveredAudioFile>[];
      final toDeleteMap = Map<String, StoredTrackInfo>.from(storedByPath);

      for (final file in trackDiscover) {
        final stored = storedByPath[file.path];
        if (stored != null) {
          if (stored.modifiedAt == file.modifiedAt) {
            toDeleteMap.remove(file.path);
          } else {
            toExtract.add(file);
          }
        } else {
          toExtract.add(file);
        }
      }
      final toDeleteStored = toDeleteMap.values.toList();

      // Etapa 4: Obteniendo metadatos completos de cada trackDiscover
      final totalExtract = toExtract.length;
      final extractedTracks = <ExtractedTrackData>[];
      int extractedCount = 0;

      sendProgress(
        ScanProgress(
          stage: ScanStage.extracting,
          progressLabel: '0/$totalExtract',
          progressValue: totalExtract == 0 ? 1.0 : 0.0,
        ),
        force: true,
      );

      if (totalExtract > 0 && !scanToken.isCancelled) {
        final numWorkers = math.min(workerCount, totalExtract);
        final fileChunks = List.generate(numWorkers, (_) => <String>[]);
        for (int i = 0; i < totalExtract; i++) {
          fileChunks[i % numWorkers].add(toExtract[i].path);
        }

        final receivePort = ReceivePort();
        final exitPort = ReceivePort();
        final spawnedIsolates = <Isolate>[];
        final thumbnailsPath = MetadataUtils.thumbnailsDirectory?.path;
        final tempPath = MetadataUtils.tempDirectory?.path;

        final completer = Completer<void>();
        final remainingWorkers = List.generate(numWorkers, (i) => i).toSet();

        void killWorkers() {
          for (final iso in spawnedIsolates) {
            iso.kill(priority: Isolate.immediate);
          }
          if (!completer.isCompleted) {
            completer.complete();
          }
        }

        scanToken.onCancel(killWorkers);

        try {
          for (int i = 0; i < numWorkers; i++) {
            if (scanToken.isCancelled) break;
            final config = _MetadataWorkerConfig(
              workerIndex: i,
              sendPort: receivePort.sendPort,
              filePaths: fileChunks[i],
              thumbnailsPath: thumbnailsPath,
              tempPath: tempPath,
            );
            final isolate = await Isolate.spawn(
              _metadataWorkerEntryPoint,
              config,
            );
            isolate.addOnExitListener(exitPort.sendPort, response: i);
            spawnedIsolates.add(isolate);
          }

          if (scanToken.isCancelled) {
            killWorkers();
          } else {
            exitPort.listen((dynamic workerIndex) {
              if (workerIndex is int && remainingWorkers.remove(workerIndex)) {
                if (remainingWorkers.isEmpty && !completer.isCompleted) {
                  completer.complete();
                }
              }
            });

            receivePort.listen((dynamic message) {
              if (scanToken.isCancelled) {
                killWorkers();
                return;
              }

              if (message is _WorkerTrackResult) {
                extractedCount++;
                if (message.track != null) {
                  extractedTracks.add(message.track!);
                }
                final progressVal = totalExtract > 0
                    ? extractedCount / totalExtract
                    : 1.0;
                sendProgress(
                  ScanProgress(
                    stage: ScanStage.extracting,
                    progressLabel: '$extractedCount/$totalExtract',
                    progressValue: progressVal,
                  ),
                );
              } else if (message is _WorkerDone) {
                remainingWorkers.remove(message.workerIndex);
                if (remainingWorkers.isEmpty && !completer.isCompleted) {
                  completer.complete();
                }
              }
            });

            await completer.future;

            if (!scanToken.isCancelled) {
              final finalVal = totalExtract > 0
                  ? extractedCount / totalExtract
                  : 1.0;
              sendProgress(
                ScanProgress(
                  stage: ScanStage.extracting,
                  progressLabel: '$extractedCount/$totalExtract',
                  progressValue: finalVal,
                ),
                force: true,
              );
            }
          }
        } finally {
          for (final iso in spawnedIsolates) {
            iso.kill(priority: Isolate.immediate);
          }
          exitPort.close();
          receivePort.close();
        }
      }

      if (scanToken.isCancelled) {
        sendProgress(
          const ScanProgress(stage: ScanStage.cancelled),
          force: true,
        );
        if (!controller.isClosed) controller.close();
        return;
      }

      final hasMutations =
          extractedTracks.isNotEmpty || toDeleteStored.isNotEmpty;

      if (hasMutations) {
        // Etapa 5: Insertando...
        sendProgress(
          const ScanProgress(stage: ScanStage.inserting),
          force: true,
        );

        if (extractedTracks.isNotEmpty) {
          try {
            database.upsertTracks(extractedTracks);
          } catch (e) {
            debugPrint('[MetadataService] upsertTracks error: $e');
          }
        }

        // Liberar memoria inmediatamente
        toExtract.clear();
        extractedTracks.clear();

        if (scanToken.isCancelled) {
          sendProgress(
            const ScanProgress(stage: ScanStage.cancelled),
            force: true,
          );
          if (!controller.isClosed) controller.close();
          return;
        }

        // Etapa 6: Limpiando orphan...
        sendProgress(
          const ScanProgress(stage: ScanStage.cleaningOrphans),
          force: true,
        );

        try {
          database.deleteTracksAndPurgeOrphans(
            toDeleteStored.map((t) => t.id).toList(),
          );
        } catch (e) {
          debugPrint('[MetadataService] deleteTracksAndPurgeOrphans error: $e');
        }

        if (scanToken.isCancelled) {
          sendProgress(
            const ScanProgress(stage: ScanStage.cancelled),
            force: true,
          );
          if (!controller.isClosed) controller.close();
          return;
        }

        // Etapa 7: Limpiando thumbnails...
        sendProgress(
          const ScanProgress(stage: ScanStage.cleaningThumbnails),
          force: true,
        );

        try {
          final activeHashes = database.getAllThumbnailHashes();

          final coverFiles = MetadataUtils.listCachedCoverFiles();

          final validHashes = activeHashes
              .where((h) => h.trim().isNotEmpty)
              .toSet();

          final orphanedFiles = <File>[];
          for (final file in coverFiles) {
            final hash = MetadataUtils.extractHashFromThumbnailPath(file.path);
            if (!validHashes.contains(hash)) {
              orphanedFiles.add(file);
            }
          }

          for (final file in orphanedFiles) {
            try {
              file.deleteSync();
            } catch (_) {}
          }
        } catch (e) {
          debugPrint('[MetadataService] cleaningThumbnails error: $e');
        }
      } else {
        toExtract.clear();
        extractedTracks.clear();
      }

      sendProgress(
        ScanProgress(
          stage: ScanStage.completed,
          progressLabel: '$extractedCount/$totalExtract',
          progressValue: 1.0,
          catalogModified: hasMutations,
        ),
        force: true,
      );
      if (!controller.isClosed) controller.close();
    } catch (e, st) {
      debugPrint('[MetadataService] Pipeline failed: $e\n$st');
      sendProgress(
        ScanProgress(stage: ScanStage.failed, errorMessage: e.toString()),
        force: true,
      );
      if (!controller.isClosed) controller.close();
    } finally {
      stopwatch.stop();
      if (_currentScanToken == scanToken) {
        _currentScanToken = null;
      }
      await MetadataUtils.clearTempDirectory();
      MemoryOptimizer.trim();
      _processNextQueuedScan();
    }
  }
}

// ---------------------------------------------------------------------------
// Stream of discovered audio files from local directories
// ---------------------------------------------------------------------------

Stream<DiscoveredAudioFile> _discoverFilesLocal(
  List<String> directories, {
  CancellationToken? cancellationToken,
}) async* {
  await Future<void>.delayed(Duration.zero);
  int processedSinceYield = 0;

  for (final dirPath in directories) {
    if (cancellationToken?.isCancelled ?? false) break;

    final dir = Directory(dirPath);
    if (!dir.existsSync()) continue;

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

      final path = entity.path;
      final filename = p.basename(path);
      if (filename.startsWith('.')) continue;

      final dotIndex = filename.lastIndexOf('.');
      if (dotIndex <= 0 || dotIndex == filename.length - 1) continue;
      final ext = filename.substring(dotIndex + 1).toLowerCase();
      if (!AppDefaults.supportedAudioExtensions.contains(ext)) continue;

      try {
        final stat = entity.statSync();
        if (stat.size <= 0) continue;
        yield DiscoveredAudioFile(
          path: path,
          size: stat.size,
          modifiedAt: stat.modified.millisecondsSinceEpoch,
        );
      } catch (_) {
        continue;
      }

      processedSinceYield++;
      if (processedSinceYield >= 64) {
        processedSinceYield = 0;
        await Future<void>.delayed(Duration.zero);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Worker Isolate Pool for Parallel Metadata Extraction
// ---------------------------------------------------------------------------

class _MetadataWorkerConfig {
  final int workerIndex;
  final SendPort sendPort;
  final List<String> filePaths;
  final String? thumbnailsPath;
  final String? tempPath;

  const _MetadataWorkerConfig({
    required this.workerIndex,
    required this.sendPort,
    required this.filePaths,
    this.thumbnailsPath,
    this.tempPath,
  });
}

sealed class _MetadataWorkerMessage {
  const _MetadataWorkerMessage();
}

class _WorkerTrackResult extends _MetadataWorkerMessage {
  final ExtractedTrackData? track;
  final String filePath;

  _WorkerTrackResult({required this.track, required this.filePath});
}

class _WorkerDone extends _MetadataWorkerMessage {
  final int workerIndex;
  const _WorkerDone({required this.workerIndex});
}

void _metadataWorkerEntryPoint(_MetadataWorkerConfig config) async {
  try {
    if (config.thumbnailsPath != null && config.tempPath != null) {
      MetadataUtils.init(config.thumbnailsPath!, config.tempPath!);
    }

    for (final filePath in config.filePaths) {
      ExtractedTrackData? track;
      try {
        track = await MetadataUtils.extractTrackMetadata(
          filePath: filePath,
          useSync: true,
        );
      } catch (e, st) {
        debugPrint('[MetadataService] Worker isolate failed for $filePath: $e');
        debugPrint('[MetadataService] Stack trace: $st');
      }
      config.sendPort.send(
        _WorkerTrackResult(track: track, filePath: filePath),
      );
    }
  } catch (e, st) {
    debugPrint('[MetadataService] Worker isolate fatal error: $e\n$st');
  } finally {
    config.sendPort.send(_WorkerDone(workerIndex: config.workerIndex));
  }
}
