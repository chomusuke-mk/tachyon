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
