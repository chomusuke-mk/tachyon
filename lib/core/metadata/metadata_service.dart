import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:miniaudio_player/miniaudio_player.dart';
import 'package:path/path.dart' as p;
import 'package:tachyon/core/constants/app_defaults.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/metadata/domain/discovered_audio_file.dart';
import 'package:tachyon/core/metadata/domain/scan_progress.dart';
import 'package:tachyon/core/metadata/metadata_utils.dart';
import 'package:tachyon/core/store/library_store.dart';
import 'package:tachyon/shared/utils/memory_optimizer.dart';

export 'package:tachyon/core/metadata/domain/discovered_audio_file.dart';

/// Stored track metadata snapshot in RAM used during differential folder scanning.
typedef StoredTrackInfo = ({int id, String filePath, int modifiedAt});

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

/// Service responsible for metadata orchestration, single-file tag extraction,
/// thumbnail resolution, and full library scanning.
///
/// Reads existing track metadata and active thumbnail hashes in $O(1)$ from
/// [LibraryStore] in RAM and persists scan mutations to [AppDatabase].
class MetadataService {
  final AppDatabase database;
  final LibraryStore store;
  final int? customWorkerCount;

  MetadataService({
    required this.database,
    LibraryStore? store,
    this.customWorkerCount,
  }) : store = store ?? LibraryStore(database);

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

  /// Starts the scan pipeline using a pull-based pool of [Isolate] workers
  /// proportional to CPU cores and returns a [Stream<ScanProgress>].
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
  // Private: Background discovery & dynamic work-stealing Isolate pool
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
      sendProgress(
        const ScanProgress(stage: ScanStage.gettingDatabase),
        force: true,
      );

      sendProgress(
        const ScanProgress(stage: ScanStage.gettingTracks),
        force: true,
      );

      if (!store.isHydrated) {
        await store.reloadFromDatabase();
      }
      final trackStored = store.getStoredTracks();

      if (scanToken.isCancelled) {
        store.clearPendingDiscoveredTracks();
        sendProgress(
          const ScanProgress(stage: ScanStage.cancelled),
          force: true,
        );
        if (!controller.isClosed) controller.close();
        return;
      }

      sendProgress(
        const ScanProgress(stage: ScanStage.discovering),
        force: true,
      );

      final trackDiscover = await _discoverFilesInIsolate(
        directories,
        cancellationToken: scanToken,
      );

      if (scanToken.isCancelled) {
        store.clearPendingDiscoveredTracks();
        sendProgress(
          const ScanProgress(stage: ScanStage.cancelled),
          force: true,
        );
        if (!controller.isClosed) controller.close();
        return;
      }

      sendProgress(const ScanProgress(stage: ScanStage.comparing), force: true);

      final storedByPath = {for (final s in trackStored) s.filePath: s};
      final toExtract = <DiscoveredAudioFile>[];
      final newlyDiscovered = <DiscoveredAudioFile>[];
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
          newlyDiscovered.add(file);
        }
      }
      final toDeleteStored = toDeleteMap.values.toList();

      // Publish newly discovered files immediately so the user can browse and
      // start playback while background metadata extraction proceeds.
      if (newlyDiscovered.isNotEmpty || store.hasPendingDiscoveredTracks) {
        store.stageDiscoveredFiles(newlyDiscovered);
      }

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
        // Longest-Processing-Time-first ordering prevents tail stragglers when
        // large lossless tracks are mixed with short lossy files.
        toExtract.sort((a, b) => b.size.compareTo(a.size));

        final numWorkers = math.min(workerCount, totalExtract);
        final receivePort = ReceivePort();
        final exitPort = ReceivePort();
        final spawnedIsolates = <Isolate>[];
        final thumbnailsPath = MetadataUtils.thumbnailsDirectory?.path;
        final tempPath = MetadataUtils.tempDirectory?.path;

        final completer = Completer<void>();
        final remainingWorkers = List.generate(numWorkers, (i) => i).toSet();
        final workerPorts = <int, SendPort>{};
        int nextIndex = 0;
        bool poolClosed = false;

        void killWorkers() {
          poolClosed = true;
          for (final iso in spawnedIsolates) {
            iso.kill(priority: Isolate.immediate);
          }
          if (!completer.isCompleted) {
            completer.complete();
          }
        }

        void dispatchNextBatch(int workerIndex) {
          if (poolClosed || scanToken.isCancelled) return;
          final port = workerPorts[workerIndex];
          if (port == null) return;
          if (nextIndex >= totalExtract) {
            port.send(null);
            return;
          }
          final remaining = totalExtract - nextIndex;
          final take = math.min(
            4,
            math.max(1, (remaining / (numWorkers * 2)).ceil()),
          );
          final end = math.min(totalExtract, nextIndex + take);
          final slice = toExtract.sublist(nextIndex, end);
          nextIndex = end;
          port.send(slice);
        }

        scanToken.onCancel(killWorkers);

        try {
          RootIsolateToken? rootIsolateToken;
          try {
            rootIsolateToken = ServicesBinding.rootIsolateToken;
          } catch (_) {}

          for (int i = 0; i < numWorkers; i++) {
            if (scanToken.isCancelled) break;
            final config = _MetadataWorkerConfig(
              workerIndex: i,
              sendPort: receivePort.sendPort,
              thumbnailsPath: thumbnailsPath,
              tempPath: tempPath,
              rootIsolateToken: rootIsolateToken,
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

              if (message is _WorkerReady) {
                workerPorts[message.workerIndex] = message.workerSendPort;
                dispatchNextBatch(message.workerIndex);
              } else if (message is _WorkerTrackResult) {
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
              } else if (message is _WorkerBatchDone) {
                dispatchNextBatch(message.workerIndex);
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
          poolClosed = true;
          for (final iso in spawnedIsolates) {
            iso.kill(priority: Isolate.immediate);
          }
          exitPort.close();
          receivePort.close();
        }
      }

      if (scanToken.isCancelled) {
        store.clearPendingDiscoveredTracks();
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
        sendProgress(
          const ScanProgress(stage: ScanStage.inserting),
          force: true,
        );

        if (extractedTracks.isNotEmpty) {
          try {
            await database.upsertTracks(extractedTracks);
          } catch (e) {
            debugPrint('[MetadataService] upsertTracks error: $e');
          }
        }

        toExtract.clear();
        extractedTracks.clear();

        if (scanToken.isCancelled) {
          store.clearPendingDiscoveredTracks();
          sendProgress(
            const ScanProgress(stage: ScanStage.cancelled),
            force: true,
          );
          if (!controller.isClosed) controller.close();
          return;
        }

        sendProgress(
          const ScanProgress(stage: ScanStage.cleaningOrphans),
          force: true,
        );

        try {
          await database.deleteTracksAndPurgeOrphans(
            toDeleteStored.map((t) => t.id).toList(),
          );
        } catch (e) {
          debugPrint('[MetadataService] deleteTracksAndPurgeOrphans error: $e');
        }

        await store.reloadFromDatabase();

        if (scanToken.isCancelled) {
          sendProgress(
            const ScanProgress(stage: ScanStage.cancelled),
            force: true,
          );
          if (!controller.isClosed) controller.close();
          return;
        }

        sendProgress(
          const ScanProgress(stage: ScanStage.cleaningThumbnails),
          force: true,
        );

        try {
          final activeUris = store.getAllArtworkUris();
          final validHashes = <String>{};
          for (final u in activeUris) {
            final trimmed = u.trim();
            if (trimmed.isNotEmpty) {
              validHashes.add(p.basename(trimmed));
            }
          }

          final dir = MetadataUtils.thumbnailsDirectory;
          if (dir != null && await dir.exists()) {
            await for (final entity in dir.list(
              recursive: false,
              followLinks: false,
            )) {
              if (entity is File) {
                final fileName = p.basename(entity.path);
                if (!validHashes.contains(fileName)) {
                  try {
                    await entity.delete();
                  } catch (_) {}
                }
              }
            }
          }
        } catch (e) {
          debugPrint('[MetadataService] cleaningThumbnails error: $e');
        }
      } else {
        toExtract.clear();
        extractedTracks.clear();
        store.clearPendingDiscoveredTracks();
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
      store.clearPendingDiscoveredTracks();
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

Future<List<DiscoveredAudioFile>> _discoverFilesInIsolate(
  List<String> directories, {
  CancellationToken? cancellationToken,
}) async {
  if (directories.isEmpty || (cancellationToken?.isCancelled ?? false)) {
    return const <DiscoveredAudioFile>[];
  }

  final receivePort = ReceivePort();
  final exitPort = ReceivePort();
  final completer = Completer<List<DiscoveredAudioFile>>();
  Isolate? iso;

  void abortDiscovery() {
    iso?.kill(priority: Isolate.immediate);
    if (!completer.isCompleted) {
      completer.complete(const <DiscoveredAudioFile>[]);
    }
  }

  cancellationToken?.onCancel(abortDiscovery);

  try {
    iso = await Isolate.spawn(_discoveryIsolateEntryPoint, (
      directories: directories,
      sendPort: receivePort.sendPort,
    ));
    iso.addOnExitListener(exitPort.sendPort);

    if (cancellationToken?.isCancelled ?? false) {
      abortDiscovery();
      return await completer.future;
    }

    receivePort.listen((dynamic message) {
      if (!completer.isCompleted && message is List<DiscoveredAudioFile>) {
        completer.complete(message);
      }
    });

    exitPort.listen((_) {
      if (!completer.isCompleted) {
        completer.complete(const <DiscoveredAudioFile>[]);
      }
    });

    return await completer.future;
  } finally {
    iso?.kill(priority: Isolate.immediate);
    receivePort.close();
    exitPort.close();
  }
}

Future<void> _discoveryIsolateEntryPoint(
  ({List<String> directories, SendPort sendPort}) config,
) async {
  final results = <DiscoveredAudioFile>[];

  for (final dirPath in config.directories) {
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
        results.add(
          DiscoveredAudioFile(
            path: path,
            size: stat.size,
            modifiedAt: stat.modified.millisecondsSinceEpoch,
          ),
        );
      } catch (_) {
        continue;
      }
    }
  }

  config.sendPort.send(results);
}

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
        final stat = await entity.stat();
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

class _MetadataWorkerConfig {
  final int workerIndex;
  final SendPort sendPort;
  final String? thumbnailsPath;
  final String? tempPath;
  final RootIsolateToken? rootIsolateToken;

  const _MetadataWorkerConfig({
    required this.workerIndex,
    required this.sendPort,
    this.thumbnailsPath,
    this.tempPath,
    this.rootIsolateToken,
  });
}

sealed class _MetadataWorkerMessage {
  const _MetadataWorkerMessage();
}

class _WorkerReady extends _MetadataWorkerMessage {
  final int workerIndex;
  final SendPort workerSendPort;
  const _WorkerReady({required this.workerIndex, required this.workerSendPort});
}

class _WorkerTrackResult extends _MetadataWorkerMessage {
  final ExtractedTrackData? track;
  final String filePath;

  _WorkerTrackResult({required this.track, required this.filePath});
}

class _WorkerBatchDone extends _MetadataWorkerMessage {
  final int workerIndex;
  const _WorkerBatchDone({required this.workerIndex});
}

class _WorkerDone extends _MetadataWorkerMessage {
  final int workerIndex;
  const _WorkerDone({required this.workerIndex});
}

Future<void> _metadataWorkerEntryPoint(_MetadataWorkerConfig config) async {
  final workerReceivePort = ReceivePort();
  try {
    try {
      await MiniaudioPlayer.ensureInitialized(
        rootIsolateToken: config.rootIsolateToken,
      );
    } catch (e) {
      debugPrint('[MetadataService] Worker MiniaudioPlayer init warning: $e');
    }

    if (config.thumbnailsPath != null && config.tempPath != null) {
      MetadataUtils.init(config.thumbnailsPath!, config.tempPath!);
    }

    final savedCoverHashes = <String>{};
    config.sendPort.send(
      _WorkerReady(
        workerIndex: config.workerIndex,
        workerSendPort: workerReceivePort.sendPort,
      ),
    );

    await for (final dynamic batch in workerReceivePort) {
      if (batch == null) break;
      final items = (batch as List).cast<DiscoveredAudioFile>();
      for (final item in items) {
        ExtractedTrackData? track;
        try {
          track = await MetadataUtils.extractTrackMetadata(
            filePath: item.path,
            useSync: true,
            knownFileSize: item.size,
            knownModifiedAt: item.modifiedAt,
            knownSavedHashes: savedCoverHashes,
          );
        } catch (e, st) {
          debugPrint(
            '[MetadataService] Worker isolate failed for ${item.path}: $e',
          );
          debugPrint('[MetadataService] Stack trace: $st');
        }
        config.sendPort.send(
          _WorkerTrackResult(track: track, filePath: item.path),
        );
      }
      config.sendPort.send(_WorkerBatchDone(workerIndex: config.workerIndex));
    }
  } catch (e, st) {
    debugPrint('[MetadataService] Worker isolate fatal error: $e\n$st');
  } finally {
    workerReceivePort.close();
    config.sendPort.send(_WorkerDone(workerIndex: config.workerIndex));
  }
}
