import 'package:miniaudio_player/miniaudio_player.dart' as ma;

export 'package:miniaudio_player/miniaudio_player.dart' show LoopMode;

/// Extension providing string serialization and parsing for [ma.LoopMode].
extension LoopModeExtension on ma.LoopMode {
  /// The string name representation of this loop mode.
  String get repr => name;

  /// Returns the next [ma.LoopMode] in the cycle: off, all, and one.
  ma.LoopMode next() => switch (this) {
    ma.LoopMode.off => ma.LoopMode.all,
    ma.LoopMode.all => ma.LoopMode.one,
    ma.LoopMode.one => ma.LoopMode.off,
  };

  /// Parses [val] into a [ma.LoopMode], defaulting to [ma.LoopMode.off].
  static ma.LoopMode fromString(String? val) {
    return ma.LoopMode.values.firstWhere(
      (e) => e.name == val,
      orElse: () => ma.LoopMode.off,
    );
  }
}
