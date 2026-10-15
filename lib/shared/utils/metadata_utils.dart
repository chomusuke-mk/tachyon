import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:haudiotagger/haudiotagger.dart';
import 'package:miniaudio_player/miniaudio_player.dart';
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;
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

  static void init(Directory thumbnailsDir, Directory tempDir) {
    tempDirectory = tempDir;
    thumbnailsDirectory = thumbnailsDir;
    if (!thumbnailsDirectory!.existsSync()) {
      thumbnailsDirectory!.createSync(recursive: true);
    }
    if (!tempDirectory!.existsSync()) {
      tempDirectory!.createSync(recursive: true);
    }
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
    if (!tempDirectory!.existsSync()) return;
    await tempDirectory!.delete(recursive: true);
    await tempDirectory!.create(recursive: true);
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

  static Future<ExtractedTrackData?> extractTrackMetadata({
    required String filePath,
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
    AudioProperties? properties;
    try {
      tag = await Haudiotagger.read(filePath);
      properties = await Haudiotagger.readProperties(filePath);
      trackGain = ParserUtils.parseDouble(tag?.replayGainTrackGain);
      trackPeak = ParserUtils.parseDouble(tag?.replayGainTrackPeak);
    } catch (e) {
      debugPrint('[MetadataService] readMetadata error for $filePath: $e');
    }

    // Get Track Analysis
    AudioAnalysisResult? analysis;
    try {
      analysis = await MiniaudioPlayer.analyzeAudio(
        filePath,
        replayGain: trackGain == null,
        waveform: true,
        waveformPoints: 100,
      );
      trackGain = trackGain ?? analysis.replayGain?.gainDb;
      trackPeak = trackPeak ?? analysis.replayGain?.peak;
      waveformData = WaveformCodec.encode(analysis.waveform?.points);
    } catch (e) {
      debugPrint('[MetadataService] analyzeAudio error for $filePath: $e');
    }

    // Extract and cache cover art, album art, and artist images
    Uint8List? coverBytes;
    Uint8List? artistBytes;
    Uint8List? albumBytes;
    String? coverHash;
    String? albumThumbnailHash;
    String? artistThumbnailHash;
    if (tag != null && tag.pictures.isNotEmpty) {
      final pictures = tag.pictures.toList();
      // Cover
      pictures.sort((a, b) {
        final aPriority = coverPriority[a.pictureType] ?? 99;
        final bPriority = coverPriority[b.pictureType] ?? 99;
        return aPriority.compareTo(bPriority);
      });
      coverBytes = pictures.isNotEmpty ? pictures.first.bytes : null;
      coverHash = coverBytes != null && coverBytes.isNotEmpty
          ? ParserUtils.computeBytesHash(coverBytes)
          : null;
      // Album
      pictures.sort((a, b) {
        final aPriority = albumPriority[a.pictureType] ?? 99;
        final bPriority = albumPriority[b.pictureType] ?? 99;
        return aPriority.compareTo(bPriority);
      });
      albumBytes = pictures.isNotEmpty ? pictures.first.bytes : null;
      albumThumbnailHash = albumBytes != null && albumBytes.isNotEmpty
          ? ParserUtils.computeBytesHash(albumBytes)
          : null;
      // Artist
      pictures.sort((a, b) {
        final aPriority = artistPriority[a.pictureType] ?? 99;
        final bPriority = artistPriority[b.pictureType] ?? 99;
        return aPriority.compareTo(bPriority);
      });
      artistBytes = pictures.isNotEmpty ? pictures.first.bytes : null;
      artistThumbnailHash = artistBytes != null && artistBytes.isNotEmpty
          ? ParserUtils.computeBytesHash(artistBytes)
          : null;
    }

    // Write cover art, album art, and artist images if they don't exist
    final Map<String, Uint8List> hashToBytes = {};
    if (coverBytes != null && coverHash != null) {
      hashToBytes[coverHash] = coverBytes;
    }
    if (albumBytes != null && albumThumbnailHash != null) {
      hashToBytes[albumThumbnailHash] = albumBytes;
    }
    if (artistBytes != null && artistThumbnailHash != null) {
      hashToBytes[artistThumbnailHash] = artistBytes;
    }
    for (final entry in hashToBytes.entries) {
      final hash = entry.key;
      final bytes = entry.value;
      final file = File(getThumbnailFilePath(hash));
      if (!await file.exists()) {
        _writeTripleQualityImages(bytes, hash);
      }
    }
    return _buildExtractedTrackData(
      filePath: filePath,
      fileSize: size,
      modifiedAt: modifiedAt,
      tag: tag,
      properties: properties,
      analysis: analysis,
      replayGainTrackGain: trackGain,
      replayGainTrackPeak: trackPeak,
      waveformData: waveformData,
      thumbnailHash: coverHash,
      albumThumbnailHash: albumThumbnailHash,
      artistThumbnailHash: artistThumbnailHash,
    );
  }

  static Future<void> _writeTripleQualityImages(
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

    try {
      final decoded = img.decodeImage(rawBytes);
      if (decoded == null) {
        debugPrint('[CoverUtils] Failed to decode image for hash: $hash');
        return;
      }
      final minDim = math.min(decoded.width, decoded.height);
      final cropX = (decoded.width - minDim) ~/ 2;
      final cropY = (decoded.height - minDim) ~/ 2;

      final squareImage =
          (cropX == 0 &&
              cropY == 0 &&
              decoded.width == minDim &&
              decoded.height == minDim)
          ? decoded
          : img.copyCrop(
              decoded,
              x: cropX,
              y: cropY,
              width: minDim,
              height: minDim,
            );

      // 1. High Quality: 800x800
      final img.Image hqImage;
      if (minDim > AppDefaults.highQualityResolution) {
        hqImage = img.copyResize(
          squareImage,
          width: AppDefaults.highQualityResolution,
          height: AppDefaults.highQualityResolution,
          interpolation: img.Interpolation.linear,
        );
      } else {
        hqImage = squareImage;
      }

      // 2. Medium Quality: 250x250 (cascaded downsampling from hqImage)
      final img.Image mqImage;
      if (hqImage.width > AppDefaults.mediumQualityResolution) {
        mqImage = img.copyResize(
          hqImage,
          width: AppDefaults.mediumQualityResolution,
          height: AppDefaults.mediumQualityResolution,
          interpolation: img.Interpolation.linear,
        );
      } else {
        mqImage = hqImage;
      }

      // 3. Low Quality: 50x50 (cascaded downsampling from mqImage)
      final img.Image lqImage;
      if (mqImage.width > AppDefaults.lowQualityResolution) {
        lqImage = img.copyResize(
          mqImage,
          width: AppDefaults.lowQualityResolution,
          height: AppDefaults.lowQualityResolution,
          interpolation: img.Interpolation.linear,
        );
      } else {
        lqImage = mqImage;
      }

      final hqBytes = img.encodeJpg(hqImage, quality: 82);
      final mqBytes = img.encodeJpg(mqImage, quality: 78);
      final lqBytes = img.encodeJpg(lqImage, quality: 72);

      final writeFutures = <Future<void>>[];
      writeFutures.add(_safeAtomicWrite(fileHq, hqBytes));
      writeFutures.add(_safeAtomicWrite(fileMq, mqBytes));
      writeFutures.add(_safeAtomicWrite(fileLq, lqBytes));
      await Future.wait(writeFutures);
    } catch (e) {
      debugPrint('[CoverUtils] Error generating triple quality images: $e');
    }
  }

  static Future<void> _safeAtomicWrite(File targetFile, Uint8List bytes) async {
    _ensureInitialized();
    if (await targetFile.exists() && await targetFile.length() > 0) {
      return;
    }

    final rand = math.Random().nextInt(1 << 30);
    final fileName = p.basename(targetFile.path);
    final tempFile = File(
      p.join(tempDirectory!.path, '${fileName}_${pid}_$rand.tmp'),
    );

    try {
      await tempFile.writeAsBytes(bytes, flush: true);
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
        await targetFile.writeAsBytes(bytes, flush: true);
      } catch (_) {}
    }
  }

  static ExtractedTrackData _buildExtractedTrackData({
    required String filePath,
    required int fileSize,
    required int modifiedAt,
    Tag? tag,
    AudioProperties? properties,
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

    final effectiveBitrate =
        properties?.bitrate ??
        (analysis != null && analysis.bitrate > 0 ? analysis.bitrate : null);
    final effectiveSampleRate =
        properties?.sampleRate ??
        (analysis != null && analysis.sampleRate > 0
            ? analysis.sampleRate
            : null);
    final effectiveChannels =
        properties?.channels ??
        (analysis != null && analysis.channels > 0 ? analysis.channels : null);

    var durationMs = properties?.durationMicros != null
        ? (properties!.durationMicros!.toInt() / 1000).round()
        : (tag?.duration != null ? tag!.duration! * 1000 : 0);
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
      codec: properties?.codec ?? (extClean.isNotEmpty ? extClean : null),
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
}
