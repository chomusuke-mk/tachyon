import 'package:tachyon/core/store/domain/track.dart';

/// Extension methods for consistent and reusable formatting of durations.
extension DurationFormatExtension on Duration {
  /// Formats duration as `mm:ss` or `h:mm:ss` (or `m:ss` if [padMinutes] is false).
  ///
  /// Optionally attaches a [prefix] (e.g. `"-"` for remaining time).
  String toFormattedString({String? prefix, bool padMinutes = false}) {
    final totalSeconds = inSeconds.abs();
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    final secondsStr = seconds.toString().padLeft(2, '0');
    final pfx = prefix ?? '';

    if (hours > 0) {
      final minutesStr = minutes.toString().padLeft(2, '0');
      return '$pfx$hours:$minutesStr:$secondsStr';
    }

    final minutesStr = padMinutes
        ? minutes.toString().padLeft(2, '0')
        : minutes.toString();
    return '$pfx$minutesStr:$secondsStr';
  }

  /// Formats duration in human-readable summary form, e.g. `2h 15m` or `42m`.
  String toHumanReadable() {
    final hours = inHours;
    final minutes = inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }
}

/// Extension methods for duration integer milliseconds.
extension DurationIntFormatExtension on int {
  /// Formats integer milliseconds as `mm:ss` or `h:mm:ss`.
  String toFormattedDuration() {
    final duration = Duration(milliseconds: this);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}

/// Extension methods for calculating total duration of a track collection.
extension TrackCollectionDurationExtension on Iterable<Track> {
  /// Aggregates track duration and formats as human-readable `Xh Ym` or `Ym`.
  String get formattedTotalDuration {
    final totalMs = fold<int>(0, (sum, t) => sum + t.durationMs);
    return Duration(milliseconds: totalMs).toHumanReadable();
  }
}
