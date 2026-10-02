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

  // METADATA EXTRACTOR SUPPORT
  /*
  '.mp3',
  '.flac',
  '.mp4',
  '.m4a',
  '.ape',
  '.ogg',
  '.opus',
  '.wav',
  '.aif',
  '.aiff',
  '.aifc',
  '.mov',
  '.webm',
  '.mkv',
   */
  // PLAYER SUPPORT
  /*
  'mp3',
  'wav',
  'flac',
  'ogg',
  'opus',
  'aif',
  'aiff',
  'aifc',
  'w64',
  'rf64',
  'bwf',
  'rifx',
  'mp2',
  'mp1',
  'oga',
  'aac',
  'm4a',
  */
  static const Set<String> supportedAudioExtensions = {
    'mp3',
    'wav',
    'flac',
    'ogg',
    'opus',
    'aif',
    'aiff',
    'aifc',
    'aiffc',
    'w64',
    'rf64',
    'bwf',
    'rifx',
    'mp2',
    'mp1',
    'oga',
    'aac',
    'm4a',
  };
}
