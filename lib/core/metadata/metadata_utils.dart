import 'package:flutter/foundation.dart';
import 'package:miniaudio_player/miniaudio_player.dart';
import 'package:path/path.dart' as p;
import 'package:tachyon/core/storage/persistent_binary_storage.dart';
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
  static StorageDirectory? get tempDirectory =>
      PersistentBinaryStorage.tempDirectory;
  static StorageDirectory? get thumbnailsDirectory =>
      PersistentBinaryStorage.thumbnailsDirectory;

  static void init(String thumbnailsPath, String tempPath) {
    PersistentBinaryStorage.init(thumbnailsPath, tempPath);
  }

  static Future<void> initAsync({
    String? thumbnailsPath,
    String? tempPath,
  }) async {
    await PersistentBinaryStorage.initAsync(
      thumbnailsPath: thumbnailsPath,
      tempPath: tempPath,
    );
  }

  static void _ensureInitialized() {
    PersistentBinaryStorage.ensureInitialized();
  }

  static Future<void> clearTempDirectory() async {
    await PersistentBinaryStorage.clearTempDirectory();
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

  /// Checks whether an artwork file exists in cache (disk or OPFS) for [artworkUri].
  static bool hasCachedArtwork(String artworkUri) {
    _ensureInitialized();
    final cleanHash = p.basename(artworkUri);
    return PersistentBinaryStorage.hasCachedArtwork(
      artworkUri,
      getArtworkPath(cleanHash),
    );
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

  /// Persists raw image bytes once into persistent storage (disk on Native,
  /// OPFS on Web) deduplicated by SHA-256 hash without extension.
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
    await PersistentBinaryStorage.saveCoverBytes(
      hash,
      getArtworkPath(hash),
      rawBytes,
    );
    knownSavedHashes?.add(hash);
    return hash;
  }

  /// Performs non-blocking asynchronous single-pass audio extraction via
  /// `MiniaudioPlayer.analyzeAudio` (runs on native Rust threads or Web Worker).
  static Future<ExtractedTrackData?> extractTrackMetadata({
    required String filePath,
    bool useSync = false,
    int? knownFileSize,
    int? knownModifiedAt,
    Set<String>? knownSavedHashes,
  }) async {
    _ensureInitialized();

    final isRemoteUrl =
        filePath.startsWith('http://') || filePath.startsWith('https://');
    final isOpfsAudio = filePath.startsWith('opfs://');

    int size = knownFileSize ?? 0;
    int modifiedAt = knownModifiedAt ?? 0;
    Object analysisSource = filePath;

    if (isRemoteUrl) {
      if (modifiedAt <= 0) modifiedAt = 1;
      final parsedUri = Uri.tryParse(filePath);
      if (parsedUri == null || !parsedUri.hasScheme || parsedUri.host.isEmpty) {
        return null;
      }
      analysisSource = parsedUri;
    } else if (isOpfsAudio) {
      final bytes = await PersistentBinaryStorage.readAudioBytesAsync(filePath);
      if (bytes == null || bytes.isEmpty) return null;
      final stat = await PersistentBinaryStorage.statFile(filePath);
      size = knownFileSize ?? stat?.size ?? bytes.length;
      modifiedAt = knownModifiedAt ?? stat?.modifiedAt ?? 1;
      analysisSource = bytes;
    } else {
      if (knownFileSize == null || knownModifiedAt == null) {
        final stat = await PersistentBinaryStorage.statFile(filePath);
        if (stat == null) return null;
        size = stat.size;
        modifiedAt = stat.modifiedAt;
      }
      analysisSource = filePath;
    }

    // Single-pass asynchronous extraction:
    // - For local/OPFS files: extracts metadata, audio info, ReplayGain, and waveform.
    // - For remote HTTP/HTTPS URLs: extracts header/tag metadata, embedded ReplayGain tags,
    //   audio info, and embedded cover art via HTTP Range requests without downloading full PCM.
    // Chromaprint is explicitly disabled everywhere.
    AudioAnalysisResult? analysis;
    try {
      analysis = await MiniaudioPlayer.analyzeAudio(
        analysisSource,
        metadata: true,
        replayGain: !isRemoteUrl,
        waveform: !isRemoteUrl,
        chromaprint: false,
        waveformPoints: 100,
      );
    } catch (e) {
      if (!isRemoteUrl &&
          knownFileSize != null &&
          !await PersistentBinaryStorage.fileExists(filePath)) {
        return null;
      }
      debugPrint('[MetadataService] analyzeAudio error for $filePath: $e');
    }

    final AudioMetadata? meta = analysis?.metadata;
    final AudioInfo? info = analysis?.audioInfo;
    if (size <= 0 && info?.fileSize != null && info!.fileSize! > 0) {
      size = info.fileSize!;
    }

    final double? trackGain =
        ParseUtils.parseDouble(meta?.replayGainTrackGain) ??
        analysis?.replayGain?.gainDb;
    final double? trackPeak =
        ParseUtils.parseDouble(meta?.replayGainTrackPeak) ??
        analysis?.replayGain?.peak;
    final String? waveformData = WaveformCodec.encode(
      analysis?.waveform?.points,
    );

    // Extract and cache embedded cover art deduplicated by hash (async OPFS / disk)
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
          knownSavedHashes: knownSavedHashes,
        );
      }
      if (albumPic != null && albumPic.bytes.isNotEmpty) {
        albumArtworkUri = (albumPic == coverPic)
            ? coverUri
            : await saveCoverBytes(
                albumPic.bytes,
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

  static final RegExp _percentEncodedRunPattern = RegExp(
    r'(?:%[0-9A-Fa-f]{2})+',
  );

  /// Safely decodes valid `%XX` UTF-8 sequences without throwing [ArgumentError]
  /// when the input is already decoded or contains literal `%` characters.
  static String safeDecodePercent(String input) {
    if (!input.contains('%')) return input;
    return input.replaceAllMapped(_percentEncodedRunPattern, (match) {
      final segment = match.group(0)!;
      try {
        return Uri.decodeComponent(segment);
      } catch (_) {
        return segment;
      }
    });
  }

  /// Resolves a human-readable fallback title from a local path, OPFS URI, or HTTP URL.
  static String fallbackTitleFromPathOrUrl(String pathOrUrl) {
    if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
      final uri = Uri.tryParse(pathOrUrl);
      if (uri != null && uri.pathSegments.isNotEmpty) {
        final lastSeg = safeDecodePercent(uri.pathSegments.last).trim();
        if (lastSeg.isNotEmpty) {
          final withoutExt = p.basenameWithoutExtension(lastSeg);
          return withoutExt.isNotEmpty ? withoutExt : lastSeg;
        }
      }
      return safeDecodePercent(pathOrUrl);
    }
    if (pathOrUrl.startsWith('opfs://audio/')) {
      final rawName = safeDecodePercent(
        pathOrUrl.substring('opfs://audio/'.length),
      );
      final withoutExt = p.basenameWithoutExtension(rawName);
      return withoutExt.isNotEmpty ? withoutExt : rawName;
    }
    final decoded = safeDecodePercent(pathOrUrl);
    final base = p.basenameWithoutExtension(decoded);
    return base.isNotEmpty ? base : p.basename(decoded);
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
          : fallbackTitleFromPathOrUrl(filePath),
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

  static List<StorageFileRef> listCachedCoverFiles() {
    return PersistentBinaryStorage.listCachedCoverFiles();
  }

  static Future<void> purgeUnusedCovers(Set<String> validFileNames) async {
    await PersistentBinaryStorage.purgeUnusedCovers(validFileNames);
  }
}
