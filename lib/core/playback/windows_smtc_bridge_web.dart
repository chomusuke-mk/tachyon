import 'package:tachyon/core/playback/tachyon_audio_handler.dart';

class WindowsSmtcBridge {
  final TachyonAudioHandler handler;

  WindowsSmtcBridge(this.handler);

  bool get isInitialized => false;
  int? get coverServerPort => null;

  Future<bool> initialize({Object? externalLibrary}) async => false;
  Future<void> dispose() async {}
}
