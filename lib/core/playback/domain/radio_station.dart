import 'package:miniaudio_player/miniaudio_player.dart' as ma;
import 'audio_playable.dart';

/// Online radio station and livestream audio entity independent of the local library catalog.
class RadioStation implements AudioPlayable {
  @override
  final int? id;

  /// External directory UUID (such as Radio Browser station UUID), if any.
  final String? stationUuid;

  /// Display name of the radio station.
  final String name;

  /// Direct audio stream URL.
  final String streamUrl;

  /// Station website URL, if provided.
  final String? homepageUrl;

  /// Station logo or favicon image URL, if provided.
  final String? faviconUrl;

  /// Primary broadcast genre or tag label, if provided.
  final String? genre;

  /// Broadcast country name or code, if provided.
  final String? country;

  /// Advertised stream bitrate in kbps, if known.
  final int? bitrateKbps;

  /// Stream audio codec identifier (e.g., `'mp3'`, `'aac'`, `'hls'`).
  final String? codec;

  /// Whether the station is marked as a user favorite.
  final bool isFavorite;

  /// Timestamp when this station record was created.
  final DateTime createdAt;

  /// Creates an immutable [RadioStation] entity.
  const RadioStation({
    this.id,
    this.stationUuid,
    required this.name,
    required this.streamUrl,
    this.homepageUrl,
    this.faviconUrl,
    this.genre,
    this.country,
    this.bitrateKbps,
    this.codec,
    this.isFavorite = false,
    required this.createdAt,
  });

  @override
  String get title => name;

  @override
  List<String> get artistNames =>
      [genre != null && genre!.isNotEmpty ? genre! : 'Online Radio'];

  @override
  String? get albumTitle => country;

  @override
  Duration get duration => Duration.zero;

  @override
  String? get artworkUri => faviconUrl;

  @override
  String get filePath => streamUrl;

  @override
  double? get replayGainTrackGain => null;

  @override
  double? get replayGainTrackPeak => null;

  @override
  bool get isStream => true;

  @override
  ma.AudioSource<AudioPlayable> toAudioSource() {
    return ma.AudioSource<AudioPlayable>(
      Uri.parse(streamUrl),
      data: this,
    );
  }

  /// Returns a copy of this station with the specified fields updated.
  RadioStation copyWith({
    int? id,
    String? stationUuid,
    String? name,
    String? streamUrl,
    String? homepageUrl,
    String? faviconUrl,
    String? genre,
    String? country,
    int? bitrateKbps,
    String? codec,
    bool? isFavorite,
    DateTime? createdAt,
  }) {
    return RadioStation(
      id: id ?? this.id,
      stationUuid: stationUuid ?? this.stationUuid,
      name: name ?? this.name,
      streamUrl: streamUrl ?? this.streamUrl,
      homepageUrl: homepageUrl ?? this.homepageUrl,
      faviconUrl: faviconUrl ?? this.faviconUrl,
      genre: genre ?? this.genre,
      country: country ?? this.country,
      bitrateKbps: bitrateKbps ?? this.bitrateKbps,
      codec: codec ?? this.codec,
      isFavorite: isFavorite ?? this.isFavorite,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RadioStation &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          stationUuid == other.stationUuid &&
          streamUrl == other.streamUrl;

  @override
  int get hashCode => Object.hash(id, stationUuid, streamUrl);
}
