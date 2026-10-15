import 'package:flutter/material.dart';
import 'package:tachyon/features/library/domain/playlist.dart';
import 'package:tachyon/shared/utils/metadata_utils.dart';
import 'package:tachyon/shared/widgets/album_art_image.dart';

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

  switch (playlist.type) {
    case PlaylistType.liked:
      if (playlist.coverHash != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8.0),
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              fit: StackFit.expand,
              children: [
                AlbumArtImage(
                  thumbnailHash: playlist.coverHash,
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
      if (playlist.coverHash != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8.0),
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              fit: StackFit.expand,
              children: [
                AlbumArtImage(
                  thumbnailHash: playlist.coverHash,
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
      if (playlist.coverHash != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8.0),
          child: SizedBox(
            width: size,
            height: size,
            child: AlbumArtImage(
              thumbnailHash: playlist.coverHash,
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
