/// Default configuration values and bounds for playback, artwork, and sample assets.
class AppDefaults {
  /// Maximum normalized master playback volume.
  static const double volumeMax = 1.0;

  /// Minimum normalized master playback volume.
  static const double volumeMin = 0.0;

  /// Default normalized master playback volume.
  static const double volumeDefault = 1.0;

  /// Maximum volume boost multiplier.
  static const double volumeBoostMax = 2.0;

  /// Minimum volume boost multiplier (no amplification).
  static const double volumeBoostMin = 1.0;

  /// Default volume boost multiplier.
  static const double volumeBoostDefault = 1.0;

  /// Minimum automatic crossfade duration in seconds.
  static const int crossfadeMinDuration = 0;

  /// Maximum automatic crossfade duration in seconds.
  static const int crossfadeMaxDuration = 20;

  /// Default automatic crossfade duration in seconds.
  static const int crossfadeDefaultDuration = 5;

  /// Minimum manual crossfade duration in seconds.
  static const int crossfadeManualMinDuration = 0;

  /// Maximum manual crossfade duration in seconds.
  static const int crossfadeManualMaxDuration = 5;

  /// Default manual crossfade duration in seconds.
  static const int crossfadeManualDefaultDuration = 1;

  /// Minimum playback speed multiplier.
  static const double playbackRateMin = 0.5;

  /// Maximum playback speed multiplier.
  static const double playbackRateMax = 1.5;

  /// Default playback speed multiplier.
  static const double playbackRateDefault = 1.0;

  /// Minimum playback pitch multiplier.
  static const double playbackPitchMin = 0.5;

  /// Maximum playback pitch multiplier.
  static const double playbackPitchMax = 1.5;

  /// Default playback pitch multiplier.
  static const double playbackPitchDefault = 1.0;

  /// Supported lowercase audio file extensions (without leading dots) for discovery.
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
    'webm',
    'mkv',
    'mka',
    'caf',
    'wv',
    'ape',
    'dsf',
    'm3u8',
  };

  /// Base URL for the remote sample audio asset repository used on Web.
  static const String webSampleAssetsBaseUrl =
      'https://raw.githubusercontent.com/chomusuke-mk/miniaudio_player_assets/main';

  /// Default Web audio catalog from `miniaudio_player/example/assets/music`
  /// (`https://github.com/chomusuke-mk/miniaudio_player_assets`).
  static const List<String> defaultWebSampleAudioUrls = <String>[
    '$webSampleAssetsBaseUrl/01_Apex_Momentum.mp3',
    '$webSampleAssetsBaseUrl/02_Bailando_con_tu_recuerdo.opus',
    '$webSampleAssetsBaseUrl/03_Before_The_Dawn_cbr_noxing.mp3',
    '$webSampleAssetsBaseUrl/04_Belaya_Tishina.flac',
    '$webSampleAssetsBaseUrl/05_Burning_in_the_Electric_Light.ogg',
    '$webSampleAssetsBaseUrl/06_Calculated_Motion_aac.m4a',
    '$webSampleAssetsBaseUrl/07_Fevered_Strings_alac.m4a',
    '$webSampleAssetsBaseUrl/08_Firelight_Promise_24bit_mono.wav',
    '$webSampleAssetsBaseUrl/09_Flesh_and_Chrome.wv',
    '$webSampleAssetsBaseUrl/10_La_cicatriz_del_and%C3%A9n.aac',
    '$webSampleAssetsBaseUrl/11_Mar_de_cristal.mka',
    '$webSampleAssetsBaseUrl/12_Mi_m%C3%A1s_bonita_coincidencia_24bit_stereo.wav',
    '$webSampleAssetsBaseUrl/13_Overture_for_the_Floor.webm',
    '$webSampleAssetsBaseUrl/14_Painting_the_Sky.mkv',
    '$webSampleAssetsBaseUrl/15_Resting_At_Your_Feet.mp2',
    '$webSampleAssetsBaseUrl/16_Ribbons_on_Anchors.oga',
    '$webSampleAssetsBaseUrl/17_Running_To_Meet_The_Sun.wav',
    '$webSampleAssetsBaseUrl/18_Running_With_Daylight.aif',
    '$webSampleAssetsBaseUrl/19_Spin_Me_In_The_Dark.rf64',
    '$webSampleAssetsBaseUrl/20_Swallowing_This_Glitter_Pill.w64',
    '$webSampleAssetsBaseUrl/21_The_Great_Equalizer.bwf',
    '$webSampleAssetsBaseUrl/22_The_Midnight_Pursuit.rifx',
    '$webSampleAssetsBaseUrl/23_Tracing_Lines.aifc',
    '$webSampleAssetsBaseUrl/24_Tracks_Into_The_Dawn.aiff',
    '$webSampleAssetsBaseUrl/25_Velocity_of_One.ape',
    '$webSampleAssetsBaseUrl/27_%C2%A1Yo_me_opongo_.caf',
    '$webSampleAssetsBaseUrl/hls/28_%D0%A0%D0%B0%D0%B7%D0%B2%D0%BE%D0%B4%D1%8F%D1%82_%D0%BC%D0%BE%D1%81%D1%82%D1%8B.m3u8',
    '$webSampleAssetsBaseUrl/29_%E9%A7%86%E3%81%91%E6%8A%9C%E3%81%91%E3%81%A6%E3%80%81%E3%81%93%E3%81%AE%E7%A9%BA%E3%82%92.dsf',
  ];

  /// Target pixel dimension for low-resolution artwork thumbnails.
  static const int lowQualityResolution = 150;

  /// Target pixel dimension for medium-resolution artwork thumbnails.
  static const int mediumQualityResolution = 500;

  /// Target pixel dimension for high-resolution artwork thumbnails.
  static const int highQualityResolution = 1200;
}
