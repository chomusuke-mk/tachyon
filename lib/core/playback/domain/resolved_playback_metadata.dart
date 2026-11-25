import 'dart:typed_data';

import 'package:miniaudio_player/miniaudio_player.dart' as ma;
import 'package:tachyon/core/metadata/metadata_utils.dart';
import 'package:tachyon/core/playback/domain/audio_playable.dart';
import 'package:tachyon/core/store/domain/artist.dart';
import 'package:tachyon/core/store/domain/track.dart';

/// Unified display metadata resolved from either persisted library records or
/// real-time engine metadata streams (for livestreams/radios and tracks whose
/// background scan analysis is still in progress).
class ResolvedPlaybackMetadata {
  /// Primary display title (song title or station name).
  final String title;

  /// Secondary display line (artist names, station context, or genre).
  final String subtitle;

  /// Album or container title, if available.
  final String? album;

  /// Cached local file path or remote artwork URI, if available.
  final String? artworkUri;

  /// In-memory cover image bytes extracted from live stream or file metadata.
  final Uint8List? artworkBytes;

  /// Formatted badge text describing live stream genre, bitrate, and codec.
  final String? liveStreamBadge;

  /// Resolved library [Artist] objects eligible for navigation.
  final List<Artist> clickableArtists;

  /// Whether any displayed fields were derived from live engine metadata.
  final bool isFromLiveMetadata;

  /// Creates a [ResolvedPlaybackMetadata] payload.
  const ResolvedPlaybackMetadata({
    required this.title,
    required this.subtitle,
    this.album,
    this.artworkUri,
    this.artworkBytes,
    this.liveStreamBadge,
    this.clickableArtists = const [],
    this.isFromLiveMetadata = false,
  });

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return (trimmed != null && trimmed.isNotEmpty) ? trimmed : null;
  }

  /// Resolves display metadata following source priority:
  /// - Streams/radios merge live ICY/Vorbis/header metadata with station fallback.
  /// - Already-persisted library tracks strictly use saved database metadata.
  /// - Pending/transient local tracks overlay live engine metadata onto file fallback.
  factory ResolvedPlaybackMetadata.resolve({
    required AudioPlayable playable,
    ma.AudioMetadata? liveMetadata,
    ma.AudioInfo? liveAudioInfo,
  }) {
    if (playable.isStream) {
      final stationName =
          _nonEmpty(playable.title) ??
          _nonEmpty(liveMetadata?.icy?.stationName) ??
          '';

      String? songTitle = _nonEmpty(liveMetadata?.title);
      String? songArtist = _nonEmpty(liveMetadata?.trackArtist);

      if (songTitle == null) {
        final icyTitle = _nonEmpty(liveMetadata?.icy?.streamTitle);
        if (icyTitle != null) {
          final sep = icyTitle.indexOf(' - ');
          if (sep > 0 && sep + 3 < icyTitle.length) {
            songArtist ??= _nonEmpty(icyTitle.substring(0, sep));
            songTitle = _nonEmpty(icyTitle.substring(sep + 3));
          } else {
            songTitle = icyTitle;
          }
        }
      }

      final String title;
      final String subtitle;
      final String? album;

      if (songTitle != null && songTitle != stationName) {
        title = songTitle;
        subtitle = [
          ?songArtist,
          if (stationName.isNotEmpty) stationName,
        ].join(' • ');
        album =
            _nonEmpty(liveMetadata?.album) ??
            (stationName.isNotEmpty ? stationName : playable.albumTitle);
      } else {
        title = stationName.isNotEmpty ? stationName : playable.title;
        subtitle =
            songArtist ??
            _nonEmpty(liveMetadata?.genre) ??
            _nonEmpty(liveMetadata?.icy?.stationGenre) ??
            playable.artistNames.join(', ');
        album = _nonEmpty(liveMetadata?.album) ?? playable.albumTitle;
      }

      final badgeParts = <String>[];
      final liveGenre =
          _nonEmpty(liveMetadata?.genre) ??
          _nonEmpty(liveMetadata?.icy?.stationGenre);
      if (liveGenre != null && liveGenre != subtitle) {
        badgeParts.add(liveGenre);
      }
      final icyBitrate = liveMetadata?.icy?.bitrateKbps;
      final infoBitrate =
          (liveAudioInfo != null && liveAudioInfo.bitrate >= 1000)
              ? liveAudioInfo.bitrate ~/ 1000
              : null;
      final kbps =
          (icyBitrate != null && icyBitrate > 0) ? icyBitrate : infoBitrate;
      if (kbps != null && kbps > 0) {
        badgeParts.add('$kbps kbps');
      }
      final codec = _nonEmpty(liveAudioInfo?.codec);
      if (codec != null && codec != 'Unknown') {
        badgeParts.add(codec);
      }

      final pic =
          (liveMetadata != null && liveMetadata.pictures.isNotEmpty)
              ? MetadataUtils.pickBestCoverPicture(liveMetadata.pictures)
              : null;
      final artworkBytes =
          (pic != null && pic.bytes.isNotEmpty) ? pic.bytes : null;

      return ResolvedPlaybackMetadata(
        title: title,
        subtitle: subtitle,
        album: album,
        artworkUri: playable.artworkUri,
        artworkBytes: artworkBytes,
        liveStreamBadge: badgeParts.isEmpty ? null : badgeParts.join(' • '),
        clickableArtists: const [],
        isFromLiveMetadata: liveMetadata != null || liveAudioInfo != null,
      );
    }

    if (playable is Track && !playable.isMetadataPending && playable.id != null) {
      return ResolvedPlaybackMetadata(
        title: playable.title,
        subtitle: playable.artistNames.join(', '),
        album: playable.albumTitle,
        artworkUri: playable.artworkUri,
        artworkBytes: null,
        liveStreamBadge: null,
        clickableArtists: playable.artists
            .where((a) => a.id != null)
            .toList(growable: false),
        isFromLiveMetadata: false,
      );
    }

    final liveTitle = _nonEmpty(liveMetadata?.title);
    final liveArtist =
        _nonEmpty(liveMetadata?.trackArtist) ??
        _nonEmpty(liveMetadata?.albumArtist);
    final liveAlbum = _nonEmpty(liveMetadata?.album);
    final artworkUri = playable.artworkUri;
    final hasCachedUri = artworkUri != null && artworkUri.trim().isNotEmpty;

    Uint8List? artworkBytes;
    if (!hasCachedUri &&
        liveMetadata != null &&
        liveMetadata.pictures.isNotEmpty) {
      final pic = MetadataUtils.pickBestCoverPicture(liveMetadata.pictures);
      if (pic != null && pic.bytes.isNotEmpty) {
        artworkBytes = pic.bytes;
      }
    }

    return ResolvedPlaybackMetadata(
      title: liveTitle ?? playable.title,
      subtitle: liveArtist ?? playable.artistNames.join(', '),
      album: liveAlbum ?? playable.albumTitle,
      artworkUri: artworkUri,
      artworkBytes: artworkBytes,
      liveStreamBadge: null,
      clickableArtists: const [],
      isFromLiveMetadata: liveMetadata != null,
    );
  }
}
