import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:tachyon/core/constants/app_defaults.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/metadata/domain/discovered_audio_file.dart';
import 'package:tachyon/core/metadata/domain/scan_progress.dart';
import 'package:tachyon/core/metadata/metadata_utils.dart';
import 'package:tachyon/core/storage/persistent_binary_storage.dart';
import 'package:tachyon/core/store/library_store.dart';
import 'package:tachyon/shared/utils/memory_optimizer.dart';

export 'package:tachyon/core/metadata/domain/discovered_audio_file.dart';

/// Stored track metadata snapshot in RAM used during differential folder scanning.
typedef StoredTrackInfo = ({int id, String filePath, int modifiedAt});

class _QueuedScan {
  final List<String> directories;
  final List<String> files;
  final StreamController<ScanProgress> controller;
  final CancellationToken? cancellationToken;

  const _QueuedScan({
    required this.directories,
    required this.files,
    required this.controller,
    this.cancellationToken,
  });
}

/// Service responsible for metadata orchestration, single-file tag extraction,
/// thumbnail resolution, and full library scanning (directories + individual files/links).
///
/// Uses a bounded asynchronous worker pool (`workerCount` concurrent async futures)
/// delegating heavy analysis to `miniaudio_player`'s native Rust worker thread pool
/// or Web Worker, without spawning Dart Isolates (ensuring 100% Web and Native parity).
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
      customWorkerCount ?? math.max(1, PersistentBinaryStorage.processorCount);

  CancellationToken? _currentScanToken;

  /// Convenience wrapper to discover audio files recursively across [directories]
  /// and explicit [files] (local paths, OPFS URIs, or HTTP/HTTPS audio URLs).
  Stream<DiscoveredAudioFile> discoverFiles(
    List<String> directories, {
    List<String> files = const [],
    CancellationToken? cancellationToken,
  }) {
    return _discoverSourcesStream(
      directories,
      files: files,
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

  /// Starts the scan pipeline using a bounded async concurrency pool proportional
  /// to CPU cores and returns a [Stream<ScanProgress>].
  ///
  /// Both [directories] and individual [files] (local files, OPFS audio files, or
  /// HTTP/HTTPS audio links) are unified into the catalog. An individual file in
  /// [files] is protected from deletion when a folder containing it is removed from
  /// [directories], as long as the file itself still exists.
  Stream<ScanProgress> scanDirectories(
    List<String> directories, {
    List<String> files = const [],
    CancellationToken? cancellationToken,
  }) {
    final controller = StreamController<ScanProgress>();
    if (isScanning) {
      final queued = _QueuedScan(
        directories: directories,
        files: files,
        controller: controller,
        cancellationToken: cancellationToken,
      );
      _scanQueue.add(queued);
      controller.onCancel = () {
        _scanQueue.remove(queued);
      };
      return controller.stream;
    }
    _runScanPipeline(
      directories,
      files,
      controller,
      cancellationToken,
    );
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
        next.files,
        next.controller,
        next.cancellationToken,
      );
      break;
    }
  }

  // ---------------------------------------------------------------------------
  // Private: Async discovery & bounded async worker pool
  // ---------------------------------------------------------------------------

  Future<void> _runScanPipeline(
    List<String> directories,
    List<String> files,
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

      final storedByPath = {for (final s in trackStored) s.filePath: s};
      final trackDiscover = await _discoverSourcesList(
        directories,
        files: files,
        storedByPath: storedByPath,
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

      final toExtract = <DiscoveredAudioFile>[];
      final newlyDiscovered = <DiscoveredAudioFile>[];
      final toDeleteMap = Map<String, StoredTrackInfo>.from(storedByPath);

      for (final file in trackDiscover) {
        final stored = storedByPath[file.path];
        if (stored != null) {
          if (stored.modifiedAt == file.modifiedAt) {
            toDeleteMap.remove(file.path);
          } else {
            toDeleteMap.remove(file.path);
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

        final hasRemoteSources =
            kIsWeb ||
            toExtract.any(
              (f) =>
                  f.path.startsWith('http://') || f.path.startsWith('https://'),
            );
        final effectivePoolCap =
            (customWorkerCount == null && hasRemoteSources)
            ? math.min(4, workerCount)
            : workerCount;
        final numWorkers = math.min(effectivePoolCap, totalExtract);
        int nextIndex = 0;
        final savedCoverHashes = <String>{};

        if (kDebugMode || kIsWeb) {
          debugPrint(
            '[MetadataService][PERF] Starting async extraction pool: '
            'total=$totalExtract, workers=$numWorkers, remote=$hasRemoteSources',
          );
        }

        Future<void> runAsyncWorker() async {
          while (!scanToken.isCancelled) {
            if (nextIndex >= totalExtract) break;
            final item = toExtract[nextIndex++];
            final itemSw = Stopwatch()..start();
            ExtractedTrackData? track;
            try {
              track = await MetadataUtils.extractTrackMetadata(
                filePath: item.path,
                knownFileSize: item.size,
                knownModifiedAt: item.modifiedAt,
                knownSavedHashes: savedCoverHashes,
              );
            } catch (e, st) {
              debugPrint(
                '[MetadataService] Async worker failed for ${item.path}: $e\n$st',
              );
            }
            itemSw.stop();

            if (scanToken.isCancelled) break;

            extractedCount++;
            if (track != null) {
              extractedTracks.add(track);
            }
            if (kDebugMode || kIsWeb) {
              debugPrint(
                '[MetadataService][PERF] Extracted ($extractedCount/$totalExtract) '
                '"${track?.title ?? p.basename(item.path)}" in ${itemSw.elapsedMilliseconds}ms '
                '(elapsed=${stopwatch.elapsedMilliseconds}ms)',
              );
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
          }
        }

        await Future.wait(List.generate(numWorkers, (_) => runAsyncWorker()));

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
          await MetadataUtils.purgeUnusedCovers(validHashes);
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

Stream<DiscoveredAudioFile> _discoverSourcesStream(
  List<String> directories, {
  List<String> files = const [],
  Map<String, StoredTrackInfo> storedByPath = const {},
  CancellationToken? cancellationToken,
}) async* {
  final seenPaths = <String>{};

  if (directories.isNotEmpty && !(cancellationToken?.isCancelled ?? false)) {
    final stream = PersistentBinaryStorage.discoverAudioFilesStream(
      directories,
      AppDefaults.supportedAudioExtensions,
      isCancelled: () => cancellationToken?.isCancelled ?? false,
    );
    await for (final item in stream) {
      if (cancellationToken?.isCancelled ?? false) return;
      if (seenPaths.add(item.path)) {
        yield DiscoveredAudioFile(
          path: item.path,
          size: item.size,
          modifiedAt: item.modifiedAt,
        );
      }
    }
  }

  for (final rawFile in files) {
    if (cancellationToken?.isCancelled ?? false) return;
    final clean = rawFile.trim();
    if (clean.isEmpty) continue;
    if (!seenPaths.add(clean)) continue;

    if (clean.startsWith('http://') || clean.startsWith('https://')) {
      final uri = Uri.tryParse(clean);
      if (uri == null || uri.host.isEmpty) continue;
      final stored = storedByPath[clean];
      yield DiscoveredAudioFile(
        path: clean,
        size: 0,
        modifiedAt: stored?.modifiedAt ?? 1,
      );
    } else {
      final stat = await PersistentBinaryStorage.statFile(clean);
      if (stat != null && stat.size > 0) {
        yield DiscoveredAudioFile(
          path: clean,
          size: stat.size,
          modifiedAt: stat.modifiedAt,
        );
      }
    }
  }
}

Future<List<DiscoveredAudioFile>> _discoverSourcesList(
  List<String> directories, {
  List<String> files = const [],
  Map<String, StoredTrackInfo> storedByPath = const {},
  CancellationToken? cancellationToken,
}) async {
  if ((directories.isEmpty && files.isEmpty) ||
      (cancellationToken?.isCancelled ?? false)) {
    return const <DiscoveredAudioFile>[];
  }
  final results = <DiscoveredAudioFile>[];
  await for (final item in _discoverSourcesStream(
    directories,
    files: files,
    storedByPath: storedByPath,
    cancellationToken: cancellationToken,
  )) {
    if (cancellationToken?.isCancelled ?? false) {
      return const <DiscoveredAudioFile>[];
    }
    results.add(item);
  }
  return results;
}
