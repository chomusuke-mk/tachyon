import 'dart:collection';
import 'dart:math' as math;

class CrossfadeMath {
  /// Calculates equal-power volumes for instance A (fade-out) and instance B (fade-in)
  /// according to constant acoustic energy formula:
  /// V_A = V_master * cos(pi/2 * p)
  /// V_B = V_master * sin(pi/2 * p)
  /// where p in [0.0, 1.0].
  static ({double volumeA, double volumeB}) calculateEqualPower({
    required double progress,
    required double masterVolume,
  }) {
    final p = progress.clamp(0.0, 1.0);
    final angle = (math.pi / 2.0) * p;
    final volA = masterVolume * math.cos(angle);
    final volB = masterVolume * math.sin(angle);
    return (volumeA: volA, volumeB: volB);
  }

  /// Calculates linear volumes for instance A (fade-out) and instance B (fade-in)
  /// V_A = V_master * (1 - p)
  /// V_B = V_master * p
  static ({double volumeA, double volumeB}) calculateLinear({
    required double progress,
    required double masterVolume,
  }) {
    final p = progress.clamp(0.0, 1.0);
    final volA = masterVolume * (1.0 - p);
    final volB = masterVolume * p;
    return (volumeA: volA, volumeB: volB);
  }

  /// Verifies acoustic energy conservation: V_A^2 + V_B^2 == V_master^2
  static bool verifyEnergyConservation({
    required double volumeA,
    required double volumeB,
    required double masterVolume,
    double epsilon = 1e-6,
  }) {
    final totalEnergy = (volumeA * volumeA) + (volumeB * volumeB);
    final targetEnergy = masterVolume * masterVolume;
    return (totalEnergy - targetEnergy).abs() <= epsilon;
  }

  /// Calculates effective crossfade duration, clamping to trackDuration / 2
  /// when track is shorter than the configured duration.
  static Duration calculateEffectiveCrossfadeDuration({
    required Duration trackDuration,
    required Duration configuredCrossfadeDuration,
  }) {
    if (trackDuration <= Duration.zero) return Duration.zero;
    if (trackDuration <= configuredCrossfadeDuration) {
      return Duration(milliseconds: trackDuration.inMilliseconds ~/ 2);
    }
    return configuredCrossfadeDuration;
  }
}

class LyricsMath {
  /// Resolves active lyric index from timestamps using SplayTreeMap in O(log n) time
  static int findActiveLyricIndex({
    required int positionMs,
    required SplayTreeMap<int, int> timestampToIndexMap,
  }) {
    if (timestampToIndexMap.isEmpty) return -1;
    final activeTimestamp = timestampToIndexMap.lastKeyBefore(positionMs + 1);
    if (activeTimestamp == null) {
      return 0; // Return first line if position is before first timestamp
    }
    return timestampToIndexMap[activeTimestamp] ?? 0;
  }
}
