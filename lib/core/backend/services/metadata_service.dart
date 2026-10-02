import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/backend/services/cover_cache_service.dart';
import 'package:tachyon/core/backend/services/scan_isolate.dart';
import 'package:tachyon/features/library/domain/scan_progress.dart';
import 'package:tachyon/features/library/domain/track.dart';

export 'package:tachyon/core/backend/services/scan_isolate.dart'
    show DiscoveredAudioFile, TrackFileMeta;

/// Service running in the Core Service Isolate responsible for metadata
/// orchestration, single-file tag extraction, thumbnail resolution, and full library scanning.
///
/// Follows a strict Cache-First strategy:
/// 1. Queries database or disk cache first (immediate return, 0 CPU).
/// 2. If missing, delegates single-file operations to an ephemeral worker via [Isolate.run].
/// 3. Runs multi-file directory scans in a dedicated isolate via [Isolate.spawn].
/// 4. Workers write files directly to disk and return only string paths.
///    Zero byte buffers are passed between isolates.
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
      customWorkerCount ?? (Platform.numberOfProcessors ~/ 2).clamp(1, 8);

  Isolate? _activeIsolate;
  SendPort? _cancelPort;

  // ---------------------------------------------------------------------------
  // Single-file operations (Isolate.run)
  // ---------------------------------------------------------------------------

  /// Extracts metadata for a single [filePath] in a dedicated worker isolate
  /// via [Isolate.run]. Does not write to SQLite (pure extraction).
  Future<Track?> extractMetadata(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync() && !await file.exists()) return null;

    final cachePath = coverCacheService.cacheDirectory.path;
    return await Isolate.run(() async {
      final coverService = CoverCacheService(cacheDirectory: Directory(cachePath));
      return await extractTrackMetadata(
        filePath,
        coverCacheService: coverService,
        awaitCover: true,
      );
    });
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
    final quality = isHighQuality ? ThumbnailQuality.high : ThumbnailQuality.low;

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
    final quality = isHighQuality ? ThumbnailQuality.high : ThumbnailQuality.low;
    if (coverCacheService.hasCachedArtistCover(artistName, quality: quality)) {
      final file = coverCacheService.getArtistCoverFile(artistName, quality: quality);
      return file.path;
    }
    return null;
  }

  /// Clears thumbnail disk cache directory.
  Future<void> clearCoverCache() async {
    await coverCacheService.clearCache();
  }

  // ---------------------------------------------------------------------------
  // Multi-file operations (Isolate.spawn)
  // ---------------------------------------------------------------------------

  /// Convenience wrapper to discover audio files recursively on the caller isolate.
  Stream<DiscoveredAudioFile> discoverFiles(
    List<String> directories, {
    CancellationToken? cancellationToken,
  }) {
    return _discoverFilesLocal(directories, cancellationToken: cancellationToken);
  }

  /// Starts the full scan pipeline in a dedicated [Isolate] via [Isolate.spawn]
  /// and returns a [Stream<ScanProgress>].
  Stream<ScanProgress> scanDirectories(
    List<String> directories, {
    CancellationToken? cancellationToken,
  }) {
    final controller = StreamController<ScanProgress>();
    _spawnScanIsolate(directories, controller, cancellationToken);
    return controller.stream;
  }

  /// Cancels any active library scan isolate.
  void cancelScan() {
    _cancelPort?.send('cancel');
    _cancelPort = null;
    _activeIsolate?.kill(priority: Isolate.immediate);
    _activeIsolate = null;
  }

  // ---------------------------------------------------------------------------
  // Private: Isolate.spawn orchestration
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
      debugPrint('[MetadataService] Failed to load existing track metas: $e');
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
            final progressMap = Map<String, dynamic>.from(message)
              ..remove('_type');
            try {
              final progress = ScanProgress.fromJson(progressMap);
              if (!controller.isClosed) controller.add(progress);
            } catch (e) {
              debugPrint('[MetadataService] Failed to parse progress: $e');
            }

          case 'batch':
            try {
              final rawList = message['tracks'] as List<dynamic>;
              final tracks = rawList
                  .map((e) => Track.fromJson(e as Map<String, dynamic>))
                  .toList();
              if (tracks.isNotEmpty) {
                pendingInserts.add(
                  database.batchInsertTracks(tracks).catchError((Object err) {
                    debugPrint('[MetadataService] batchInsert error: $err');
                  }),
                );
              }
            } catch (e) {
              debugPrint('[MetadataService] Failed to process batch: $e');
            }

          case 'done':
            try {
              await Future.wait(pendingInserts);
              await database.cleanOrphanAlbumsAndArtists();
            } catch (e) {
              debugPrint('[MetadataService] Insert error during done: $e');
            }
            try {
              final progressMap = Map<String, dynamic>.from(
                message['progress'] as Map<String, dynamic>,
              );
              final finalProgress = ScanProgress.fromJson(progressMap);
              if (!controller.isClosed) controller.add(finalProgress);
            } catch (e) {
              debugPrint('[MetadataService] Failed to parse done progress: $e');
            }
            progressPort.close();
            if (!controller.isClosed) controller.close();
            _activeIsolate?.kill(priority: Isolate.immediate);
            _activeIsolate = null;
            _cancelPort = null;

          default:
            debugPrint('[MetadataService] Unknown message type: $type');
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

// =============================================================================
// SHARED WORKER FUNCTIONS (Used by Isolate.run and scan_isolate.dart)
// =============================================================================

/// Parses audio tags and metadata for a single file.
/// If [coverCacheService] is provided and artwork is not yet cached, saves
/// dual-quality artwork to disk.
Future<Track?> extractTrackMetadata(
  String filePath, {
  CoverCacheService? coverCacheService,
  bool awaitCover = false,
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
    final metadata = readMetadata(file, getImage: false);

    if (coverCacheService != null && !coverCacheService.hasCachedCover(file.path)) {
      try {
        final future = coverCacheService.saveCacheCover(
          file.path,
          artistName: metadata.artist,
          albumName: metadata.album,
        );
        if (awaitCover) {
          await future;
        } else {
          unawaited(future);
        }
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

/// Worker function that extracts artwork from file or folder using [CoverCacheService],
/// performs centered square crop (minDim x minDim), saves 80x80 LQ and max 500x500 HQ
/// to disk, and returns the disk file paths. Never returns raw bytes.
Future<Map<String, String>?> extractAndSaveThumbnailWorker({
  required String filePath,
  required String cacheDirPath,
}) async {
  final file = File(filePath);
  if (!file.existsSync()) return null;

  final coverCache = CoverCacheService(cacheDirectory: Directory(cacheDirPath));
  final hqFile = await coverCache.saveCacheCover(filePath);
  if (hqFile != null && hqFile.existsSync() && hqFile.lengthSync() > 0) {
    final lqFile = coverCache.getCoverFile(filePath, quality: ThumbnailQuality.low);
    return {
      'hq': hqFile.path,
      'lq': lqFile.path,
    };
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
