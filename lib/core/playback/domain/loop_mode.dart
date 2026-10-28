import 'package:miniaudio_player/miniaudio_player.dart' as ma;

export 'package:miniaudio_player/miniaudio_player.dart' show LoopMode;

/// Backwards compatibility alias for [ma.LoopMode].
typedef Loop = ma.LoopMode;

/// Extension providing string serialization and parsing for [ma.LoopMode].
extension LoopModeExtension on ma.LoopMode {
  String get repr => name;

  static ma.LoopMode fromString(String? val) {
    return ma.LoopMode.values.firstWhere(
      (e) => e.name == val,
      orElse: () => ma.LoopMode.off,
    );
  }
}
