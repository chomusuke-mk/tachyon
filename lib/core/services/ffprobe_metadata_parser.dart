import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

import '../../features/library/domain/track.dart';

/// Extracted properties of the primary audio stream.
class AudioStreamProperties {
  final String? codec;
  final int? sampleRate;
  final int? channels;
  final int? bitsPerSample;
  final int? bitrate;
  final int durationMs;

  const AudioStreamProperties({
    this.codec,
    this.sampleRate,
    this.channels,
    this.bitsPerSample,
    this.bitrate,
    this.durationMs = 0,
  });
}

/// Extracted and normalized audio tags.
class TagData {
  final String title;
  final String? album;
  final String? artist;
  final List<String> artists;
  final String? albumArtist;
  final int? trackNumber;
  final int? trackTotal;
  final int discNumber;
  final int? discTotal;
  final int? year;
  final List<String> genres;
  final String? lyrics;

  const TagData({
    required this.title,
    this.album,
    this.artist,
    this.artists = const [],
    this.albumArtist,
    this.trackNumber,
    this.trackTotal,
    this.discNumber = 1,
    this.discTotal,
    this.year,
    this.genres = const [],
    this.lyrics,
  });
}

/// Pure Dart parser for `ffprobe -v quiet -print_format json -show_format -show_streams` output.
class FfprobeMetadataParser {
  const FfprobeMetadataParser();

  static final RegExp _yearRegex = RegExp(r'\b(19\d{2}|20\d{2})\b');
  static final RegExp _featParenRegex = RegExp(
    r'[\(\[]\s*(?:feat\.?|ft\.?|featuring)\s+([^\)\]]+)[\)\]]',
    caseSensitive: false,
  );
  static final RegExp _artistSplitRegex = RegExp(
    r'(?:\s*[/;,]\s*|\s+(?:feat|ft|featuring)\.?\s+)',
    caseSensitive: false,
  );
  static final RegExp _genreSplitRegex = RegExp(r'\s*[/;,]\s*');
  static final RegExp _numericCleanRegex = RegExp(r'\D');
  static final RegExp _trackNumberSplitRegex =
      RegExp(r'[/\\-]|\s+of\s+', caseSensitive: false);

  /// Parses the complete ffprobe JSON output into a domain [Track] entity.
  Track parse({
    required String jsonString,
    required String filePath,
    int? fileSize,
    int? modifiedAt,
    bool hasCover = false,
  }) {
    Map<String, dynamic> jsonMap;
    try {
      jsonMap = json.decode(jsonString) as Map<String, dynamic>;
    } catch (_) {
      jsonMap = const {};
    }

    final format = jsonMap['format'] as Map<String, dynamic>? ?? const {};
    final streams = (jsonMap['streams'] as List<dynamic>?) ?? const [];

    final audioProps = parseAudioStream(streams, format);
    final tags = parseTags(format, streams, filePath);

    // Resolve file size and modified timestamp
    int resolvedFileSize = fileSize ?? 0;
    if (resolvedFileSize <= 0) {
      final sizeStr = format['size']?.toString();
      if (sizeStr != null) {
        resolvedFileSize = int.tryParse(sizeStr) ?? 0;
      }
    }
    if (resolvedFileSize <= 0) {
      try {
        final f = File(filePath);
        if (f.existsSync()) {
          resolvedFileSize = f.lengthSync();
        }
      } catch (_) {}
    }

    int resolvedModifiedAt = modifiedAt ?? 0;
    if (resolvedModifiedAt <= 0) {
      try {
        final f = File(filePath);
        if (f.existsSync()) {
          resolvedModifiedAt = f.lastModifiedSync().millisecondsSinceEpoch;
        }
      } catch (_) {}
    }

    final resolvedArtists = tags.artists.isNotEmpty
        ? tags.artists
        : (tags.artist != null && tags.artist != 'Unknown Artist'
            ? [tags.artist!]
            : const <String>[]);

    return Track(
      uri: filePath,
      title: tags.title.isNotEmpty
          ? tags.title
          : p.basenameWithoutExtension(filePath),
      album: tags.album ?? 'Unknown Album',
      artist: tags.artist ??
          (resolvedArtists.isNotEmpty
              ? resolvedArtists.first
              : 'Unknown Artist'),
      artists: resolvedArtists,
      albumArtist: tags.albumArtist,
      trackNumber: tags.trackNumber,
      discNumber: tags.discNumber,
      year: tags.year,
      durationMs: audioProps.durationMs,
      bitrate: audioProps.bitrate,
      sampleRate: audioProps.sampleRate,
      channels: audioProps.channels,
      codec: audioProps.codec,
      fileSize: resolvedFileSize,
      modifiedAt: resolvedModifiedAt,
      lyrics: tags.lyrics,
      hasCover: hasCover,
      genres: tags.genres,
    );
  }

  /// Extracts audio stream attributes such as codec, sample rate, channels, bit rate, and duration.
  AudioStreamProperties parseAudioStream(
    List<dynamic> streams,
    Map<String, dynamic> format,
  ) {
    Map<String, dynamic>? audioStream;
    for (final s in streams) {
      if (s is Map<String, dynamic> &&
          s['codec_type']?.toString().toLowerCase() == 'audio') {
        audioStream = s;
        break;
      }
    }

    final codec = audioStream?['codec_name']?.toString().toLowerCase();

    final sampleRateStr = audioStream?['sample_rate']?.toString();
    final sampleRate =
        sampleRateStr != null ? int.tryParse(sampleRateStr) : null;

    final channelsRaw = audioStream?['channels'];
    final channels = channelsRaw is int
        ? channelsRaw
        : (channelsRaw != null ? int.tryParse(channelsRaw.toString()) : null);

    final bitsPerSampleRaw =
        audioStream?['bits_per_sample'] ?? audioStream?['bits_per_raw_sample'];
    int? bitsPerSample;
    if (bitsPerSampleRaw is int && bitsPerSampleRaw > 0) {
      bitsPerSample = bitsPerSampleRaw;
    } else if (bitsPerSampleRaw != null) {
      final parsed = int.tryParse(bitsPerSampleRaw.toString());
      if (parsed != null && parsed > 0) bitsPerSample = parsed;
    }

    final streamBitrateStr = audioStream?['bit_rate']?.toString();
    final formatBitrateStr = format['bit_rate']?.toString();
    final bitrate = streamBitrateStr != null
        ? int.tryParse(streamBitrateStr)
        : (formatBitrateStr != null ? int.tryParse(formatBitrateStr) : null);

    final durationSecStr = format['duration']?.toString() ??
        audioStream?['duration']?.toString();
    int durationMs = 0;
    if (durationSecStr != null) {
      final sec = double.tryParse(durationSecStr);
      if (sec != null && sec > 0) {
        durationMs = (sec * 1000).round();
      }
    }

    return AudioStreamProperties(
      codec: codec,
      sampleRate: sampleRate,
      channels: channels,
      bitsPerSample: bitsPerSample,
      bitrate: bitrate,
      durationMs: durationMs,
    );
  }

  /// Checks if any stream in the ffprobe output is an attached video/picture stream.
  bool hasAttachedPicture(Map<String, dynamic> jsonMap) {
    final streams = jsonMap['streams'] as List<dynamic>?;
    if (streams == null) return false;

    for (final s in streams) {
      if (s is Map<String, dynamic>) {
        final codecType = s['codec_type']?.toString().toLowerCase();
        final disposition = s['disposition'];
        if (codecType == 'video' && disposition is Map) {
          final attachedPic = disposition['attached_pic'];
          if (attachedPic == 1 || attachedPic == '1' || attachedPic == true) {
            return true;
          }
        }
      }
    }
    return false;
  }

  /// Extracts and normalizes metadata tags from format and stream tag dictionaries.
  TagData parseTags(
    Map<String, dynamic> format,
    List<dynamic> streams,
    String filePath,
  ) {
    // Collect and uppercase all tags, prioritizing format tags then audio stream tags
    final normalizedTags = <String, String>{};

    void ingest(dynamic tagsObj) {
      if (tagsObj is Map) {
        for (final entry in tagsObj.entries) {
          final key = entry.key.toString().toUpperCase().trim();
          final val = entry.value?.toString().trim() ?? '';
          if (val.isNotEmpty && !normalizedTags.containsKey(key)) {
            normalizedTags[key] = val;
          }
        }
      }
    }

    ingest(format['tags']);
    for (final s in streams) {
      if (s is Map && s['codec_type']?.toString().toLowerCase() == 'audio') {
        ingest(s['tags']);
      }
    }

    // 1. Title
    final titleRaw = normalizedTags['TITLE'] ??
        normalizedTags['TIT2'] ??
        normalizedTags['NAME'] ??
        p.basenameWithoutExtension(filePath);
    final title = titleRaw.trim();

    // 2. Artist & Split Artists
    final rawArtist = normalizedTags['ARTIST'] ??
        normalizedTags['TPE1'] ??
        normalizedTags['PERFORMER'];
    final artists = splitArtists(rawArtist);
    final primaryArtist = artists.isNotEmpty
        ? artists.first
        : (rawArtist != null && rawArtist.trim().isNotEmpty
            ? rawArtist.trim()
            : 'Unknown Artist');

    // 3. Album Artist
    final rawAlbumArtist = normalizedTags['ALBUM_ARTIST'] ??
        normalizedTags['ALBUMARTIST'] ??
        normalizedTags['ALBUM ARTIST'] ??
        normalizedTags['TPE2'];
    final albumArtist = rawAlbumArtist?.trim();

    // 4. Album
    final rawAlbum = normalizedTags['ALBUM'] ?? normalizedTags['TALB'];
    final album = (rawAlbum != null && rawAlbum.trim().isNotEmpty)
        ? rawAlbum.trim()
        : 'Unknown Album';

    // 5. Track Number
    final rawTrack = normalizedTags['TRACK'] ??
        normalizedTags['TRACKNUMBER'] ??
        normalizedTags['TRCK'];
    final (trackNumber, trackTotal) = parseTrackNumber(rawTrack);

    // 6. Disc Number
    final rawDisc = normalizedTags['DISC'] ??
        normalizedTags['DISCNUMBER'] ??
        normalizedTags['TPOS'];
    final (discNumber, discTotal) = parseDiscNumber(rawDisc);

    // 7. Year
    final rawYear = normalizedTags['DATE'] ??
        normalizedTags['YEAR'] ??
        normalizedTags['TYER'] ??
        normalizedTags['TDRC'] ??
        normalizedTags['ORIGINALDATE'] ??
        normalizedTags['ORIGINALYEAR'];
    final year = parseYear(rawYear);

    // 8. Genres
    final rawGenre = normalizedTags['GENRE'] ?? normalizedTags['TCON'];
    final genres = splitGenres(rawGenre);

    // 9. Lyrics
    final lyrics = normalizedTags['LYRICS'] ??
        normalizedTags['UNSYNCEDLYRICS'] ??
        normalizedTags['USLT'] ??
        normalizedTags['LYRICS-ENG'];

    return TagData(
      title: title,
      album: album,
      artist: primaryArtist,
      artists: artists,
      albumArtist: albumArtist,
      trackNumber: trackNumber,
      trackTotal: trackTotal,
      discNumber: discNumber,
      discTotal: discTotal,
      year: year,
      genres: genres,
      lyrics: lyrics?.trim(),
    );
  }

  /// Splits an artist tag into individual artists, handling delimiters
  /// (`/`, `;`, `,`, `feat.`, `ft.`, `featuring`) and preserving special cases like `AC/DC`.
  List<String> splitArtists(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    final trimmed = raw.trim();

    // Extract featuring clauses enclosed in brackets or parentheses: e.g. "Song (feat. SZA)"
    final featMatches = <String>[];
    for (final match in _featParenRegex.allMatches(trimmed)) {
      final featContent = match.group(1)?.trim();
      if (featContent != null && featContent.isNotEmpty) {
        featMatches.add(featContent);
      }
    }
    final cleaned = trimmed.replaceAll(_featParenRegex, '');

    // Protect "AC/DC" or similar slash-based names before splitting on "/"
    const acDcPlaceholder = '___AC_DC___';
    final protected = cleaned.replaceAll(
      RegExp(r'\bAC/DC\b', caseSensitive: false),
      acDcPlaceholder,
    );

    final parts = protected.split(_artistSplitRegex);
    final results = <String>{};

    for (final p in parts) {
      final restored = p.replaceAll(acDcPlaceholder, 'AC/DC').trim();
      if (restored.isNotEmpty) {
        results.add(restored);
      }
    }

    for (final f in featMatches) {
      final subParts = f.split(_artistSplitRegex);
      for (final sp in subParts) {
        final cl = sp.trim();
        if (cl.isNotEmpty) {
          results.add(cl);
        }
      }
    }

    return results.toList();
  }

  /// Splits a genre tag into individual cleaned genres, stripping ID3v1 codes like `(17)Rock`.
  List<String> splitGenres(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    final parts = raw.split(_genreSplitRegex);
    final results = <String>{};

    for (final p in parts) {
      var genre = p.trim();
      if (genre.isEmpty) continue;

      // Strip ID3v1 genre numbers like "(17) Rock" or "(17)"
      genre = genre.replaceAll(RegExp(r'^\(\d+\)\s*'), '').trim();
      if (genre.isNotEmpty) {
        results.add(genre);
      }
    }
    return results.toList();
  }

  /// Parses track number and total tracks from strings like `"3"`, `"03/12"`, `"3 of 12"`.
  (int?, int?) parseTrackNumber(String? raw) {
    if (raw == null || raw.trim().isEmpty) return (null, null);
    final parts = raw.trim().split(_trackNumberSplitRegex);
    if (parts.isEmpty) return (null, null);

    final trackNumStr = parts[0].replaceAll(_numericCleanRegex, '');
    final trackNumber = int.tryParse(trackNumStr);

    int? trackTotal;
    if (parts.length > 1) {
      final trackTotalStr = parts[1].replaceAll(_numericCleanRegex, '');
      trackTotal = int.tryParse(trackTotalStr);
    }

    return (trackNumber, trackTotal);
  }

  /// Parses disc number and total discs from strings like `"1"`, `"1/2"`, defaulting to disc 1.
  (int, int?) parseDiscNumber(String? raw) {
    if (raw == null || raw.trim().isEmpty) return (1, null);
    final parts = raw.trim().split(_trackNumberSplitRegex);
    if (parts.isEmpty) return (1, null);

    final discNumStr = parts[0].replaceAll(_numericCleanRegex, '');
    final discNumber = int.tryParse(discNumStr) ?? 1;

    int? discTotal;
    if (parts.length > 1) {
      final discTotalStr = parts[1].replaceAll(_numericCleanRegex, '');
      discTotal = int.tryParse(discTotalStr);
    }

    return (discNumber, discTotal);
  }

  /// Extracts a 4-digit year from arbitrary date/year strings.
  int? parseYear(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final match = _yearRegex.firstMatch(raw.trim());
    return match != null ? int.tryParse(match.group(1)!) : null;
  }
}
