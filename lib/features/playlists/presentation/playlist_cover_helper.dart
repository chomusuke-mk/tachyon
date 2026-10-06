import 'package:flutter/material.dart';
import 'package:tachyon/features/library/domain/playlist.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/shared/widgets/album_art_image.dart';

/// Finds the cover hash for a playlist by searching the most recently added tracks
/// until finding one with a valid cover thumbnail hash.
String? findPlaylistCoverHash(Playlist playlist, [List<Track>? tracks]) {
  if (playlist.entries.isNotEmpty) {
    final sorted = List<PlaylistEntry>.from(playlist.entries)
      ..sort((a, b) {
        final cmp = b.addedAt.compareTo(a.addedAt);
        if (cmp != 0) return cmp;
        return b.position.compareTo(a.position);
      });
    for (final entry in sorted) {
      final track = entry.track;
      if (track != null) {
        final hash = track.thumbnailHash ?? track.album?.thumbnailHash;
        if (hash != null && hash.trim().isNotEmpty) {
          return hash.trim();
        }
      }
    }
  }

  if (tracks != null && tracks.isNotEmpty) {
    for (final track in tracks.reversed) {
      final hash = track.thumbnailHash ?? track.album?.thumbnailHash;
      if (hash != null && hash.trim().isNotEmpty) {
        return hash.trim();
      }
    }
  }

  return null;
}

/// Builds the leading art widget for a playlist tile in the playlists list view.
///
/// - Favorites: cover in ThumbnailQuality.low with a heart icon overlay (or fallback).
/// - History: cover in ThumbnailQuality.low with a clock/history icon overlay (or fallback).
/// - User Playlists: cover in ThumbnailQuality.low without overlay (or fallback icon).
Widget buildPlaylistLeading(
  BuildContext context,
  Playlist playlist, {
  double size = 48,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  final coverHash = findPlaylistCoverHash(playlist);

  switch (playlist.type) {
    case PlaylistType.liked:
      if (coverHash != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8.0),
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              fit: StackFit.expand,
              children: [
                AlbumArtImage(
                  thumbnailHash: coverHash,
                  quality: ThumbnailQuality.low,
                  fit: BoxFit.cover,
                ),
                Container(
                  color: Colors.black38,
                  child: Center(
                    child: Icon(
                      Icons.favorite_rounded,
                      color: Colors.white,
                      size: size * 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: colorScheme.primary,
        child: Icon(
          Icons.favorite_rounded,
          color: Colors.white,
          size: size * 0.5,
        ),
      );

    case PlaylistType.history:
      if (coverHash != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8.0),
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              fit: StackFit.expand,
              children: [
                AlbumArtImage(
                  thumbnailHash: coverHash,
                  quality: ThumbnailQuality.low,
                  fit: BoxFit.cover,
                ),
                Container(
                  color: Colors.black38,
                  child: Center(
                    child: Icon(
                      Icons.history_rounded,
                      color: Colors.white,
                      size: size * 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.history_rounded,
          color: colorScheme.onSurfaceVariant,
          size: size * 0.5,
        ),
      );

    case PlaylistType.user:
      if (coverHash != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8.0),
          child: SizedBox(
            width: size,
            height: size,
            child: AlbumArtImage(
              thumbnailHash: coverHash,
              quality: ThumbnailQuality.low,
              fit: BoxFit.cover,
            ),
          ),
        );
      }
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: colorScheme.secondaryContainer,
        child: Icon(
          Icons.playlist_play_rounded,
          color: colorScheme.onSecondaryContainer,
          size: size * 0.5,
        ),
      );
  }
}
