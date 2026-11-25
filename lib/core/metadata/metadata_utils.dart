import 'package:flutter/foundation.dart';
import 'package:miniaudio_player/miniaudio_player.dart';
import 'package:path/path.dart' as p;
import 'package:tachyon/core/storage/persistent_binary_storage.dart';
import 'package:tachyon/shared/utils/crypto_utils.dart';
import 'package:tachyon/shared/utils/parse_utils.dart';
import 'package:tachyon/shared/utils/waveform_codec.dart';

/// Quality levels for thumbnail images and cover art (used for RAM decoding bounds).
enum ThumbnailQuality {
  /// Low-resolution thumbnail suitable for compact list items.
  low,

  /// Medium-resolution thumbnail suitable for grid cards and standard tiles.
  medium,

  /// High-resolution artwork suitable for full-screen or detail views.
  high,
}

/// Priority ranking of embedded [PictureType] values when selecting track cover art.
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

/// Priority ranking of embedded [PictureType] values when selecting artist artwork.
const Map<PictureType, int> artistPriority = {
  PictureType.leadArtist: 0,
  PictureType.artist: 1,
  PictureType.band: 2,
  PictureType.bandLogo: 3,
  PictureType.publisherLogo: 4,
  PictureType.composer: 5,
};

/// Priority ranking of embedded [PictureType] values when selecting album artwork.
const Map<PictureType, int> albumPriority = {
  PictureType.coverFront: 0,
  PictureType.coverBack: 1,
  PictureType.leaflet: 2,
  PictureType.media: 3,
  PictureType.illustration: 4,
  PictureType.brightFish: 5,
};

/// Extracted audio metadata, technical properties, and cached artwork URIs for a track.
class ExtractedTrackData {
  /// Source file path, OPFS path, or HTTP URL of the audio track.
  final String filePath;

  /// Resolved track title (falling back to filename or URL segment).
  final String title;

  /// List of individual track artist names.
  final List<String> artistNames;

  /// Album artist name, if specified in tags.
  final String? albumArtistName;

  /// Album title, if specified in tags.
  final String? albumName;

  /// Track index within the disc or album, if available.
  final int? trackNumber;

  /// Disc index within a multi-disc release (defaults to `1`).
  final int? discNumber;

  /// Release year, if specified in tags.
  final int? year;

  /// Total track duration in milliseconds.
  final int durationMs;

  /// Audio bitrate in bits per second, if available.
  final int? bitrate;

  /// Audio sample rate in Hz, if available.
  final int? sampleRate;

  /// Number of audio channels, if available.
  final int? channels;

  /// Audio codec name or uppercase file extension fallback.
  final String? codec;

  /// File size in bytes.
  final int fileSize;

  /// File modification timestamp used for incremental scan diffing.
  final int modifiedAt;

  /// Track ReplayGain adjustment in dB, if available.
  final double? replayGainTrackGain;

  /// Track ReplayGain peak amplitude ratio, if available.
  final double? replayGainTrackPeak;

  /// Encoded waveform amplitude string generated from audio samples, if available.
  final String? waveformData;

  /// List of genre names parsed from metadata tags.
  final List<String> genreNames;

  /// Embedded lyrics text extracted from audio tags, if present.
  final String? embeddedLyrics;

  /// Content hash URI of the cached track cover image, if present.
  final String? artworkUri;

  /// Content hash URI of the cached album cover image, if present.
  final String? albumArtworkUri;

  /// Content hash URI of the cached artist image, if present.
  final String? artistArtworkUri;

  /// Creates an [ExtractedTrackData] instance with extracted track metadata and properties.
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

/// Static utilities for audio metadata extraction and artwork cache management.
abstract final class MetadataUtils {
  /// Temporary working directory managed by [PersistentBinaryStorage], if initialized.
  static StorageDirectory? get tempDirectory =>
      PersistentBinaryStorage.tempDirectory;

  /// Cached cover art directory managed by [PersistentBinaryStorage], if initialized.
  static StorageDirectory? get thumbnailsDirectory =>
      PersistentBinaryStorage.thumbnailsDirectory;

  /// Initializes storage directories synchronously at [thumbnailsPath] and [tempPath].
  static void init(String thumbnailsPath, String tempPath) {
    PersistentBinaryStorage.init(thumbnailsPath, tempPath);
  }

  /// Initializes storage directories asynchronously using optional [thumbnailsPath] and [tempPath].
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

  /// Clears all temporary files from the configured temporary directory.
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
    int? knownFileSize,
    int? knownModifiedAt,
    Set<String>? knownSavedHashes,
  }) async {
    _ensureInitialized();

    final isRemoteUrl =
        filePath.startsWith('http://') || filePath.startsWith('https://');

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
    } else {
      if (knownFileSize == null || knownModifiedAt == null) {
        final stat = await PersistentBinaryStorage.statFile(filePath);
        if (stat == null) return null;
        size = stat.size;
        modifiedAt = stat.modifiedAt;
      }
      analysisSource = filePath;
    }

    // Single-pass asynchronous extraction across all sources (local, OPFS, and remote URLs):
    // extracts metadata, audio info, ReplayGain, and 150-point waveform.
    // Chromaprint is explicitly disabled everywhere.
    AudioAnalysisResult? analysis;
    try {
      analysis = await MiniaudioPlayer.analyzeAudio(
        analysisSource,
        metadata: true,
        replayGain: true,
        waveform: true,
        chromaprint: false,
        waveformPoints: 150,
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

  /// Resolves a human-readable fallback title from a local path, OPFS path, or HTTP URL.
  static String fallbackTitleFromPathOrUrl(String pathOrUrl) {
    final trimmed = pathOrUrl.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      final uri = Uri.tryParse(trimmed);
      if (uri != null && uri.pathSegments.isNotEmpty) {
        final lastSeg = safeDecodePercent(uri.pathSegments.last).trim();
        if (lastSeg.isNotEmpty) {
          final withoutExt = p.basenameWithoutExtension(lastSeg);
          return withoutExt.isNotEmpty ? withoutExt : lastSeg;
        }
      }
      return safeDecodePercent(trimmed);
    }
    final decoded = safeDecodePercent(trimmed);
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

  /// Returns references to all cover image files currently stored in the thumbnail cache.
  static List<StorageFileRef> listCachedCoverFiles() {
    return PersistentBinaryStorage.listCachedCoverFiles();
  }

  /// Deletes cached cover files whose filenames are not in [validFileNames].
  static Future<void> purgeUnusedCovers(Set<String> validFileNames) async {
    await PersistentBinaryStorage.purgeUnusedCovers(validFileNames);
  }
}
