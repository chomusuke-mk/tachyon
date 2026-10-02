class AppDefaults {
  static const double volumeMax = 100.0;
  static const double volumeMin = 0.0;
  static const double volumeDefault = 100.0;

  static const double volumeBoostMax = 200.0;
  static const double volumeBoostMin = 100.0;
  static const double volumeBoostDefault = 100.0;

  static const int crossfadeMinDuration = 0;
  static const int crossfadeMaxDuration = 30;
  static const int crossfadeDefaultDuration = 5;

  static const double playbackRateMin = 0.5;
  static const double playbackRateMax = 1.5;
  static const double playbackRateDefault = 1.0;

  static const double playbackPitchMin = 0.5;
  static const double playbackPitchMax = 1.5;
  static const double playbackPitchDefault = 1.0;

  static const bool audioPlayerAsyncEnabled = false;

  static const Set<String> supportedAudioExtensions = {
    'mp3', 'flac', 'ogg', 'opus', 'm4a', 'aac', 'wav', 'aiff', 'wma'
  };
}
