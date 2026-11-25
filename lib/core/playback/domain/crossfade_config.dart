import 'package:flutter/foundation.dart';
import 'package:miniaudio_player/miniaudio_player.dart' as ma;
import 'package:tachyon/core/constants/app_defaults.dart';

export 'package:miniaudio_player/miniaudio_player.dart' show CrossfadeCurve;

/// Extension providing serialization and parsing for [ma.CrossfadeCurve].
extension CrossfadeCurveExtension on ma.CrossfadeCurve {
  /// The serialized JSON string representation of this crossfade curve.
  String get jsonValue {
    switch (this) {
      case ma.CrossfadeCurve.linear:
        return 'linear';
      case ma.CrossfadeCurve.equalPower:
        return 'equal_power';
    }
  }

  /// Parses [val] into a [ma.CrossfadeCurve], defaulting to
  /// [ma.CrossfadeCurve.equalPower].
  static ma.CrossfadeCurve fromString(String? val) {
    if (val == 'linear') return ma.CrossfadeCurve.linear;
    return ma.CrossfadeCurve.equalPower;
  }
}

/// Configuration for automatic and manual track crossfade transitions.
@immutable
class CrossfadeConfig {
  /// Minimum supported automatic crossfade duration.
  static const Duration minDuration = Duration(
    seconds: AppDefaults.crossfadeMinDuration,
  );

  /// Maximum supported automatic crossfade duration.
  static const Duration maxDuration = Duration(
    seconds: AppDefaults.crossfadeMaxDuration,
  );

  /// Default automatic crossfade duration between consecutive tracks.
  static const Duration defaultDuration = Duration(
    seconds: AppDefaults.crossfadeDefaultDuration,
  );

  /// Default crossfade duration used for manual skips.
  static const Duration defaultManualDuration = Duration(
    seconds: AppDefaults.crossfadeManualDefaultDuration,
  );

  /// Automatic crossfade duration between naturally advancing tracks.
  final Duration duration;

  /// Crossfade duration applied when manually skipping tracks.
  final Duration manualDuration;

  /// Gain curve applied during crossfade transitions.
  final ma.CrossfadeCurve curve;

  /// Creates a [CrossfadeConfig] with optional [duration], [manualDuration],
  /// and [curve].
  const CrossfadeConfig({
    this.duration = defaultDuration,
    this.manualDuration = defaultManualDuration,
    this.curve = ma.CrossfadeCurve.equalPower,
  });

  /// Clamps [duration] within `[minDuration, maxDuration]`.
  Duration get clampedDuration {
    if (duration < minDuration) return minDuration;
    if (duration > maxDuration) return maxDuration;
    return duration;
  }

  /// Creates a copy of this configuration with the specified overrides.
  CrossfadeConfig copyWith({
    Duration? duration,
    Duration? manualDuration,
    ma.CrossfadeCurve? curve,
  }) {
    return CrossfadeConfig(
      duration: duration ?? this.duration,
      manualDuration: manualDuration ?? this.manualDuration,
      curve: curve ?? this.curve,
    );
  }

  /// Serializes this crossfade configuration to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'durationMs': duration.inMilliseconds,
      'manualDurationMs': manualDuration.inMilliseconds,
      'curve': curve.name,
    };
  }

  /// Deserializes a [CrossfadeConfig] from a [json] map.
  factory CrossfadeConfig.fromJson(Map<String, dynamic> json) {
    return CrossfadeConfig(
      duration: Duration(
        milliseconds:
            ((json['durationMs'] ?? json['duration']) as num?)?.toInt() ??
            defaultDuration.inMilliseconds,
      ),
      manualDuration: Duration(
        milliseconds:
            (json['manualDurationMs'] as num?)?.toInt() ??
            defaultManualDuration.inMilliseconds,
      ),
      curve: CrossfadeCurveExtension.fromString(json['curve'] as String?),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CrossfadeConfig &&
          runtimeType == other.runtimeType &&
          duration == other.duration &&
          manualDuration == other.manualDuration &&
          curve == other.curve;

  @override
  int get hashCode => Object.hash(duration, manualDuration, curve);
}
