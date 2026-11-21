import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/core/playback/tachyon_audio_handler.dart';

class LinuxMprisBridge {
  final TachyonAudioHandler handler;
  final PlaybackController playbackController;
  final Duration metadataDebounceDuration;
  final Duration stateCoalesceDuration;

  LinuxMprisBridge({
    required this.handler,
    required this.playbackController,
    this.metadataDebounceDuration = const Duration(milliseconds: 60),
    this.stateCoalesceDuration = const Duration(milliseconds: 12),
  });

  int get emittedSignalCount => 0;
  String? get registeredBusName => null;
  String get playbackStatus => 'Stopped';
  String get loopStatus => 'None';
  double get rate => 1.0;
  bool get shuffle => false;
  double get volume => 1.0;

  Future<void> initialize() async {}
  Future<void> dispose() async {}
}
