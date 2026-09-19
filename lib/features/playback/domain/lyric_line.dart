import 'dart:collection';

import 'package:flutter/foundation.dart';

@immutable
class LyricLine {
  final int timestampMs;
  final String text;
  final bool isSynced;
  final String? translation;

  const LyricLine({
    required this.timestampMs,
    required this.text,
    this.isSynced = true,
    this.translation,
  });

  Duration get timestamp => Duration(milliseconds: timestampMs);

  String get formattedTimestamp {
    final totalSeconds = timestampMs ~/ 1000;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    final centis = ((timestampMs % 1000) ~/ 10).toString().padLeft(2, '0');
    return '[$minutes:$seconds.$centis]';
  }

  LyricLine copyWith({
    int? timestampMs,
    String? text,
    bool? isSynced,
    String? translation,
  }) {
    return LyricLine(
      timestampMs: timestampMs ?? this.timestampMs,
      text: text ?? this.text,
      isSynced: isSynced ?? this.isSynced,
      translation: translation ?? this.translation,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'timestampMs': timestampMs,
      'text': text,
      'isSynced': isSynced,
      'translation': translation,
    };
  }

  factory LyricLine.fromJson(Map<String, dynamic> json) {
    return LyricLine(
      timestampMs:
          ((json['timestampMs'] ?? json['timestamp_ms']) as num?)?.toInt() ?? 0,
      text: json['text'] as String? ?? '',
      isSynced: (json['isSynced'] ?? json['is_synced']) as bool? ?? false,
      translation: json['translation'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LyricLine &&
          runtimeType == other.runtimeType &&
          timestampMs == other.timestampMs &&
          text == other.text &&
          isSynced == other.isSynced &&
          translation == other.translation;

  @override
  int get hashCode => Object.hash(timestampMs, text, isSynced, translation);

  /// Standard LRC parser with support for [offset:+/-ms], multi-timestamps, and plain text
  static List<LyricLine> parseLrc(String rawContent, {int userOffsetMs = 0}) {
    if (rawContent.trim().isEmpty) return const [];

    final lines = rawContent.split(RegExp(r'\r?\n'));
    int headerOffset = 0;
    final List<LyricLine> parsed = [];

    // Header regex e.g. [offset:500] or [offset:-200]
    final offsetRegex = RegExp(
      r'\[offset:\s*([+-]?\d+)\s*\]',
      caseSensitive: false,
    );
    // Timestamp tag regex e.g. [01:23.45] or [1:23.45] or [105:23.456]
    final timestampRegex = RegExp(r'\[(\d{1,}):(\d{2})\.(\d{2,3})\]');

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final offsetMatch = offsetRegex.firstMatch(line);
      if (offsetMatch != null) {
        headerOffset = int.tryParse(offsetMatch.group(1) ?? '0') ?? 0;
        continue;
      }

      final matches = timestampRegex.allMatches(line).toList();
      if (matches.isEmpty) {
        // Line without timestamp: metadata tag [ar:...] or plain unsynced lyric line
        if (!line.startsWith('[') || !line.endsWith(']')) {
          parsed.add(LyricLine(timestampMs: 0, text: line, isSynced: false));
        }
        continue;
      }

      // Extract text after the last timestamp match
      final lastMatch = matches.last;
      final text = line.substring(lastMatch.end).trim();

      for (final match in matches) {
        final mm = int.parse(match.group(1)!);
        final ss = int.parse(match.group(2)!);
        final fracStr = match.group(3)!;
        final fracMs = fracStr.length == 2
            ? int.parse(fracStr) * 10
            : int.parse(fracStr);

        final totalMs =
            (mm * 60 * 1000) +
            (ss * 1000) +
            fracMs +
            headerOffset +
            userOffsetMs;
        parsed.add(
          LyricLine(
            timestampMs: totalMs < 0 ? 0 : totalMs,
            text: text,
            isSynced: true,
          ),
        );
      }
    }

    // Sort synced lyrics chronologically
    parsed.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    return parsed;
  }

  /// Builds an O(log n) SplayTreeMap index from timestampMs to line index
  static SplayTreeMap<int, int> buildIndex(List<LyricLine> lyrics) {
    final map = SplayTreeMap<int, int>();
    for (int i = 0; i < lyrics.length; i++) {
      if (lyrics[i].isSynced) {
        map[lyrics[i].timestampMs] = i;
      }
    }
    return map;
  }

  /// Finds the currently active lyric line in O(log n) time
  static int findActiveIndex(SplayTreeMap<int, int> indexMap, int positionMs) {
    if (indexMap.isEmpty) return 0;
    final activeTimestamp = indexMap.lastKeyBefore(positionMs + 1);
    if (activeTimestamp == null) return 0;
    return indexMap[activeTimestamp] ?? 0;
  }
}
