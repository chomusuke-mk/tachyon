import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:haudiotagger/haudiotagger.dart';
import 'package:path/path.dart' as p;
import 'package:tachyon/shared/utils/cover_utils.dart';
import 'package:tachyon/core/constants/app_defaults.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/library/domain/scan_progress.dart';

/// Track metadata snapshot used to detect unchanged files during incremental scanning.
typedef TrackFileMeta = ({int modifiedAt, int fileSize});

const Set<String> supportedTagExtensions = {
  '.mp3',
  '.flac',
  '.m4a',
  '.mp4',
  '.aac',
  '.ogg',
  '.oga',
  '.opus',
  '.wav',
  '.aif',
  '.aiff',
  '.aifc',
  '.ape',
  '.wv',
  '.mpc',
  '.spx',
};

const Map<PictureType, int> coverPriority = {
  PictureType.coverFront: 0,
  PictureType.coverBack: 1,
  PictureType.illustration: 2,
  PictureType.leadArtist: 3,
  PictureType.artist: 4,
  PictureType.band: 5,
  PictureType.composer: 6,
  PictureType.lyricist: 7,
};

const Map<PictureType, int> artistPriority = {
  PictureType.leadArtist: 0,
  PictureType.artist: 1,
  PictureType.band: 2,
  PictureType.bandLogo: 3,
  PictureType.publisherLogo: 4,
  PictureType.composer: 5,
};

const Map<PictureType, int> albumPriority = {
  PictureType.coverFront: 0,
  PictureType.coverBack: 1,
  PictureType.leaflet: 2,
  PictureType.media: 3,
  PictureType.illustration: 4,
  PictureType.brightFish: 5,
};

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
  final String? thumbnailHash;
  final String? albumThumbnailHash;
  final String? artistThumbnailHash;

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
    this.thumbnailHash,
    this.albumThumbnailHash,
    this.artistThumbnailHash,
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
/// 4. In each worker, extracts metadata and saves triple-quality (LQ, MQ, HQ) covers
///    to disk in a single pass.
/// 5. Workers write files directly to disk and return pure Dart models.
///    Zero raw byte buffers are passed between isolates.
class MetadataService {
  final AppDatabase database;
  final int? customWorkerCount;
  final String cacheDirPath;

  MetadataService({
    required this.database,
    required this.cacheDirPath,
    this.customWorkerCount,
  });

  int get workerCount =>
      customWorkerCount ?? math.max(1, Platform.numberOfProcessors);

  CancellationToken? _currentScanToken;

  static List<String> parseArtistNames(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static List<String> parseGenreNames(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    return raw
        .split(RegExp(r'[,;/]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

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

    final cachePath = CoverUtils.cacheDirectory.path;
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
      // Estado inicial: Obteniendo base de datos...
      sendProgress(
        const ScanProgress(
          phase: ScanPhase.gettingDatabase,
          message: 'Obteniendo base de datos...',
        ),
        force: true,
      );

      // Etapa 1: Obteniendo canciones... (desde base de datos)
      sendProgress(
        const ScanProgress(
          phase: ScanPhase.gettingTracks,
          message: 'Obteniendo canciones...',
        ),
        force: true,
      );

      final trackStored = database.getStoredTracks();

      if (scanToken.isCancelled) {
        sendProgress(
          current.copyWith(
            phase: ScanPhase.cancelled,
            message: 'Cancelado',
            clearProgress: true,
          ),
          force: true,
        );
        if (!controller.isClosed) controller.close();
        return;
      }

      // Etapa 2: Comparando... (listar archivos de carpetas y comparar con trackStored)
      sendProgress(
        const ScanProgress(
          phase: ScanPhase.comparing,
          message: 'Comparando...',
        ),
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
          current.copyWith(
            phase: ScanPhase.cancelled,
            message: 'Cancelado',
            clearProgress: true,
          ),
          force: true,
        );
        if (!controller.isClosed) controller.close();
        return;
      }

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

      // Etapa 3: Obteniendo metadatos completos de cada trackDiscover
      final totalExtract = toExtract.length;
      final extractedTracks = <ExtractedTrackData>[];
      final activeTasks = <Future<void>>{};
      final poolSize = workerCount;
      int extractedCount = 0;

      sendProgress(
        ScanProgress(
          phase: ScanPhase.extracting,
          message: 'Obteniendo metadatos 0/$totalExtract',
          progress: totalExtract == 0 ? 1.0 : 0.0,
          totalFiles: totalExtract,
          scannedFiles: 0,
        ),
        force: true,
      );

      for (final file in toExtract) {
        if (scanToken.isCancelled) break;

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
          extractedCount++;

          if (track != null) {
            extractedTracks.add(track);
          }

          final progressVal = totalExtract > 0
              ? extractedCount / totalExtract
              : 1.0;
          sendProgress(
            ScanProgress(
              phase: ScanPhase.extracting,
              message: 'Obteniendo metadatos $extractedCount/$totalExtract',
              progress: progressVal,
              totalFiles: totalExtract,
              scannedFiles: extractedCount,
              currentFile: file.path,
            ),
          );
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
          current.copyWith(
            phase: ScanPhase.cancelled,
            message: 'Cancelado',
            clearProgress: true,
          ),
          force: true,
        );
        if (!controller.isClosed) controller.close();
        return;
      }

      // Etapa 4: Insertando...
      sendProgress(
        const ScanProgress(
          phase: ScanPhase.inserting,
          message: 'Insertando...',
        ),
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
          current.copyWith(
            phase: ScanPhase.cancelled,
            message: 'Cancelado',
            clearProgress: true,
          ),
          force: true,
        );
        if (!controller.isClosed) controller.close();
        return;
      }

      // Etapa 5: Limpiando orphan...
      sendProgress(
        const ScanProgress(
          phase: ScanPhase.cleaningOrphans,
          message: 'Limpiando orphan...',
        ),
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
          current.copyWith(
            phase: ScanPhase.cancelled,
            message: 'Cancelado',
            clearProgress: true,
          ),
          force: true,
        );
        if (!controller.isClosed) controller.close();
        return;
      }

      // Etapa 6: Limpiando thumbnails...
      sendProgress(
        const ScanProgress(
          phase: ScanPhase.cleaningThumbnails,
          message: 'Limpiando thumbnails...',
        ),
        force: true,
      );

      try {
        final activeHashes = database.getAllThumbnailHashes();
        await CoverUtils.clearTemp();

        final coverFiles = CoverUtils.listCachedCoverFiles();

        final remainingFiles = List<File>.from(coverFiles);
        final validHashes = activeHashes
            .where((h) => h.trim().isNotEmpty)
            .toSet();

        for (final hash in validHashes) {
          remainingFiles.removeWhere(
            (file) => p.basename(file.path).contains(hash),
          );
        }

        for (final file in remainingFiles) {
          try {
            file.deleteSync();
          } catch (_) {}
        }
      } catch (e) {
        debugPrint('[MetadataService] cleaningThumbnails error: $e');
      }

      sendProgress(
        ScanProgress(
          phase: ScanPhase.completed,
          message: 'Completado',
          progress: 1.0,
          totalFiles: totalExtract,
          scannedFiles: extractedCount,
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
      await CoverUtils.clearTemp();
    }
  }
}

// =============================================================================
// SHARED EXTRACTION & WORKER FUNCTIONS
// =============================================================================

double? _parseReplayGain(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  final str = value.toString().replaceAll(RegExp(r'[^0-9.-]'), '');
  return double.tryParse(str);
}

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

Future<(Tag?, AudioProperties?)> _readTagsAndProperties(String filePath) async {
  final ext = p.extension(filePath).toLowerCase();
  if (!supportedTagExtensions.contains(ext)) {
    return (null, null);
  }

  Tag? tag;
  AudioProperties? properties;
  try {
    tag = await Haudiotagger.read(filePath);
  } catch (e) {
    debugPrint(
      '[MetadataService] Error reading tags with haudiotagger for $filePath: $e',
    );
  }

  try {
    properties = await Haudiotagger.readProperties(filePath);
  } catch (_) {}

  return (tag, properties);
}

ExtractedTrackData _buildExtractedTrackData({
  required String filePath,
  required int fileSize,
  required int modifiedAt,
  Tag? tag,
  AudioProperties? properties,
  String? thumbnailHash,
  String? albumThumbnailHash,
  String? artistThumbnailHash,
}) {
  final ext = p.extension(filePath).toLowerCase();
  final extClean = ext.replaceAll('.', '').toUpperCase();

  if (tag != null) {
    final durationMs = properties?.durationMicros != null
        ? (properties!.durationMicros!.toInt() / 1000).round()
        : (tag.duration != null ? tag.duration! * 1000 : 0);

    final artists = MetadataService.parseArtistNames(tag.trackArtist);
    final resolvedArtists = artists.isNotEmpty
        ? artists
        : MetadataService.parseArtistNames(tag.albumArtist);

    final genres = MetadataService.parseGenreNames(tag.genre);

    return ExtractedTrackData(
      filePath: filePath,
      title: tag.title?.trim().isNotEmpty == true
          ? tag.title!.trim()
          : p.basenameWithoutExtension(filePath),
      albumName: tag.album?.trim().isNotEmpty == true
          ? tag.album!.trim()
          : null,
      artistNames: resolvedArtists,
      albumArtistName: tag.albumArtist?.trim().isNotEmpty == true
          ? tag.albumArtist!.trim()
          : null,
      genreNames: genres,
      trackNumber: tag.trackNumber,
      discNumber: tag.discNumber ?? 1,
      year: tag.year,
      durationMs: durationMs,
      bitrate: properties?.bitrate,
      sampleRate: properties?.sampleRate,
      channels: properties?.channels,
      codec: properties?.codec ?? (extClean.isNotEmpty ? extClean : null),
      fileSize: fileSize,
      modifiedAt: modifiedAt,
      embeddedLyrics: tag.lyrics,
      replayGainTrackGain: _parseReplayGain(tag.replayGainTrackGain),
      replayGainTrackPeak: _parseReplayGain(tag.replayGainTrackPeak),
      thumbnailHash: thumbnailHash,
      albumThumbnailHash: albumThumbnailHash,
      artistThumbnailHash: artistThumbnailHash,
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
      codec: properties.codec.isNotEmpty
          ? properties.codec
          : (extClean.isNotEmpty ? extClean : null),
      fileSize: fileSize,
      modifiedAt: modifiedAt,
      thumbnailHash: thumbnailHash,
      albumThumbnailHash: albumThumbnailHash,
      artistThumbnailHash: artistThumbnailHash,
    );
  }

  return _buildFallbackTrackData(
    filePath: filePath,
    size: fileSize,
    modifiedAt: modifiedAt,
  );
}

/// Worker function that runs in a dedicated isolate via [Isolate.run].
/// In a single pass:
/// 1. Reads file metadata.
/// 2. Saves content-addressed thumbnails in covers/ directory.
/// 3. Returns the populated [ExtractedTrackData] with thumbnail hashes.
@pragma('vm:entry-point')
Future<ExtractedTrackData?> extractAndCacheTrackWorker({
  required String filePath,
  String? cacheDirPath,
}) async {
  final file = File(filePath);
  if (!file.existsSync() && !await file.exists()) return null;

  if (!CoverUtils.isInitialized) {
    if (cacheDirPath == null) {
      debugPrint(
        '[MetadataService] Cache directory path is null. Cannot initialize CoverUtils.',
      );
      throw Exception('Bad use of CoverUtils: cacheDirPath is null.');
    }
    CoverUtils.init(Directory(cacheDirPath));
  }

  int size = 0;
  int modifiedAt = 0;
  try {
    final stat = await file.stat();
    size = stat.size;
    modifiedAt = stat.modified.millisecondsSinceEpoch;
  } catch (_) {}

  try {
    final (tag, properties) = await _readTagsAndProperties(filePath);

    Uint8List? coverBytes;
    Uint8List? artistBytes;
    Uint8List? albumBytes;

    if (tag != null && tag.pictures.isNotEmpty) {
      final pictures = tag.pictures.toList();
      // Cover
      pictures.sort((a, b) {
        final aPriority = coverPriority[a.pictureType] ?? 99;
        final bPriority = coverPriority[b.pictureType] ?? 99;
        return aPriority.compareTo(bPriority);
      });
      coverBytes = pictures.isNotEmpty ? pictures.first.bytes : null;
      // Album
      pictures.sort((a, b) {
        final aPriority = albumPriority[a.pictureType] ?? 99;
        final bPriority = albumPriority[b.pictureType] ?? 99;
        return aPriority.compareTo(bPriority);
      });
      albumBytes = pictures.isNotEmpty ? pictures.first.bytes : null;
      // Artist
      pictures.sort((a, b) {
        final aPriority = artistPriority[a.pictureType] ?? 99;
        final bPriority = artistPriority[b.pictureType] ?? 99;
        return aPriority.compareTo(bPriority);
      });
      artistBytes = pictures.isNotEmpty ? pictures.first.bytes : null;
    }

    String? thumbnailHash;
    if (coverBytes != null && coverBytes.isNotEmpty) {
      thumbnailHash = CoverUtils.computeBytesHash(coverBytes);
      if (!CoverUtils.hasCachedCover(thumbnailHash)) {
        await CoverUtils.saveThumbnailBytes(thumbnailHash, coverBytes);
      }
    }

    String? albumThumbnailHash;
    if (albumBytes != null && albumBytes.isNotEmpty) {
      albumThumbnailHash = CoverUtils.computeBytesHash(albumBytes);
      if (!CoverUtils.hasCachedCover(albumThumbnailHash)) {
        await CoverUtils.saveThumbnailBytes(albumThumbnailHash, albumBytes);
      }
    }

    String? artistThumbnailHash;
    if (artistBytes != null && artistBytes.isNotEmpty) {
      artistThumbnailHash = CoverUtils.computeBytesHash(artistBytes);
      if (!CoverUtils.hasCachedCover(artistThumbnailHash)) {
        await CoverUtils.saveThumbnailBytes(artistThumbnailHash, artistBytes);
      }
    }

    return _buildExtractedTrackData(
      filePath: filePath,
      fileSize: size,
      modifiedAt: modifiedAt,
      tag: tag,
      properties: properties,
      thumbnailHash: thumbnailHash,
      albumThumbnailHash: albumThumbnailHash,
      artistThumbnailHash: artistThumbnailHash,
    );
  } catch (e) {
    debugPrint(
      '[MetadataService] Unexpected error extracting metadata for $filePath: $e',
    );
    return _buildFallbackTrackData(
      filePath: filePath,
      size: size,
      modifiedAt: modifiedAt,
    );
  }
}

/// Parses audio tags and metadata for a single file.
Future<ExtractedTrackData?> extractTrackMetadata(String filePath) async {
  return extractAndCacheTrackWorker(filePath: filePath);
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
