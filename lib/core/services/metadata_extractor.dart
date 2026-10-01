import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/services/cover_cache_service.dart';
import 'package:tachyon/core/services/scan_isolate.dart';
import 'package:tachyon/features/library/domain/scan_progress.dart';
import 'package:tachyon/features/library/domain/track.dart';

export 'package:tachyon/core/services/scan_isolate.dart'
    show DiscoveredAudioFile, TrackFileMeta;

/// Manages spawning the scan Isolate and bridging its progress events and
/// track batches back to the main isolate.
///
/// ### Architecture
/// The scan isolate performs CPU-heavy work (file discovery, `readMetadata`,
/// cover caching) and communicates results to the main isolate via a typed
/// message protocol over a single [ReceivePort]:
///
/// ```
///  {'_type': 'progress', ...ScanProgress fields}  → emit to progress stream
///  {'_type': 'batch',    'tracks': [Track.toJson(), ...]}  → DB insert (main)
///  {'_type': 'done',     'progress': ScanProgress.toJson()}  → final stats
/// ```
///
/// All SQLite writes stay in the main isolate so there is never more than one
/// writer, avoiding the "database is locked" error that arises when a second
/// isolate opens its own connection concurrently.
class MetadataExtractor {
  final AppDatabase database;
  final CoverCacheService coverCacheService;
  final int? customWorkerCount;

  MetadataExtractor({
    required this.database,
    required this.coverCacheService,
    this.customWorkerCount,
  });

  int get workerCount =>
      customWorkerCount ?? (Platform.numberOfProcessors ~/ 2).clamp(1, 8);

  Isolate? _activeIsolate;
  SendPort? _cancelPort;

  // ---------------------------------------------------------------------------
  // Public: extractMetadata – single-file convenience (runs on caller isolate)
  // ---------------------------------------------------------------------------

  /// Extracts metadata for a single [filePath]. Useful for one-off queries.
  Future<Track?> extractMetadata(String filePath) async {
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

      if (!coverCacheService.hasCachedCover(file.path)) {
        try {
          unawaited(coverCacheService.saveCacheCover(
            file.path,
            artistName: metadata.artist,
            albumName: metadata.album,
          ));
        } catch (_) {}
      }

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
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Public: discoverFiles – convenience wrapper (runs on caller isolate)
  // ---------------------------------------------------------------------------

  Stream<DiscoveredAudioFile> discoverFiles(
    List<String> directories, {
    CancellationToken? cancellationToken,
  }) {
    return _discoverFilesLocal(directories, cancellationToken: cancellationToken);
  }

  // ---------------------------------------------------------------------------
  // Public: scanDirectories – spawns the Isolate
  // ---------------------------------------------------------------------------

  /// Starts the full scan pipeline in a dedicated [Isolate] and returns a
  /// [Stream<ScanProgress>].
  Stream<ScanProgress> scanDirectories(
    List<String> directories, {
    CancellationToken? cancellationToken,
  }) {
    final controller = StreamController<ScanProgress>();
    _spawnScanIsolate(directories, controller, cancellationToken);
    return controller.stream;
  }

  /// Cancels any active scan.
  void cancelScan() {
    _cancelPort?.send('cancel');
    _cancelPort = null;
    _activeIsolate?.kill(priority: Isolate.immediate);
    _activeIsolate = null;
  }

  // ---------------------------------------------------------------------------
  // Private: isolate orchestration
  // ---------------------------------------------------------------------------

  Future<void> _spawnScanIsolate(
    List<String> directories,
    StreamController<ScanProgress> controller,
    CancellationToken? cancellationToken,
  ) async {
    cancelScan();

    final coverCachePath = coverCacheService.cacheDirectory.path;

    final progressPort = ReceivePort();
    final handshakePort = ReceivePort();

    // Query existing track metadata for incremental scanning
    Map<String, TrackFileMeta> existingMetas = const {};
    try {
      existingMetas = await database.getExistingTrackMetas();
    } catch (e) {
      debugPrint('[MetadataExtractor] Failed to load existing track metas: $e');
    }

    if (cancellationToken?.isCancelled ?? false) {
      progressPort.close();
      handshakePort.close();
      controller.add(const ScanProgress(phase: ScanPhase.cancelled));
      controller.close();
      return;
    }

    final args = ScanIsolateArgs(
      progressPort: progressPort.sendPort,
      handshakePort: handshakePort.sendPort,
      directories: directories,
      coverCachePath: coverCachePath,
      workerCount: workerCount,
      existingMetas: existingMetas,
    );

    late Isolate isolate;
    try {
      isolate = await Isolate.spawn(scanIsolateEntry, args);
    } catch (e) {
      progressPort.close();
      handshakePort.close();
      controller.addError(e);
      controller.close();
      return;
    }

    _activeIsolate = isolate;

    // Handshake: receive the cancel SendPort from the new isolate
    final cancelSendPort = await handshakePort.first as SendPort;
    handshakePort.close();
    _cancelPort = cancelSendPort;

    // Forward external cancellation token
    if (cancellationToken?.isCancelled ?? false) {
      cancelSendPort.send('cancel');
    }
    cancellationToken?.onCancel(() => cancelSendPort.send('cancel'));

    // Pending DB insert futures so we can await them before emitting 'completed'
    final pendingInserts = <Future<void>>[];

    progressPort.listen(
      (message) async {
        if (message is! Map<String, dynamic>) return;

        final type = message['_type'] as String?;

        switch (type) {
          case 'progress':
            // Strip the internal '_type' key before deserialising
            final progressMap = Map<String, dynamic>.from(message)
              ..remove('_type');
            try {
              final progress = ScanProgress.fromJson(progressMap);
              if (!controller.isClosed) controller.add(progress);
            } catch (e) {
              debugPrint('[MetadataExtractor] Failed to parse progress: $e');
            }

          case 'batch':
            // Deserialise tracks and insert via the main-isolate DB connection
            try {
              final rawList = message['tracks'] as List<dynamic>;
              final tracks = rawList
                  .map((e) => Track.fromJson(e as Map<String, dynamic>))
                  .toList();
              if (tracks.isNotEmpty) {
                pendingInserts.add(
                  database.batchInsertTracks(tracks).catchError((Object err) {
                    debugPrint('[MetadataExtractor] batchInsert error: $err');
                  }),
                );
              }
            } catch (e) {
              debugPrint('[MetadataExtractor] Failed to process batch: $e');
            }

          case 'done':
            // Wait for all pending DB inserts, then emit the final progress
            try {
              await Future.wait(pendingInserts);
              await database.cleanOrphanAlbumsAndArtists();
            } catch (e) {
              debugPrint('[MetadataExtractor] Insert error during done: $e');
            }
            try {
              final progressMap = Map<String, dynamic>.from(
                message['progress'] as Map<String, dynamic>,
              );
              final finalProgress = ScanProgress.fromJson(progressMap);
              if (!controller.isClosed) controller.add(finalProgress);
            } catch (e) {
              debugPrint('[MetadataExtractor] Failed to parse done progress: $e');
            }
            progressPort.close();
            if (!controller.isClosed) controller.close();
            _activeIsolate?.kill(priority: Isolate.immediate);
            _activeIsolate = null;
            _cancelPort = null;

          default:
            debugPrint('[MetadataExtractor] Unknown message type: $type');
        }
      },
      onError: (Object err) {
        if (!controller.isClosed) controller.addError(err);
        progressPort.close();
        controller.close();
        _activeIsolate?.kill(priority: Isolate.immediate);
        _activeIsolate = null;
        _cancelPort = null;
      },
      onDone: () {
        if (!controller.isClosed) controller.close();
        _activeIsolate?.kill(priority: Isolate.immediate);
        _activeIsolate = null;
        _cancelPort = null;
      },
      cancelOnError: false,
    );

    controller.onCancel = () {
      cancelSendPort.send('cancel');
      _activeIsolate?.kill(priority: Isolate.immediate);
      _activeIsolate = null;
      _cancelPort = null;
    };
  }
}

// ---------------------------------------------------------------------------
// Local file discovery (runs on caller isolate; used by discoverFiles helper)
// ---------------------------------------------------------------------------

Stream<DiscoveredAudioFile> _discoverFilesLocal(
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
      debugPrint('[MetadataExtractor] Unable to list directory $dirPath: $e');
      continue;
    }

    await for (final entity in entityStream.handleError((Object e) {
      debugPrint('[MetadataExtractor] Error accessing filesystem entity: $e');
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

