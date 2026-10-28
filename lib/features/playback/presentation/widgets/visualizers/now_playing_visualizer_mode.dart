/// Visual display modes for the Now Playing artwork and audio reactive effects.
enum NowPlayingVisualizerMode {
  /// Pure cover image without audio reactive wave or bass pulsation.
  off,

  /// Cover image with continuous fluid audio wave docked underneath and bass bounce.
  wave,

  /// Studio 10-band spectrum analyzer with dB reference markings, peak caps,
  /// and frequency labels, replacing the cover image.
  bars,

  /// Reactive circular audio visualizer with pulsing neon ring,
  /// audio-reactive scale, and 3D undulating particle wave mesh ribbons
  /// (inspired by the iconic NCS / NoCopyrightSounds visualizer style).
  circle;

  String get key => name;

  static NowPlayingVisualizerMode fromString(String? value) {
    if (value == null || value.isEmpty) return NowPlayingVisualizerMode.wave;
    for (final mode in NowPlayingVisualizerMode.values) {
      if (mode.name == value) return mode;
    }
    return NowPlayingVisualizerMode.wave;
  }

  NowPlayingVisualizerMode get next {
    final nextIndex = (index + 1) % NowPlayingVisualizerMode.values.length;
    return NowPlayingVisualizerMode.values[nextIndex];
  }
}
