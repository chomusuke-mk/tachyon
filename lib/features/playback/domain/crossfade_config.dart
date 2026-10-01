import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/core/constants/app_defaults.dart';

@immutable
class CrossfadeConfig {
  static const Duration minDuration = Duration(
    seconds: AppDefaults.crossfadeMinDuration,
  );
  static const Duration maxDuration = Duration(
    seconds: AppDefaults.crossfadeMaxDuration,
  );
  static const Duration defaultDuration = Duration(
    seconds: AppDefaults.crossfadeDefaultDuration,
  );
  static const Duration defaultManualDuration = Duration(
    seconds: 3,
  );

  final bool enabled;
  final Duration duration;
  final Duration manualDuration;
  final CrossfadeCurve curve;

  const CrossfadeConfig({
    this.enabled = true,
    this.duration = defaultDuration,
    this.manualDuration = defaultManualDuration,
    this.curve = CrossfadeCurve.equalPower,
  });

  /// Clamps duration to ensure it is always within [minDuration, maxDuration]
  Duration get clampedDuration {
    if (duration < minDuration) return minDuration;
    if (duration > maxDuration) return maxDuration;
    return duration;
  }

  /// Handles edge cases where track is shorter than crossfade duration
  Duration effectiveDuration(Duration trackDuration) {
    if (!enabled || duration == Duration.zero) return Duration.zero;
    if (trackDuration <= Duration.zero) return Duration.zero;
    final halfTrack = Duration(milliseconds: trackDuration.inMilliseconds ~/ 2);
    if (clampedDuration > halfTrack) {
      return halfTrack;
    }
    return clampedDuration;
  }

  /// Calculates the volume of the outgoing track (Fade Out)
  /// [progress] is normalized in range [0.0, 1.0]
  double calculateFadeOutVolume(double progress, double masterVolume) {
    final p = progress.clamp(0.0, 1.0);
    switch (curve) {
      case CrossfadeCurve.equalPower:
        return masterVolume * math.cos(math.pi * 0.5 * p);
      case CrossfadeCurve.linear:
        return masterVolume * (1.0 - p);
    }
  }

  /// Calculates the volume of the incoming track (Fade In)
  /// [progress] is normalized in range [0.0, 1.0]
  double calculateFadeInVolume(double progress, double masterVolume) {
    final p = progress.clamp(0.0, 1.0);
    switch (curve) {
      case CrossfadeCurve.equalPower:
        return masterVolume * math.sin(math.pi * 0.5 * p);
      case CrossfadeCurve.linear:
        return masterVolume * p;
    }
  }

  CrossfadeConfig copyWith({
    bool? enabled,
    Duration? duration,
    Duration? manualDuration,
    CrossfadeCurve? curve,
  }) {
    return CrossfadeConfig(
      enabled: enabled ?? this.enabled,
      duration: duration ?? this.duration,
      manualDuration: manualDuration ?? this.manualDuration,
      curve: curve ?? this.curve,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'durationMs': duration.inMilliseconds,
      'manualDurationMs': manualDuration.inMilliseconds,
      'curve': curve.name,
    };
  }

  factory CrossfadeConfig.fromJson(Map<String, dynamic> json) {
    return CrossfadeConfig(
      enabled: json['enabled'] as bool? ?? true,
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
      curve: CrossfadeCurve.fromString(json['curve'] as String?),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CrossfadeConfig &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          duration == other.duration &&
          manualDuration == other.manualDuration &&
          curve == other.curve;

  @override
  int get hashCode => Object.hash(enabled, duration, manualDuration, curve);
}
