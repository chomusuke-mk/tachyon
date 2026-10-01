import 'package:flutter/material.dart';
import 'package:tachyon/features/library/domain/track.dart';

import 'album_art_image.dart';

enum TrackAction {
  play,
  playNext,
  addToQueue,
  addToPlaylist,
  viewAlbum,
  viewArtist,
  fileInfo,
  delete,
}

class TrackTile extends StatelessWidget {
  final Track track;
  final bool isPlaying;
  final bool isSelected;
  final bool isSelectionMode;
  final bool isLiked;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<bool?>? onSelectChanged;
  final VoidCallback? onToggleLike;
  final void Function(TrackAction action)? onActionSelected;

  const TrackTile({
    super.key,
    required this.track,
    this.isPlaying = false,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.isLiked = false,
    this.onTap,
    this.onLongPress,
    this.onSelectChanged,
    this.onToggleLike,
    this.onActionSelected,
  });

  String _formatDuration(int durationMs) {
    final duration = Duration(milliseconds: durationMs);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final leadingWidget = isSelectionMode
        ? Checkbox(value: isSelected, onChanged: onSelectChanged)
        : Stack(
            alignment: Alignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8.0),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: AlbumArtImage(
                    filePath: track.filePath,
                    fit: BoxFit.cover,
                    cacheWidth: 96,
                    cacheHeight: 96,
                  ),
                ),
              ),
              if (isPlaying)
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: Icon(
                    Icons.equalizer_rounded,
                    color: colorScheme.primary,
                    size: 24,
                  ),
                ),
            ],
          );

    return SizedBox(
      height: 72.0,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
        leading: leadingWidget,
        title: Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: isPlaying ? colorScheme.primary : colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          '${track.artistName} • ${track.albumName}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _formatDuration(track.durationMs),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (onToggleLike != null)
              IconButton(
                icon: Icon(
                  isLiked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: isLiked
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                  size: 20,
                ),
                onPressed: onToggleLike,
              ),
            if (onActionSelected != null)
              PopupMenuButton<TrackAction>(
                icon: Icon(
                  Icons.more_vert_rounded,
                  color: colorScheme.onSurfaceVariant,
                  size: 20,
                ),
                onSelected: onActionSelected,
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: TrackAction.play,
                    child: Row(
                      children: [
                        Icon(Icons.play_arrow_rounded, size: 20),
                        SizedBox(width: 12),
                        Text('Play'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: TrackAction.playNext,
                    child: Row(
                      children: [
                        Icon(Icons.playlist_play_rounded, size: 20),
                        SizedBox(width: 12),
                        Text('Play Next'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: TrackAction.addToQueue,
                    child: Row(
                      children: [
                        Icon(Icons.queue_music_rounded, size: 20),
                        SizedBox(width: 12),
                        Text('Add to Queue'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: TrackAction.addToPlaylist,
                    child: Row(
                      children: [
                        Icon(Icons.add_to_photos_rounded, size: 20),
                        SizedBox(width: 12),
                        Text('Add to Playlist'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: TrackAction.viewAlbum,
                    child: Row(
                      children: [
                        Icon(Icons.album_rounded, size: 20),
                        SizedBox(width: 12),
                        Text('View Album'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: TrackAction.viewArtist,
                    child: Row(
                      children: [
                        Icon(Icons.person_rounded, size: 20),
                        SizedBox(width: 12),
                        Text('View Artist'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: TrackAction.fileInfo,
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 20),
                        SizedBox(width: 12),
                        Text('File Info'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: TrackAction.delete,
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline_rounded,
                          size: 20,
                          color: Colors.redAccent,
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Delete',
                          style: TextStyle(color: Colors.redAccent),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}
