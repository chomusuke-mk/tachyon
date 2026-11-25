import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/core/store/domain/track.dart';
import 'package:tachyon/features/locales/presentation/controllers/locale_controller.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/features/playlists/presentation/controllers/playlists_controller.dart';
import 'package:tachyon/shared/utils/duration_formatter.dart';

import 'album_art_image.dart';
import 'track_action_helper.dart';

export 'track_action_helper.dart';

/// List tile displaying a [Track] with artwork, duration, like toggle, and context actions.
class TrackTile extends StatelessWidget {
  /// Track metadata displayed by this tile.
  final Track track;

  /// Optional override indicating whether [track] is currently playing.
  ///
  /// Derived from [PlaybackController.isCurrentTrack] when `null`.
  final bool? isPlaying;

  /// Whether the selection checkbox is checked when [isSelectionMode] is `true`.
  final bool isSelected;

  /// Whether the leading artwork is replaced by a multi-select [Checkbox].
  final bool isSelectionMode;

  /// Optional override indicating whether [track] is marked as liked.
  ///
  /// Resolved from [PlaylistsController.isTrackLiked] when `null` and
  /// [showLikeButton] is `true`.
  final bool? isLiked;

  /// Whether the favorite toggle button is shown in the trailing row.
  final bool showLikeButton;

  /// Whether the overflow [TrackPopupMenuButton] is shown in the trailing row.
  final bool showActions;

  /// Whether the delete action is enabled in the trailing action menu.
  final bool enableDelete;

  /// Optional subset of [TrackAction] entries permitted in the overflow menu.
  final Set<TrackAction>? allowedActions;

  /// Optional list of tracks forming the playback queue context when tapped or played.
  final List<Track>? contextTracks;

  /// Optional tap callback overriding the default playback action.
  final VoidCallback? onTap;

  /// Optional callback invoked when the tile is long-pressed.
  final VoidCallback? onLongPress;

  /// Callback invoked when the selection checkbox value changes in [isSelectionMode].
  final ValueChanged<bool?>? onSelectChanged;

  /// Optional callback overriding the default favorite toggle behavior.
  final VoidCallback? onToggleLike;

  /// Optional callback overriding default [TrackAction] handling from the overflow menu.
  final void Function(TrackAction action)? onActionSelected;

  /// Optional extra widgets inserted into the trailing row after the overflow menu.
  final List<Widget>? additionalActions;

  /// Optional single widget appended at the end of the trailing row.
  final Widget? additionalTrailing;

  /// Creates a [TrackTile].
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

    final effectiveIsLiked =
        isLiked ??
        (showLikeButton && track.id != null
            ? _resolveIsLiked(context, track.id!)
            : false);

    final effectiveOnToggleLike =
        onToggleLike ??
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
                    artworkUri: track.artworkUri,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
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

    final effectiveOnTap =
        onTap ??
        () {
          try {
            context.read<PlaybackController>().playTrack(
              track,
              contextTracks: contextTracks,
            );
          } catch (_) {}
        };

    return RepaintBoundary(
      child: SizedBox(
        height: 72.0,
        child: Material(
          type: MaterialType.transparency,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
            leading: RepaintBoundary(child: leadingWidget),
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
                (track.isMetadataPending && track.durationMs <= 0)
                    ? '--:--'
                    : track.durationMs.toFormattedDuration(),
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
                    size: 20,
                    color: effectiveIsLiked
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                  tooltip: effectiveIsLiked ? strings.npUnlike : strings.npLike,
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
      ),
    );
  }
}
