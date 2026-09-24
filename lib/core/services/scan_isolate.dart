import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:tachyon/core/services/cover_cache_service.dart';
import 'package:tachyon/features/library/domain/scan_progress.dart';
import 'package:tachyon/features/library/domain/track.dart';

// ---------------------------------------------------------------------------
// Message protocol: Scan Isolate → Main Isolate
//
//  {'_type': 'progress', ...ScanProgress.toJson()}
//    → a throttled UI progress update
//
//  {'_type': 'batch', 'tracks': [Track.toJson(), ...]}
//    → a batch of extracted tracks ready for DB insertion
//
//  {'_type': 'done', 'progress': ScanProgress.toJson()}
//    → all data has been sent; main isolate should await pending inserts
//      and then emit this final ScanProgress(completed) to the stream.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Args bundle: main isolate → scan isolate
// ---------------------------------------------------------------------------

/// Track metadata snapshot used to detect unchanged files during incremental scanning.
typedef TrackFileMeta = ({int modifiedAt, int fileSize});

/// All data needed to boot the scan isolate.
/// Only primitive / sendable types so it crosses the isolate boundary safely.
class ScanIsolateArgs {
  /// [SendPort] the isolate uses to push typed message maps back to main.
  final SendPort progressPort;

  /// [SendPort] used for the handshake: isolate sends back its cancel port.
  final SendPort handshakePort;

  final List<String> directories;
  final String coverCachePath;
  final int workerCount;
  final Map<String, TrackFileMeta> existingMetas;

  const ScanIsolateArgs({
    required this.progressPort,
    required this.handshakePort,
    required this.directories,
    required this.coverCachePath,
    required this.workerCount,
    this.existingMetas = const {},
  });
}

// ---------------------------------------------------------------------------
// Isolate entry point
// ---------------------------------------------------------------------------

/// Top-level entry point for the scan isolate.
/// Marked with [pragma] for AOT / tree-shaking compatibility.
@pragma('vm:entry-point')
Future<void> scanIsolateEntry(ScanIsolateArgs args) async {
  // Set up a ReceivePort inside the isolate for cancel commands
  final cancelReceivePort = ReceivePort();
  // Hand the corresponding SendPort back to the main isolate (handshake)
  args.handshakePort.send(cancelReceivePort.sendPort);

  final token = CancellationToken();
  cancelReceivePort.listen((msg) {
    if (msg == 'cancel') token.cancel();
  });

  // Boot cover cache service (pure dart:io – safe in any isolate)
  final coverService = CoverCacheService(
    cacheDirectory: Directory(args.coverCachePath),
  );
  await coverService.init();

  // Run the full extract pipeline (no DB access here)
  await _runPipeline(
    directories: args.directories,
    coverService: coverService,
    workerCount: args.workerCount,
    existingMetas: args.existingMetas,
    cancellationToken: token,
    send: args.progressPort.send,
  );

  cancelReceivePort.close();
}

// ---------------------------------------------------------------------------
// Pipeline
// ---------------------------------------------------------------------------

Future<void> _runPipeline({
  required List<String> directories,
  required CoverCacheService coverService,
  required int workerCount,
  required Map<String, TrackFileMeta> existingMetas,
  required CancellationToken cancellationToken,
  required void Function(Object?) send,
}) async {
  final stopwatch = Stopwatch()..start();

  ScanProgress current = const ScanProgress();

  // Throttled emit: sends a 'progress' message ≤ 20 Hz
  int lastEmitMs = -50;
  void sendProgress(ScanProgress p, {bool force = false}) {
    current = p.copyWith(elapsedTime: stopwatch.elapsed);
    final now = stopwatch.elapsedMilliseconds;
    if (force || now - lastEmitMs >= 50) {
      lastEmitMs = now;
      send({'_type': 'progress', ...current.toJson()});
    }
  }

  // Sends a 'batch' of extracted tracks to the main isolate for DB insertion
  void sendBatch(List<Track> tracks) {
    if (tracks.isEmpty) return;
    send({
      '_type': 'batch',
      'tracks': tracks.map((t) => t.toJson()).toList(),
    });
  }

  // Sends the terminal 'done' message with final stats
  void sendDone(ScanProgress finalProgress) {
    send({
      '_type': 'done',
      'progress': finalProgress.copyWith(elapsedTime: stopwatch.elapsed).toJson(),
    });
  }

  try {
    sendProgress(const ScanProgress(phase: ScanPhase.discovering), force: true);

    // 1. File discovery
    final discoveredFiles = <DiscoveredAudioFile>[];
    await for (final file in _discoverFiles(
      directories,
      cancellationToken: cancellationToken,
    )) {
      if (cancellationToken.isCancelled) break;
      discoveredFiles.add(file);
      sendProgress(ScanProgress(
        phase: ScanPhase.discovering,
        totalFiles: discoveredFiles.length,
        currentFile: file.path,
      ));
    }

    if (cancellationToken.isCancelled) {
      sendProgress(
        current.copyWith(phase: ScanPhase.cancelled, clearCurrentFile: true),
        force: true,
      );
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

    // 3. Concurrency-bounded extraction
    final limiter = _ConcurrencyLimiter(workerCount);
    final pendingTracks = <Track>[];
    final tasks = <Future<void>>[];

    void maybeSendBatch({bool force = false}) {
      if (pendingTracks.length >= 30 || (force && pendingTracks.isNotEmpty)) {
        final batch = List<Track>.from(pendingTracks);
        pendingTracks.clear();
        // Emit 'persisting' so the UI shows a saving indicator
        send({'_type': 'progress', ...current.copyWith(phase: ScanPhase.persisting).toJson()});
        sendBatch(batch);
        send({'_type': 'progress', ...current.copyWith(phase: ScanPhase.extracting).toJson()});
      }
    }

    for (final file in discoveredFiles) {
      if (cancellationToken.isCancelled) break;

      final existing = existingMetas[file.path];
      if (existing != null &&
          existing.modifiedAt == file.modifiedAt &&
          existing.fileSize == file.size) {
        if (!coverService.hasCachedCover(file.path)) {
          try {
            unawaited(coverService.saveCacheCover(file.path));
          } catch (_) {}
        }
        skippedCount++;
        scannedCount++;
        sendProgress(ScanProgress(
          phase: ScanPhase.extracting,
          scannedFiles: scannedCount,
          totalFiles: totalFiles,
          newTracks: newCount,
          updatedTracks: updatedCount,
          skippedTracks: skippedCount,
          failedTracks: failedCount,
          progress: totalFiles > 0 ? scannedCount / totalFiles : 1.0,
          currentFile: file.path,
        ));
        continue;
      }

      tasks.add(limiter.run(() async {
        if (cancellationToken.isCancelled) return;

        final track = await _extractMetadata(file.path, coverService);
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

        sendProgress(ScanProgress(
          phase: ScanPhase.extracting,
          scannedFiles: scannedCount,
          totalFiles: totalFiles,
          newTracks: newCount,
          updatedTracks: updatedCount,
          skippedTracks: skippedCount,
          failedTracks: failedCount,
          progress: totalFiles > 0 ? scannedCount / totalFiles : 1.0,
          currentFile: file.path,
        ));

        maybeSendBatch();
      }));
    }

    await Future.wait(tasks);

    if (cancellationToken.isCancelled) {
      sendProgress(
        current.copyWith(phase: ScanPhase.cancelled, clearCurrentFile: true),
        force: true,
      );
      return;
    }

    // Final flush
    maybeSendBatch(force: true);

    // 4. Signal completion — the main isolate will emit this after all inserts
    sendDone(ScanProgress(
      phase: ScanPhase.completed,
      scannedFiles: totalFiles,
      totalFiles: totalFiles,
      newTracks: newCount,
      updatedTracks: updatedCount,
      skippedTracks: skippedCount,
      failedTracks: failedCount,
      progress: 1.0,
    ));
  } catch (e, st) {
    debugPrint('[ScanIsolate] Pipeline failed: $e\n$st');
    send({
      '_type': 'progress',
      ...current.copyWith(
        phase: ScanPhase.failed,
        errorMessage: e.toString(),
        elapsedTime: stopwatch.elapsed,
      ).toJson(),
    });
  } finally {
    stopwatch.stop();
  }
}

// ---------------------------------------------------------------------------
// Helper: single-file metadata extraction (CPU-bound — runs in scan isolate)
// ---------------------------------------------------------------------------

Future<Track?> _extractMetadata(
  String filePath,
  CoverCacheService coverService,
) async {
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
    final metadata = readMetadata(file, getImage: false);

    if (!coverService.hasCachedCover(file.path)) {
      try {
        unawaited(coverService.saveCacheCover(file.path));
      } catch (_) {}
    }

    return Track(
      uri: filePath,
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
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Helper: recursive audio file discovery
// ---------------------------------------------------------------------------

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

Stream<DiscoveredAudioFile> _discoverFiles(
  List<String> directories, {
  CancellationToken? cancellationToken,
}) async* {
  final supportedSet = supportedFileExtensions
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
      debugPrint('[ScanIsolate] Unable to list directory $dirPath: $e');
      continue;
    }

    await for (final entity in entityStream.handleError((Object e) {
      debugPrint('[ScanIsolate] Error accessing filesystem entity: $e');
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

// ---------------------------------------------------------------------------
// Bounded concurrency limiter (local to the scan isolate)
// ---------------------------------------------------------------------------

class _ConcurrencyLimiter {
  final int maxConcurrent;
  int _activeCount = 0;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  _ConcurrencyLimiter(this.maxConcurrent)
      : assert(maxConcurrent >= 1, 'maxConcurrent must be at least 1');

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
