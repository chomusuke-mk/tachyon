enum AudioFormat {
  mp3,
  flac,
  wav,
  aac,
  ogg,
  m4a;

  static AudioFormat fromExtension(String ext) {
    switch (ext.toLowerCase().replaceAll('.', '')) {
      case 'mp3':
        return AudioFormat.mp3;
      case 'flac':
        return AudioFormat.flac;
      case 'wav':
        return AudioFormat.wav;
      case 'aac':
        return AudioFormat.aac;
      case 'ogg':
        return AudioFormat.ogg;
      case 'm4a':
        return AudioFormat.m4a;
      default:
        return AudioFormat.mp3;
    }
  }
}

enum LoopMode {
  off,
  one,
  all,
}

enum CrossfadeCurve {
  linear,
  equalPower,
}

class TrackInfo {
  final int id;
  final String uri;
  final String title;
  final String artist;
  final List<String> artists;
  final String album;
  final String albumArtist;
  final int trackNumber;
  final int discNumber;
  final int year;
  final Duration duration;
  final int bitrate;
  final int sampleRate;
  final String codec;
  final int fileSize;
  final bool hasCover;
  final String? coverPath;
  final String? rawLyrics;
  final AudioFormat format;

  const TrackInfo({
    required this.id,
    required this.uri,
    required this.title,
    required this.artist,
    this.artists = const [],
    required this.album,
    this.albumArtist = '',
    this.trackNumber = 1,
    this.discNumber = 1,
    this.year = 0,
    required this.duration,
    this.bitrate = 320000,
    this.sampleRate = 44100,
    this.codec = 'mp3',
    this.fileSize = 0,
    this.hasCover = false,
    this.coverPath,
    this.rawLyrics,
    this.format = AudioFormat.mp3,
  });

  TrackInfo copyWith({
    int? id,
    String? uri,
    String? title,
    String? artist,
    List<String>? artists,
    String? album,
    String? albumArtist,
    int? trackNumber,
    int? discNumber,
    int? year,
    Duration? duration,
    int? bitrate,
    int? sampleRate,
    String? codec,
    int? fileSize,
    bool? hasCover,
    String? coverPath,
    String? rawLyrics,
    AudioFormat? format,
  }) {
    return TrackInfo(
      id: id ?? this.id,
      uri: uri ?? this.uri,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      artists: artists ?? this.artists,
      album: album ?? this.album,
      albumArtist: albumArtist ?? this.albumArtist,
      trackNumber: trackNumber ?? this.trackNumber,
      discNumber: discNumber ?? this.discNumber,
      year: year ?? this.year,
      duration: duration ?? this.duration,
      bitrate: bitrate ?? this.bitrate,
      sampleRate: sampleRate ?? this.sampleRate,
      codec: codec ?? this.codec,
      fileSize: fileSize ?? this.fileSize,
      hasCover: hasCover ?? this.hasCover,
      coverPath: coverPath ?? this.coverPath,
      rawLyrics: rawLyrics ?? this.rawLyrics,
      format: format ?? this.format,
    );
  }
}

class AlbumInfo {
  final int id;
  final String name;
  final String artistName;
  final int year;
  final int trackCount;

  const AlbumInfo({
    required this.id,
    required this.name,
    required this.artistName,
    required this.year,
    this.trackCount = 0,
  });
}

class ArtistInfo {
  final int id;
  final String name;
  final int trackCount;
  final int albumCount;

  const ArtistInfo({
    required this.id,
    required this.name,
    this.trackCount = 0,
    this.albumCount = 0,
  });
}

class GenreInfo {
  final int id;
  final String name;

  const GenreInfo({
    required this.id,
    required this.name,
  });
}

class PlaylistInfo {
  final int id;
  final String name;
  final int createdAt;
  final int isSpecial; // 0=User, 1=Liked Songs, 2=History
  final int trackCount;

  const PlaylistInfo({
    required this.id,
    required this.name,
    required this.createdAt,
    this.isSpecial = 0,
    this.trackCount = 0,
  });
}

class PlaylistEntry {
  final int id;
  final int playlistId;
  final int trackId;
  final String uri;
  final String? customTitle;
  final int position;

  const PlaylistEntry({
    required this.id,
    required this.playlistId,
    required this.trackId,
    required this.uri,
    this.customTitle,
    required this.position,
  });
}


class LyricEntry {
  final int timestampMs;
  final String text;
  final bool isSynced;

  const LyricEntry({
    required this.timestampMs,
    required this.text,
    this.isSynced = true,
  });

  @override
  String toString() => 'LyricEntry($timestampMs ms: "$text")';
}

class PlayerStateSnapshot {
  final int index;
  final List<TrackInfo> queue;
  final bool playing;
  final bool buffering;
  final bool completed;
  final Duration position;
  final Duration duration;
  final double volume; // 0.0 to 200.0
  final double rate; // 0.5 to 1.5
  final double pitch; // 0.5 to 1.5
  final LoopMode loopMode;
  final bool shuffle;
  final Duration crossfadeDuration;
  final CrossfadeCurve crossfadeCurve;
  final bool crossfadeActive;
  final double crossfadeProgress; // 0.0 to 1.0
  final double instanceAVolume; // Current track volume
  final double instanceBVolume; // Preloaded next track volume

  const PlayerStateSnapshot({
    this.index = 0,
    this.queue = const [],
    this.playing = false,
    this.buffering = false,
    this.completed = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 100.0,
    this.rate = 1.0,
    this.pitch = 1.0,
    this.loopMode = LoopMode.off,
    this.shuffle = false,
    this.crossfadeDuration = const Duration(seconds: 5),
    this.crossfadeCurve = CrossfadeCurve.equalPower,
    this.crossfadeActive = false,
    this.crossfadeProgress = 0.0,
    this.instanceAVolume = 100.0,
    this.instanceBVolume = 0.0,
  });

  TrackInfo? get currentTrack =>
      (index >= 0 && index < queue.length) ? queue[index] : null;

  TrackInfo? get nextTrack =>
      (index + 1 < queue.length) ? queue[index + 1] : null;

  PlayerStateSnapshot copyWith({
    int? index,
    List<TrackInfo>? queue,
    bool? playing,
    bool? buffering,
    bool? completed,
    Duration? position,
    Duration? duration,
    double? volume,
    double? rate,
    double? pitch,
    LoopMode? loopMode,
    bool? shuffle,
    Duration? crossfadeDuration,
    CrossfadeCurve? crossfadeCurve,
    bool? crossfadeActive,
    double? crossfadeProgress,
    double? instanceAVolume,
    double? instanceBVolume,
  }) {
    return PlayerStateSnapshot(
      index: index ?? this.index,
      queue: queue ?? this.queue,
      playing: playing ?? this.playing,
      buffering: buffering ?? this.buffering,
      completed: completed ?? this.completed,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      volume: volume ?? this.volume,
      rate: rate ?? this.rate,
      pitch: pitch ?? this.pitch,
      loopMode: loopMode ?? this.loopMode,
      shuffle: shuffle ?? this.shuffle,
      crossfadeDuration: crossfadeDuration ?? this.crossfadeDuration,
      crossfadeCurve: crossfadeCurve ?? this.crossfadeCurve,
      crossfadeActive: crossfadeActive ?? this.crossfadeActive,
      crossfadeProgress: crossfadeProgress ?? this.crossfadeProgress,
      instanceAVolume: instanceAVolume ?? this.instanceAVolume,
      instanceBVolume: instanceBVolume ?? this.instanceBVolume,
    );
  }
}

class AppSettings {
  final List<String> musicDirectories;
  final bool crossfadeEnabled;
  final int crossfadeDurationSeconds;
  final double volume;
  final double playbackRate;
  final double playbackPitch;
  final LoopMode loopMode;
  final bool shuffle;
  final String themeMode; // 'system', 'light', 'dark'
  final String locale; // 'en', 'es'
  final String replayGain; // 'off', 'track', 'album'
  final double replayGainPreamp;

  const AppSettings({
    this.musicDirectories = const [],
    this.crossfadeEnabled = true,
    this.crossfadeDurationSeconds = 5,
    this.volume = 100.0,
    this.playbackRate = 1.0,
    this.playbackPitch = 1.0,
    this.loopMode = LoopMode.off,
    this.shuffle = false,
    this.themeMode = 'dark',
    this.locale = 'en',
    this.replayGain = 'off',
    this.replayGainPreamp = 0.0,
  });

  AppSettings copyWith({
    List<String>? musicDirectories,
    bool? crossfadeEnabled,
    int? crossfadeDurationSeconds,
    double? volume,
    double? playbackRate,
    double? playbackPitch,
    LoopMode? loopMode,
    bool? shuffle,
    String? themeMode,
    String? locale,
    String? replayGain,
    double? replayGainPreamp,
  }) {
    return AppSettings(
      musicDirectories: musicDirectories ?? this.musicDirectories,
      crossfadeEnabled: crossfadeEnabled ?? this.crossfadeEnabled,
      crossfadeDurationSeconds:
          crossfadeDurationSeconds ?? this.crossfadeDurationSeconds,
      volume: volume ?? this.volume,
      playbackRate: playbackRate ?? this.playbackRate,
      playbackPitch: playbackPitch ?? this.playbackPitch,
      loopMode: loopMode ?? this.loopMode,
      shuffle: shuffle ?? this.shuffle,
      themeMode: themeMode ?? this.themeMode,
      locale: locale ?? this.locale,
      replayGain: replayGain ?? this.replayGain,
      replayGainPreamp: replayGainPreamp ?? this.replayGainPreamp,
    );
  }
}

class ReleaseUpdateInfo {
  final String tagName;
  final String version;
  final String changelog;
  final String assetUrl;
  final bool isNewer;

  const ReleaseUpdateInfo({
    required this.tagName,
    required this.version,
    required this.changelog,
    required this.assetUrl,
    required this.isNewer,
  });
}
