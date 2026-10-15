import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:haudiotagger/haudiotagger.dart';
import 'package:miniaudio_player/miniaudio_player.dart';
import 'package:path/path.dart' as p;
import 'package:tachyon/core/constants/app_defaults.dart';

import 'dart:math' as math;

import 'package:tachyon/shared/utils/parse_utils.dart';
import 'package:tachyon/shared/utils/waveform_codec.dart';

/// Quality levels for thumbnail images and cover art.
enum ThumbnailQuality { low, medium, high }

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
  final String? waveformData;
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
    this.waveformData,
    this.genreNames = const [],
    this.embeddedLyrics,
    this.thumbnailHash,
    this.albumThumbnailHash,
    this.artistThumbnailHash,
  });
}

abstract final class MetadataUtils {
  static Directory? tempDirectory;
  static Directory? thumbnailsDirectory;
  static const String _kGpuBridgePortName = 'cover_utils_dart_ui_gpu_bridge';
  static RawReceivePort? _gpuBridgePort;

  static final Map<String, Future<void>> _inFlightHashes = {};

  static void init(String thumbnailsPath, String tempPath) {
    tempDirectory = Directory(tempPath);
    thumbnailsDirectory = Directory(thumbnailsPath);
    if (!thumbnailsDirectory!.existsSync()) {
      thumbnailsDirectory!.createSync(recursive: true);
    }
    if (!tempDirectory!.existsSync()) {
      tempDirectory!.createSync(recursive: true);
    }
    if (ui.RootIsolateToken.instance == null) return;
    if (_gpuBridgePort != null) return;

    _gpuBridgePort = RawReceivePort((dynamic message) async {
      if (message is! List || message.length != 3) return;
      final SendPort replyPort = message[0] as SendPort;
      final TransferableTypedData transferableRaw =
          message[1] as TransferableTypedData;
      final String hash = message[2] as String;
      try {
        final rawBytes = transferableRaw.materialize().asUint8List();
        await _deduplicatedWriteOnRootIsolate(rawBytes, hash);
        replyPort.send(null);
      } catch (e) {
        replyPort.send('ERROR:$e');
      }
    });

    ui.IsolateNameServer.removePortNameMapping(_kGpuBridgePortName);
    ui.IsolateNameServer.registerPortWithName(
      _gpuBridgePort!.sendPort,
      _kGpuBridgePortName,
    );
  }

  static void _ensureInitialized() {
    if (tempDirectory == null || thumbnailsDirectory == null) {
      throw Exception(
        'MetadataUtils is not initialized. Call MetadataUtils.init() first.',
      );
    }
  }

  static Future<void> clearTempDirectory() async {
    _ensureInitialized();
    try {
      if (await tempDirectory!.exists()) {
        await tempDirectory!.delete(recursive: true);
      }
      if (!await tempDirectory!.exists()) {
        await tempDirectory!.create(recursive: true);
      }
    } catch (_) {}
  }

  /// Returns the file path for the thumbnail image
  static String getThumbnailFilePath(
    String hash, {
    ThumbnailQuality quality = ThumbnailQuality.low,
  }) {
    _ensureInitialized();
    return p.join(thumbnailsDirectory!.path, '${hash}_${quality.name}.png');
  }

  /// Extracts the hash from a thumbnail file path.
  static String extractHashFromThumbnailPath(String thumbnailPath) {
    final fileName = p.basename(thumbnailPath);
    final parts = fileName.split('_');
    if (parts.isEmpty) return '';
    return parts.first;
  }

  static bool hasCachedThumbnail(
    String hash, {
    ThumbnailQuality quality = ThumbnailQuality.low,
  }) {
    _ensureInitialized();
    final f = File(getThumbnailFilePath(hash, quality: quality));
    return f.existsSync() && f.lengthSync() > 0;
  }

  @visibleForTesting
  static Future<void> saveThumbnailBytes(
    String hash,
    Uint8List rawBytes,
  ) async {
    _ensureInitialized();
    await _writeTripleQualityImages(rawBytes, hash);
  }

  static Future<ExtractedTrackData?> extractTrackMetadata({
    required String filePath,
    bool useSync = false,
  }) async {
    _ensureInitialized();
    final file = File(filePath);
    if (!await file.exists()) return null;
    // Get file properties
    int size = 0;
    int modifiedAt = 0;
    try {
      final stat = await file.stat();
      size = stat.size;
      modifiedAt = stat.modified.millisecondsSinceEpoch;
    } catch (_) {}

    // Get Track Metadata
    double? trackGain;
    double? trackPeak;
    String? waveformData;
    Tag? tag;
    try {
      tag = await Haudiotagger.read(filePath);
      trackGain = ParserUtils.parseDouble(tag?.replayGainTrackGain);
      trackPeak = ParserUtils.parseDouble(tag?.replayGainTrackPeak);
    } catch (e) {
      debugPrint('[MetadataService] readMetadata error for $filePath: $e');
    }

    // Get Track Analysis
    AudioAnalysisResult? analysis;
    try {
      if (useSync) {
        analysis = MiniaudioPlayer.analyzeAudioSync(
          filePath,
          replayGain: trackGain == null,
          waveform: true,
          waveformPoints: 100,
        );
      } else {
        analysis = await MiniaudioPlayer.analyzeAudio(
          filePath,
          replayGain: trackGain == null,
          waveform: true,
          waveformPoints: 100,
        );
      }
      trackGain = trackGain ?? analysis.replayGain?.gainDb;
      trackPeak = trackPeak ?? analysis.replayGain?.peak;
      waveformData = WaveformCodec.encode(analysis.waveform?.points);
    } catch (e) {
      debugPrint('[MetadataService] analyzeAudio error for $filePath: $e');
    }

    // Extract and cache cover art, album art, and artist images
    String? coverHash;
    String? albumThumbnailHash;
    String? artistThumbnailHash;
    final Map<String, Uint8List> hashToBytes = {};
    if (tag != null && tag.pictures.isNotEmpty) {
      final pictures = tag.pictures;
      // Memorizar el cálculo SHA-256 por instancia de Picture para no hashear 3 veces los mismos bytes
      final Map<Picture, String> pictureHashes = {};
      String? getOrComputeHash(Picture? pic) {
        if (pic == null || pic.bytes.isEmpty) return null;
        return pictureHashes.putIfAbsent(pic, () {
          final h = ParserUtils.computeBytesHash(pic.bytes);
          hashToBytes[h] = pic.bytes;
          return h;
        });
      }

      Picture? pickBest(
        Map<PictureType, int> priorityMap, {
        bool fallbackToFirst = false,
      }) {
        Picture? best;
        int bestPriority = 99;
        for (final pic in pictures) {
          final p = priorityMap[pic.pictureType];
          if (p != null && p < bestPriority) {
            bestPriority = p;
            best = pic;
          }
        }
        return best ?? (fallbackToFirst ? pictures.first : null);
      }

      coverHash = getOrComputeHash(
        pickBest(coverPriority, fallbackToFirst: true),
      );
      albumThumbnailHash = getOrComputeHash(
        pickBest(albumPriority, fallbackToFirst: false),
      );
      artistThumbnailHash = getOrComputeHash(
        pickBest(artistPriority, fallbackToFirst: false),
      );
    }

    for (final entry in hashToBytes.entries) {
      final hash = entry.key;
      final bytes = entry.value;
      if (!_allQualitiesExistSync(hash)) {
        await _writeTripleQualityImages(bytes, hash);
      }
    }
    return _buildExtractedTrackData(
      filePath: filePath,
      fileSize: size,
      modifiedAt: modifiedAt,
      tag: tag,
      analysis: analysis,
      replayGainTrackGain: trackGain,
      replayGainTrackPeak: trackPeak,
      waveformData: waveformData,
      thumbnailHash: coverHash,
      albumThumbnailHash: albumThumbnailHash,
      artistThumbnailHash: artistThumbnailHash,
    );
  }

  static bool _allQualitiesExistSync(String hash) {
    return File(getThumbnailFilePath(hash, quality: ThumbnailQuality.low))
            .existsSync() &&
        File(getThumbnailFilePath(hash, quality: ThumbnailQuality.medium))
            .existsSync() &&
        File(getThumbnailFilePath(hash, quality: ThumbnailQuality.high))
            .existsSync();
  }

  static Future<void> _writeTripleQualityImages(
    Uint8List rawBytes,
    String hash,
  ) async {
    _ensureInitialized();
    if (ui.RootIsolateToken.instance != null) {
      return _deduplicatedWriteOnRootIsolate(rawBytes, hash);
    }
    final SendPort? gpuSendPort = ui.IsolateNameServer.lookupPortByName(
      _kGpuBridgePortName,
    );
    if (gpuSendPort == null) {
      throw StateError(
        'El puente GPU de MetadataUtils no fue inicializado en el Root Isolate. '
        'Llama a MetadataUtils.init() antes de crear el Isolate.',
      );
    }
    final responsePort = ReceivePort();
    try {
      gpuSendPort.send(<Object>[
        responsePort.sendPort,
        TransferableTypedData.fromList([rawBytes]),
        hash,
      ]);

      final dynamic response = await responsePort.first;
      if (response is String && response.startsWith('ERROR:')) {
        throw Exception(response.substring(6));
      }
    } finally {
      responsePort.close();
    }
  }

  static Future<void> _deduplicatedWriteOnRootIsolate(
    Uint8List rawBytes,
    String hash,
  ) {
    if (_allQualitiesExistSync(hash)) return Future.value();
    final existingTask = _inFlightHashes[hash];
    if (existingTask != null) return existingTask;

    final future = _writeTripleQualityImagesOnRootIsolate(rawBytes, hash)
        .whenComplete(() async {
          _inFlightHashes.remove(hash);
          return Future.value();
        });
    _inFlightHashes[hash] = future;
    return future;
  }

  static Future<void> _writeTripleQualityImagesOnRootIsolate(
    Uint8List rawBytes,
    String hash,
  ) async {
    _ensureInitialized();
    final fileHq = File(
      getThumbnailFilePath(hash, quality: ThumbnailQuality.high),
    );
    final fileMq = File(
      getThumbnailFilePath(hash, quality: ThumbnailQuality.medium),
    );
    final fileLq = File(
      getThumbnailFilePath(hash, quality: ThumbnailQuality.low),
    );

    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? decodedImage;
    ui.Image? hqImage;
    ui.Image? mqImage;
    ui.Image? lqImage;

    try {
      // 1. Leer dimensiones del encabezado en C++ SIN decodificar toda la imagen
      buffer = await ui.ImmutableBuffer.fromUint8List(rawBytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final int origWidth = descriptor.width;
      final int origHeight = descriptor.height;
      final int side = math.min(origWidth, origHeight);

      final int targetLarge = math.min(side, AppDefaults.highQualityResolution);
      final int targetMedium = math.min(
        side,
        AppDefaults.mediumQualityResolution,
      );
      final int targetSmall = math.min(side, AppDefaults.lowQualityResolution);

      // 2. Decodificar escalando directamente en el decodificador nativo (libjpeg-turbo / libpng)
      final double scale = targetLarge / side;
      final int decodeWidth = math.max(1, (origWidth * scale).round());
      final int decodeHeight = math.max(1, (origHeight * scale).round());

      codec = await descriptor.instantiateCodec(
        targetWidth: decodeWidth,
        targetHeight: decodeHeight,
      );
      final ui.FrameInfo frame = await codec.getNextFrame();
      decodedImage = frame.image;

      // 3. Obtener hqImage cuadrada (Si ya es cuadrada, reutilizamos decodedImage sin pasar por Canvas)
      if (decodedImage.width == targetLarge &&
          decodedImage.height == targetLarge) {
        hqImage = decodedImage;
      } else {
        final int minDecoded = math.min(
          decodedImage.width,
          decodedImage.height,
        );
        final ui.Rect cropRect = ui.Rect.fromLTWH(
          (decodedImage.width - minDecoded) / 2.0,
          (decodedImage.height - minDecoded) / 2.0,
          minDecoded.toDouble(),
          minDecoded.toDouble(),
        );
        hqImage = await _renderResizedUiImage(
          sourceImage: decodedImage,
          srcRect: cropRect,
          size: targetLarge,
        );
      }

      // 4. Downsampling en cascada en GPU (hqImage -> mqImage -> lqImage)
      final ui.Rect fullHqRect = ui.Rect.fromLTWH(
        0,
        0,
        hqImage.width.toDouble(),
        hqImage.height.toDouble(),
      );

      mqImage = (targetMedium == targetLarge)
          ? hqImage
          : await _renderResizedUiImage(
              sourceImage: hqImage,
              srcRect: fullHqRect,
              size: targetMedium,
            );

      final ui.Rect fullMqRect = ui.Rect.fromLTWH(
        0,
        0,
        mqImage.width.toDouble(),
        mqImage.height.toDouble(),
      );

      lqImage = (targetSmall == targetMedium)
          ? mqImage
          : await _renderResizedUiImage(
              sourceImage: mqImage,
              srcRect: fullMqRect,
              size: targetSmall,
            );

      // 5. Codificar a PNG en paralelo
      final Future<Uint8List> hqFuture = _encodeUiImageToPng(hqImage);
      final Future<Uint8List> mqFuture = identical(mqImage, hqImage)
          ? hqFuture
          : _encodeUiImageToPng(mqImage);
      final Future<Uint8List> lqFuture = identical(lqImage, mqImage)
          ? mqFuture
          : _encodeUiImageToPng(lqImage);

      final results = await Future.wait([hqFuture, mqFuture, lqFuture]);

      // 6. Guardar las imágenes en paralelo (sin fsync bloqueante)
      await Future.wait([
        _safeAtomicWrite(fileHq, results[0]),
        _safeAtomicWrite(fileMq, results[1]),
        _safeAtomicWrite(fileLq, results[2]),
      ]);
    } finally {
      if (lqImage != null && !identical(lqImage, mqImage)) {
        lqImage.dispose();
      }
      if (mqImage != null && !identical(mqImage, hqImage)) {
        mqImage.dispose();
      }
      if (hqImage != null && !identical(hqImage, decodedImage)) {
        hqImage.dispose();
      }
      decodedImage?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  static Future<ui.Image> _renderResizedUiImage({
    required ui.Image sourceImage,
    required ui.Rect srcRect,
    required int size,
  }) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    final ui.Rect dstRect = ui.Rect.fromLTWH(
      0,
      0,
      size.toDouble(),
      size.toDouble(),
    );

    canvas.drawImageRect(
      sourceImage,
      srcRect,
      dstRect,
      ui.Paint()
        ..isAntiAlias = true
        ..filterQuality = ui
            .FilterQuality
            .low, // Bilineal directo (sin costo de generar mipmaps)
    );

    final ui.Picture picture = recorder.endRecording();
    try {
      return await picture.toImage(size, size);
    } finally {
      picture.dispose();
    }
  }

  static Future<Uint8List> _encodeUiImageToPng(ui.Image image) async {
    final ByteData? byteData = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    if (byteData == null) {
      throw StateError(
        'No se pudo codificar la miniatura (${image.width} px) a PNG.',
      );
    }
    return byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
  }

  static Future<void> _safeAtomicWrite(File targetFile, Uint8List bytes) async {
    _ensureInitialized();
    if (targetFile.existsSync() && targetFile.lengthSync() > 0) {
      return;
    }

    final rand = math.Random().nextInt(1 << 30);
    final fileName = p.basename(targetFile.path);
    final tempFile = File(
      p.join(tempDirectory!.path, '${fileName}_${pid}_$rand.tmp'),
    );

    try {
      await tempFile.writeAsBytes(bytes, flush: false);
      await tempFile.rename(targetFile.path);
    } catch (_) {
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
      if (await targetFile.exists() && await targetFile.length() > 0) {
        return;
      }
      try {
        await targetFile.writeAsBytes(bytes, flush: false);
      } catch (_) {}
    }
  }

  static ExtractedTrackData _buildExtractedTrackData({
    required String filePath,
    required int fileSize,
    required int modifiedAt,
    Tag? tag,
    AudioAnalysisResult? analysis,
    double? replayGainTrackGain,
    double? replayGainTrackPeak,
    String? waveformData,
    String? thumbnailHash,
    String? albumThumbnailHash,
    String? artistThumbnailHash,
  }) {
    final ext = p.extension(filePath).toLowerCase();
    final extClean = ext.replaceAll('.', '').toUpperCase();

    final effectiveBitrate = analysis != null && analysis.bitrate > 0
        ? analysis.bitrate
        : null;
    final effectiveSampleRate = analysis != null && analysis.sampleRate > 0
        ? analysis.sampleRate
        : null;
    final effectiveChannels = analysis != null && analysis.channels > 0
        ? analysis.channels
        : null;

    var durationMs = tag?.duration != null ? tag!.duration! * 1000 : 0;
    if (durationMs <= 0 && analysis != null) {
      durationMs = analysis.duration.inMilliseconds;
    }

    final artists =
        tag?.trackArtist
            ?.split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList() ??
        const [];
    final resolvedArtists = artists.isNotEmpty
        ? artists
        : (tag?.albumArtist != null
              ? [tag!.albumArtist!.trim()]
              : const <String>[]);

    final genres =
        tag?.genre
            ?.split(RegExp(r'[,;/]'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList() ??
        const [];

    return ExtractedTrackData(
      filePath: filePath,
      title: tag?.title?.trim().isNotEmpty == true
          ? tag!.title!.trim()
          : p.basenameWithoutExtension(filePath),
      albumName: tag?.album?.trim().isNotEmpty == true
          ? tag!.album!.trim()
          : null,
      artistNames: resolvedArtists,
      albumArtistName: tag?.albumArtist?.trim().isNotEmpty == true
          ? tag!.albumArtist!.trim()
          : null,
      genreNames: genres,
      trackNumber: tag?.trackNumber,
      discNumber: tag?.discNumber ?? 1,
      year: tag?.year,
      durationMs: durationMs,
      bitrate: effectiveBitrate,
      sampleRate: effectiveSampleRate,
      channels: effectiveChannels,
      codec: extClean.isNotEmpty ? extClean : null,
      fileSize: fileSize,
      modifiedAt: modifiedAt,
      embeddedLyrics: tag?.lyrics,
      replayGainTrackGain: replayGainTrackGain,
      replayGainTrackPeak: replayGainTrackPeak,
      waveformData: waveformData,
      thumbnailHash: thumbnailHash,
      albumThumbnailHash: albumThumbnailHash,
      artistThumbnailHash: artistThumbnailHash,
    );
  }

  static List<File> listCachedCoverFiles() {
    _ensureInitialized();
    if (!thumbnailsDirectory!.existsSync()) {
      return [];
    }
    final files = thumbnailsDirectory!.listSync(
      recursive: true,
      followLinks: false,
    );
    return files.whereType<File>().toList();
  }

  static List<File> listCachedThumbnails() => listCachedCoverFiles();

  static void disposeBridge() {
    ui.IsolateNameServer.removePortNameMapping(_kGpuBridgePortName);
    _gpuBridgePort?.close();
    _gpuBridgePort = null;
    _inFlightHashes.clear();
  }
}
