import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/playlists/presentation/playlists_controller.dart';

import 'album_art_image.dart';
import 'track_action_helper.dart';

export 'track_action_helper.dart';

class TrackTile extends StatelessWidget {
  final Track track;
  final bool? isPlaying;
  final bool isSelected;
  final bool isSelectionMode;
  final bool? isLiked;
  final bool showLikeButton;
  final bool showActions;
  final bool enableDelete;
  final Set<TrackAction>? allowedActions;
  final List<Track>? contextTracks;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<bool?>? onSelectChanged;
  final VoidCallback? onToggleLike;
  final void Function(TrackAction action)? onActionSelected;
  final List<Widget>? additionalActions;
  final Widget? additionalTrailing;

  const TrackTile({
    super.key,
    required this.track,
    this.isPlaying,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.isLiked,
    this.showLikeButton = false,
    this.showActions = true,
    this.enableDelete = true,
    this.allowedActions,
    this.contextTracks,
    this.onTap,
    this.onLongPress,
    this.onSelectChanged,
    this.onToggleLike,
    this.onActionSelected,
    this.additionalActions,
    this.additionalTrailing,
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

  bool _resolveIsPlaying(BuildContext context) {
    try {
      return context.select<PlaybackController, bool>(
        (c) => c.isCurrentTrack(track),
      );
    } catch (_) {
      return false;
    }
  }

  bool _resolveIsLiked(BuildContext context, int trackId) {
    try {
      return context.select<PlaylistsController, bool>(
        (p) => p.isTrackLiked(trackId),
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final strings = context.watch<LocaleController>().localeStrings;

    final effectiveIsPlaying = isPlaying ?? _resolveIsPlaying(context);

    final effectiveIsLiked = isLiked ??
        (showLikeButton && track.id != null
            ? _resolveIsLiked(context, track.id!)
            : false);

    final effectiveOnToggleLike = onToggleLike ??
        (showLikeButton && track.id != null
            ? () {
                try {
                  context.read<PlaylistsController>().toggleLikeTrack(track);
                } catch (_) {}
              }
            : null);

    final artistText = track.artists.isNotEmpty
        ? track.artists.map((a) => a.name).join(', ')
        : strings.trUnknownArtist;
    final albumText = track.album?.name;
    final subtitleText = (albumText != null && albumText.isNotEmpty)
        ? '$artistText • $albumText'
        : artistText;

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
                    thumbnailHash:
                        track.thumbnailHash ?? track.album?.thumbnailHash,
                    fit: BoxFit.cover,
                    cacheWidth: 100,
                    cacheHeight: 100,
                  ),
                ),
              ),
              if (effectiveIsPlaying)
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

    final effectiveOnTap = onTap ??
        () {
          try {
            context
                .read<PlaybackController>()
                .playTrack(track, contextTracks: contextTracks);
          } catch (_) {}
        };

    return SizedBox(
      height: 72.0,
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
          leading: leadingWidget,
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: effectiveIsPlaying
                  ? colorScheme.primary
                  : colorScheme.onSurface,
            ),
          ),
          subtitle: Text(
            subtitleText,
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
              if (showLikeButton || onToggleLike != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    effectiveIsLiked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: effectiveIsLiked
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                  tooltip:
                      effectiveIsLiked ? strings.npUnlike : strings.npLike,
                  onPressed: effectiveOnToggleLike,
                ),
              if (showActions)
                TrackPopupMenuButton(
                  track: track,
                  contextTracks: contextTracks,
                  enableDelete: enableDelete,
                  allowedActions: allowedActions,
                  onActionSelected: onActionSelected,
                ),
              ...?additionalActions,
              ?additionalTrailing,
            ],
          ),
          onTap: effectiveOnTap,
          onLongPress: onLongPress,
        ),
      ),
    );
  }
}
