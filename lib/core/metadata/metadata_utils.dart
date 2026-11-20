import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:miniaudio_player/miniaudio_player.dart';
import 'package:path/path.dart' as p;
import 'package:tachyon/shared/utils/crypto_utils.dart';
import 'package:tachyon/shared/utils/parse_utils.dart';
import 'package:tachyon/shared/utils/waveform_codec.dart';

/// Quality levels for thumbnail images and cover art (used for RAM decoding bounds).
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
  final String? artworkUri;
  final String? albumArtworkUri;
  final String? artistArtworkUri;

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
    this.artworkUri,
    this.albumArtworkUri,
    this.artistArtworkUri,
  });
}

abstract final class MetadataUtils {
  static Directory? tempDirectory;
  static Directory? thumbnailsDirectory;

  static void init(String thumbnailsPath, String tempPath) {
    tempDirectory = Directory(tempPath);
    thumbnailsDirectory = Directory(thumbnailsPath);
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
    try {
      if (await tempDirectory!.exists()) {
        await tempDirectory!.delete(recursive: true);
      }
      if (!await tempDirectory!.exists()) {
        await tempDirectory!.create(recursive: true);
      }
    } catch (_) {}
  }

  /// Returns the canonical file path for an artwork file with given [hash] without extension.
  static String getArtworkPath(String hash) {
    _ensureInitialized();
    final cleanHash = p.basename(hash);
    return p.join(thumbnailsDirectory!.path, cleanHash);
  }

  /// Extracts the hash from an artwork file path.
  static String extractHashFromArtworkPath(String artworkPath) {
    return p.basename(artworkPath);
  }

  /// Checks whether an artwork file exists in cache for [artworkUri].
  static bool hasCachedArtwork(String artworkUri) {
    _ensureInitialized();
    final f = File(artworkUri);
    if (f.existsSync() && f.lengthSync() > 0) return true;
    final fallback = File(getArtworkPath(p.basename(artworkUri)));
    return fallback.existsSync() && fallback.lengthSync() > 0;
  }

  /// Selects the highest-priority embedded picture according to [priorityMap].
  static AudioPicture? pickBestCoverPicture(
    List<AudioPicture> pictures, {
    Map<PictureType, int> priorityMap = coverPriority,
    bool fallbackToFirst = true,
  }) {
    if (pictures.isEmpty) return null;
    AudioPicture? best;
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

  /// Persists raw image bytes once into disk deduplicated by SHA-256 hash without extension.
  /// Flutter image codecs inspect binary magic numbers directly, avoiding extension dependencies.
  /// Returns the content hash of the persisted cover art image.
  static Future<String?> saveCoverBytes(
    Uint8List rawBytes, {
    bool useSync = false,
    Set<String>? knownSavedHashes,
  }) async {
    _ensureInitialized();
    if (rawBytes.isEmpty) return null;
    final hash = CryptoUtils.computeBytesHash(rawBytes);
    if (knownSavedHashes != null && knownSavedHashes.contains(hash)) {
      return hash;
    }
    final targetFile = File(getArtworkPath(hash));
    if (!targetFile.existsSync() || targetFile.lengthSync() == 0) {
      if (useSync) {
        _safeAtomicWriteSync(targetFile, rawBytes);
      } else {
        await _safeAtomicWrite(targetFile, rawBytes);
      }
    }
    knownSavedHashes?.add(hash);
    return hash;
  }

  static Future<ExtractedTrackData?> extractTrackMetadata({
    required String filePath,
    bool useSync = false,
    int? knownFileSize,
    int? knownModifiedAt,
    Set<String>? knownSavedHashes,
  }) async {
    _ensureInitialized();
    final file = File(filePath);
    int size = knownFileSize ?? 0;
    int modifiedAt = knownModifiedAt ?? 0;

    if (knownFileSize == null || knownModifiedAt == null) {
      if (useSync) {
        if (!file.existsSync()) return null;
        try {
          final stat = file.statSync();
          size = stat.size;
          modifiedAt = stat.modified.millisecondsSinceEpoch;
        } catch (_) {}
      } else {
        if (!await file.exists()) return null;
        try {
          final stat = await file.stat();
          size = stat.size;
          modifiedAt = stat.modified.millisecondsSinceEpoch;
        } catch (_) {}
      }
    }

    // Single-pass native Rust extraction (metadata, audio info, ReplayGain, waveform).
    // Chromaprint is explicitly disabled.
    AudioAnalysisResult? analysis;
    try {
      if (useSync) {
        analysis = MiniaudioPlayer.analyzeAudioSync(
          filePath,
          metadata: true,
          replayGain: true,
          waveform: true,
          chromaprint: false,
          waveformPoints: 100,
        );
      } else {
        analysis = await MiniaudioPlayer.analyzeAudio(
          filePath,
          metadata: true,
          replayGain: true,
          waveform: true,
          chromaprint: false,
          waveformPoints: 100,
        );
      }
    } catch (e) {
      if (knownFileSize != null && !file.existsSync()) {
        return null;
      }
      debugPrint('[MetadataService] analyzeAudio error for $filePath: $e');
    }

    final AudioMetadata? meta = analysis?.metadata;
    final AudioInfo? info = analysis?.audioInfo;

    final double? trackGain =
        ParseUtils.parseDouble(meta?.replayGainTrackGain) ??
        analysis?.replayGain?.gainDb;
    final double? trackPeak =
        ParseUtils.parseDouble(meta?.replayGainTrackPeak) ??
        analysis?.replayGain?.peak;
    final String? waveformData =
        WaveformCodec.encode(analysis?.waveform?.points);

    // Extract and cache embedded cover art deduplicated by hash
    String? coverUri;
    String? albumArtworkUri;
    String? artistArtworkUri;

    final pictures = meta?.pictures ?? const <AudioPicture>[];
    if (pictures.isNotEmpty) {
      final coverPic = pickBestCoverPicture(
        pictures,
        priorityMap: coverPriority,
        fallbackToFirst: true,
      );
      final albumPic = pickBestCoverPicture(
        pictures,
        priorityMap: albumPriority,
        fallbackToFirst: false,
      );
      final artistPic = pickBestCoverPicture(
        pictures,
        priorityMap: artistPriority,
        fallbackToFirst: false,
      );

      if (coverPic != null && coverPic.bytes.isNotEmpty) {
        coverUri = await saveCoverBytes(
          coverPic.bytes,
          useSync: useSync,
          knownSavedHashes: knownSavedHashes,
        );
      }
      if (albumPic != null && albumPic.bytes.isNotEmpty) {
        albumArtworkUri = (albumPic == coverPic)
            ? coverUri
            : await saveCoverBytes(
                albumPic.bytes,
                useSync: useSync,
                knownSavedHashes: knownSavedHashes,
              );
      }
      if (artistPic != null && artistPic.bytes.isNotEmpty) {
        artistArtworkUri = (artistPic == coverPic)
            ? coverUri
            : ((artistPic == albumPic)
                ? albumArtworkUri
                : await saveCoverBytes(
                    artistPic.bytes,
                    useSync: useSync,
                    knownSavedHashes: knownSavedHashes,
                  ));
      }
    }

    return _buildExtractedTrackData(
      filePath: filePath,
      fileSize: size,
      modifiedAt: modifiedAt,
      meta: meta,
      info: info,
      replayGainTrackGain: trackGain,
      replayGainTrackPeak: trackPeak,
      waveformData: waveformData,
      artworkUri: coverUri,
      albumArtworkUri: albumArtworkUri,
      artistArtworkUri: artistArtworkUri,
    );
  }

  static void _safeAtomicWriteSync(File targetFile, Uint8List bytes) {
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
      tempFile.writeAsBytesSync(bytes, flush: false);
      tempFile.renameSync(targetFile.path);
    } catch (_) {
      try {
        if (tempFile.existsSync()) {
          tempFile.deleteSync();
        }
      } catch (_) {}
      if (targetFile.existsSync() && targetFile.lengthSync() > 0) {
        return;
      }
      try {
        targetFile.writeAsBytesSync(bytes, flush: false);
      } catch (_) {}
    }
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
    AudioMetadata? meta,
    AudioInfo? info,
    double? replayGainTrackGain,
    double? replayGainTrackPeak,
    String? waveformData,
    String? artworkUri,
    String? albumArtworkUri,
    String? artistArtworkUri,
  }) {
    final ext = p.extension(filePath).toLowerCase();
    final extClean = ext.replaceAll('.', '').toUpperCase();

    final effectiveBitrate = info != null && info.bitrate > 0
        ? info.bitrate
        : null;

    final effectiveSampleRate = info != null && info.sampleRate > 0
        ? info.sampleRate
        : null;

    final effectiveChannels = info != null && info.channels > 0
        ? info.channels
        : null;

    final durationMs = info?.duration?.inMilliseconds ?? 0;

    final codec =
        (info != null && info.codec.isNotEmpty && info.codec != 'Unknown')
            ? info.codec
            : (extClean.isNotEmpty ? extClean : null);

    final artists =
        meta?.trackArtist
            ?.split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList() ??
        const [];
    final trimmedAlbumArtist = meta?.albumArtist?.trim();
    final resolvedArtists = artists.isNotEmpty
        ? artists
        : (trimmedAlbumArtist != null && trimmedAlbumArtist.isNotEmpty
            ? [trimmedAlbumArtist]
            : const <String>[]);

    final genres =
        meta?.genre
            ?.split(RegExp(r'[,;/]'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList() ??
        const [];

    return ExtractedTrackData(
      filePath: filePath,
      title: meta?.title?.trim().isNotEmpty == true
          ? meta!.title!.trim()
          : p.basenameWithoutExtension(filePath),
      albumName: meta?.album?.trim().isNotEmpty == true
          ? meta!.album!.trim()
          : null,
      artistNames: resolvedArtists,
      albumArtistName:
          trimmedAlbumArtist != null && trimmedAlbumArtist.isNotEmpty
              ? trimmedAlbumArtist
              : null,
      genreNames: genres,
      trackNumber: meta?.trackNumber,
      discNumber: meta?.discNumber ?? 1,
      year: meta?.year,
      durationMs: durationMs,
      bitrate: effectiveBitrate,
      sampleRate: effectiveSampleRate,
      channels: effectiveChannels,
      codec: codec,
      fileSize: fileSize,
      modifiedAt: modifiedAt,
      embeddedLyrics: meta?.lyrics?.trim().isNotEmpty == true
          ? meta!.lyrics
          : null,
      replayGainTrackGain: replayGainTrackGain,
      replayGainTrackPeak: replayGainTrackPeak,
      waveformData: waveformData,
      artworkUri: artworkUri,
      albumArtworkUri: albumArtworkUri,
      artistArtworkUri: artistArtworkUri,
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
