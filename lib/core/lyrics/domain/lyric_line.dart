import 'package:flutter/foundation.dart';

/// Single lyric line with an optional synchronization timestamp and translation.
@immutable
class LyricLine {
  /// Playback position in milliseconds when this line becomes active.
  final int timestampMs;

  /// Lyric text content for this line.
  final String text;

  /// Whether this line has an explicit synchronization timestamp.
  final bool isSynced;

  /// Optional translated text corresponding to [text].
  final String? translation;

  /// Creates a [LyricLine] at [timestampMs] with [text], sync status, and optional [translation].
  const LyricLine({
    required this.timestampMs,
    required this.text,
    this.isSynced = true,
    this.translation,
  });

  /// Playback timestamp as a [Duration].
  Duration get timestamp => Duration(milliseconds: timestampMs);

  /// LRC-formatted timestamp string in `[mm:ss.cc]` notation.
  String get formattedTimestamp {
    final totalSeconds = timestampMs ~/ 1000;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    final centis = ((timestampMs % 1000) ~/ 10).toString().padLeft(2, '0');
    return '[$minutes:$seconds.$centis]';
  }

  /// Returns a copy of this [LyricLine] with the specified fields replaced.
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
}
