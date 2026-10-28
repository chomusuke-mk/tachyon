import 'package:miniaudio_player/miniaudio_player.dart' as ma;
import 'audio_playable.dart';

/// Online radio station and livestream audio entity independent of the local library catalog.
class RadioStation implements AudioPlayable {
  @override
  final int? id;
  final String name;
  final String streamUrl;
  final String? homepageUrl;
  final String? faviconUrl;
  final String? genre;
  final String? country;
  final int? bitrateKbps;
  final String? codec; // 'mp3', 'aac', 'hls'
  final bool isFavorite;
  final DateTime createdAt;

  const RadioStation({
    this.id,
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
  String? get thumbnailHash => null;

  @override
  String get filePath => streamUrl;

  @override
  double? get replayGainTrackGain => null;

  @override
  double? get replayGainTrackPeak => null;

  @override
  bool get isStream => true;

  @override
  ma.EngineItem<AudioPlayable> toEngineItem({int position = 0}) {
    return ma.EngineItem.liveStream(
      Uri.parse(streamUrl),
      jitterBuffer: const Duration(seconds: 5),
      data: this,
      position: position,
    );
  }

  RadioStation copyWith({
    int? id,
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
          streamUrl == other.streamUrl;

  @override
  int get hashCode => Object.hash(id, streamUrl);
}
