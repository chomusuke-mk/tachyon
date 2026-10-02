import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:tachyon/features/playback/domain/lyric_line.dart';

/// Immutable container holding the parsed LRC document, metadata, and fast lookup trees.
@immutable
class ParsedLrc {
  /// Header metadata tags: e.g. {'ti': 'Title', 'ar': 'Artist', 'al': 'Album', 'by': 'Author'}
  final Map<String, String> metadata;

  /// Header offset specified in the file in milliseconds (from [offset:+/-ms])
  final int offsetMs;

  /// Ordered list of all lyric lines (sorted chronologically if synced)
  final List<LyricLine> lines;

  /// Self-balancing binary search tree indexed by line Duration for O(log n) lookup
  final SplayTreeMap<Duration, LyricLine> timeline;

  /// Self-balancing binary search tree mapping timestampMs to line index in [lines]
  final SplayTreeMap<int, int> indexMap;

  /// Whether the file contains timestamped lines
  final bool isSynced;

  const ParsedLrc({
    required this.metadata,
    required this.offsetMs,
    required this.lines,
    required this.timeline,
    required this.indexMap,
    required this.isSynced,
  });

  /// Factory for an empty lyric document
  factory ParsedLrc.empty() => ParsedLrc(
    metadata: const {},
    offsetMs: 0,
    lines: const [],
    timeline: SplayTreeMap<Duration, LyricLine>(),
    indexMap: SplayTreeMap<int, int>(),
    isSynced: false,
  );

  // Metadata accessors
  String? get title => metadata['ti'];
  String? get artist => metadata['ar'];
  String? get album => metadata['al'];
  String? get author => metadata['by'];
  String? get editor => metadata['re'];
  String? get version => metadata['ve'];
  String? get length => metadata['length'];

  bool get isEmpty => lines.isEmpty;
  bool get isNotEmpty => lines.isNotEmpty;

  /// Resolves the active line index for the given playback position in O(log n) time.
  ///
  /// Returns -1 if lines is empty.
  /// Returns 0 if lyrics are unsynced or if playback has not reached the first line.
  /// Returns lines.length - 1 if playback is past the last timestamp.
  int activeIndexAt(Duration position) {
    if (lines.isEmpty) return -1;
    if (!isSynced || indexMap.isEmpty) return 0;

    final posMs = position.inMilliseconds;
    final activeTimestamp = indexMap.lastKeyBefore(posMs + 1);
    if (activeTimestamp == null) return 0;
    return indexMap[activeTimestamp] ?? 0;
  }

  /// Resolves the active [LyricLine] for the given playback position in O(log n) time.
  LyricLine? lineAt(Duration position) {
    if (lines.isEmpty) return null;
    if (!isSynced || timeline.isEmpty) return lines.first;

    final key = timeline.lastKeyBefore(
      position + const Duration(microseconds: 1),
    );
    if (key == null) return lines.first;
    return timeline[key];
  }
}

/// High-performance parser engine for standard and extended LRC files.
abstract final class LrcParser {
  // Matches standard and extended LRC timestamps:
  // [mm:ss.xx] (centis), [mm:ss.xxx] (millis), [m:ss.xx], [120:00.00]
  static final RegExp _timestampRegex = RegExp(
    r'\[(\d+):(\d{2})(?:\.(\d{1,3}))?\]',
  );

  // Matches [offset:+/-ms]
  static final RegExp _offsetRegex = RegExp(
    r'\[offset:\s*([+-]?\d+)\s*\]',
    caseSensitive: false,
  );

  // Matches metadata tags e.g. [ti:Song Title] or [ar:Artist Name]
  static final RegExp _metadataRegex = RegExp(r'^\[([a-zA-Z]+)\s*:\s*(.*)\]$');

  /// Parses raw LRC or plain text into a structured [ParsedLrc] document.
  ///
  /// [userOffsetMs] allows runtime user offset calibration (+ moves later, - moves earlier).
  static ParsedLrc parse(String rawContent, {int userOffsetMs = 0}) {
    if (rawContent.trim().isEmpty) {
      return ParsedLrc.empty();
    }

    // Strip UTF-8 BOM if present
    var sanitized = rawContent;
    if (sanitized.startsWith('\uFEFF')) {
      sanitized = sanitized.substring(1);
    }

    final lines = sanitized.split(RegExp(r'\r?\n'));
    int headerOffset = 0;
    final Map<String, String> metadata = {};
    final List<LyricLine> parsedLines = [];
    bool hasAnyTimestamp = false;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final offsetMatch = _offsetRegex.firstMatch(line);
      if (offsetMatch != null) {
        headerOffset = int.tryParse(offsetMatch.group(1) ?? '0') ?? 0;
        metadata['offset'] = headerOffset.toString();
        continue;
      }

      final metaMatch = _metadataRegex.firstMatch(line);
      if (metaMatch != null) {
        // Exclude tags that match timestamps (e.g. invalid format)
        if (!_timestampRegex.hasMatch(line)) {
          final key = metaMatch.group(1)!.toLowerCase();
          final value = metaMatch.group(2)!.trim();
          metadata[key] = value;
          continue;
        }
      }

      // Check for timestamp matches
      final timestampMatches = _timestampRegex.allMatches(line).toList();
      if (timestampMatches.isEmpty) {
        // Plain text lyric line (without brackets)
        if (!line.startsWith('[') || !line.endsWith(']')) {
          parsedLines.add(
            LyricLine(timestampMs: 0, text: line, isSynced: false),
          );
        }
        continue;
      }

      hasAnyTimestamp = true;

      // Extract text after the last timestamp tag on this line
      final lastMatch = timestampMatches.last;
      final text = line.substring(lastMatch.end).trim();

      // Multi-timestamp support: emit one LyricLine per timestamp tag
      for (final match in timestampMatches) {
        final mm = int.parse(match.group(1)!);
        final ss = int.parse(match.group(2)!);
        final fracStr = match.group(3);

        int fracMs = 0;
        if (fracStr != null && fracStr.isNotEmpty) {
          if (fracStr.length == 1) {
            fracMs = int.parse(fracStr) * 100;
          } else if (fracStr.length == 2) {
            fracMs = int.parse(fracStr) * 10;
          } else {
            fracMs = int.parse(fracStr.substring(0, 3));
          }
        }

        final totalMs =
            (mm * 60 * 1000) +
            (ss * 1000) +
            fracMs +
            headerOffset +
            userOffsetMs;
        final clampedMs = totalMs < 0 ? 0 : totalMs;

        parsedLines.add(
          LyricLine(timestampMs: clampedMs, text: text, isSynced: true),
        );
      }
    }

    if (hasAnyTimestamp) {
      // Sort chronologically
      parsedLines.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    }

    // Build timeline and index trees
    final timeline = SplayTreeMap<Duration, LyricLine>();
    final indexMap = SplayTreeMap<int, int>();

    for (int i = 0; i < parsedLines.length; i++) {
      final line = parsedLines[i];
      if (line.isSynced) {
        timeline[line.timestamp] = line;
        indexMap[line.timestampMs] = i;
      }
    }

    return ParsedLrc(
      metadata: Map.unmodifiable(metadata),
      offsetMs: headerOffset,
      lines: List.unmodifiable(parsedLines),
      timeline: timeline,
      indexMap: indexMap,
      isSynced: hasAnyTimestamp,
    );
  }

  /// Determines whether the string contains valid LRC timestamp tags.
  static bool isValidLrc(String? rawContent) {
    if (rawContent == null || rawContent.trim().isEmpty) return false;
    return _timestampRegex.hasMatch(rawContent);
  }
}
