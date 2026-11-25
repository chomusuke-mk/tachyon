import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/core/store/domain/track.dart';
import 'package:tachyon/features/library/presentation/screens/album_detail_screen.dart';
import 'package:tachyon/features/library/presentation/screens/artist_detail_screen.dart';
import 'package:tachyon/features/locales/presentation/controllers/locale_controller.dart';
import 'package:tachyon/features/playlists/presentation/widgets/playlist_dialogs.dart';
import 'package:tachyon/shared/widgets/track_action_dialogs.dart';

/// Context-menu action identifiers available on library and queue tracks.
enum TrackAction {
  /// Starts playing the track within its surrounding list context.
  play,

  /// Inserts the track immediately after the active queue item.
  playNext,

  /// Appends the track to the end of the active playback queue.
  addToQueue,

  /// Opens the playlist picker dialog for adding the track.
  addToPlaylist,

  /// Navigates to the album detail screen for the track's album.
  viewAlbum,

  /// Navigates to the primary artist detail screen for the track.
  viewArtist,

  /// Displays technical and tag metadata for the audio file.
  fileInfo,

  /// Confirms and deletes the track from the library.
  delete,
}

/// Dispatcher translating [TrackAction] selections into navigation, playback
/// mutations, or modal confirmation/picker dialogs.
abstract final class TrackActionHelper {
  /// Executes [action] for [track] using providers from [context].
  static Future<void> handleTrackAction(
    BuildContext context,
    Track track,
    TrackAction action, {
    List<Track>? contextTracks,
    bool enableDelete = true,
  }) async {
    final playback = context.read<PlaybackController>();

    switch (action) {
      case TrackAction.play:
        playback.playTrack(track, contextTracks: contextTracks);
        break;
      case TrackAction.playNext:
        playback.playNext(track);
        break;
      case TrackAction.addToQueue:
        playback.addToQueue(track);
        break;
      case TrackAction.addToPlaylist:
        showAddToPlaylistDialog(context, track);
        break;
      case TrackAction.viewAlbum:
        if (track.album != null) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => AlbumDetailScreen(album: track.album!),
            ),
          );
        }
        break;
      case TrackAction.viewArtist:
        final artist = track.artists.firstOrNull;
        if (artist != null) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ArtistDetailScreen(artist: artist),
            ),
          );
        }
        break;
      case TrackAction.fileInfo:
        showTrackInfoDialog(context, track);
        break;
      case TrackAction.delete:
        if (enableDelete) {
          showDeleteTrackDialog(context, track);
        }
        break;
    }
  }

  /// Opens the add-track-to-playlist modal dialog for [track].
  static void showAddToPlaylistDialog(BuildContext context, Track track) =>
      TrackActionDialogs.showAddToPlaylistDialog(context, track);

  /// Opens the add-queue-to-playlist modal dialog for [queue].
  static void showAddQueueToPlaylistDialog(
    BuildContext context,
    List<AudioSource<AudioPlayable>> queue,
  ) => TrackActionDialogs.showAddQueueToPlaylistDialog(context, queue);

  /// Opens the create-playlist dialog.
  static Future<void> showCreatePlaylistDialog(BuildContext context) =>
      PlaylistDialogs.showCreate(context);

  /// Opens the file metadata inspection dialog for [track].
  static void showTrackInfoDialog(BuildContext context, Track track) =>
      TrackActionDialogs.showTrackInfoDialog(context, track);

  /// Opens the delete-track confirmation dialog for [track].
  static void showDeleteTrackDialog(BuildContext context, Track track) =>
      TrackActionDialogs.showDeleteTrackDialog(context, track);
}

/// Overflow menu button exposing localized [TrackAction] entries for [track].
class TrackPopupMenuButton extends StatelessWidget {
  /// Track whose context menu actions are presented.
  final Track track;

  /// Optional list providing surrounding queue context when [TrackAction.play]
  /// is selected.
  final List<Track>? contextTracks;

  /// Whether [TrackAction.delete] is included when [allowedActions] is omitted.
  final bool enableDelete;

  /// Explicit subset of allowed actions overriding the default menu set.
  final Set<TrackAction>? allowedActions;

  /// Optional custom handler invoked instead of [TrackActionHelper.handleTrackAction].
  final void Function(TrackAction action)? onActionSelected;

  /// Creates a [TrackPopupMenuButton].
  const TrackPopupMenuButton({
    super.key,
    required this.track,
    this.contextTracks,
    this.enableDelete = true,
    this.allowedActions,
    this.onActionSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final strings = context.watch<LocaleController>().localeStrings;

    final effectiveAllowed =
        allowedActions ??
        {
          TrackAction.play,
          TrackAction.playNext,
          TrackAction.addToQueue,
          TrackAction.addToPlaylist,
          TrackAction.viewAlbum,
          TrackAction.viewArtist,
          TrackAction.fileInfo,
          if (enableDelete) TrackAction.delete,
        };

    return PopupMenuButton<TrackAction>(
      icon: Icon(
        Icons.more_vert_rounded,
        color: colorScheme.onSurfaceVariant,
        size: 20,
      ),
      tooltip: strings.trMoreActions,
      padding: EdgeInsets.zero,
      onSelected: (action) {
        if (onActionSelected != null) {
          onActionSelected!(action);
        } else {
          TrackActionHelper.handleTrackAction(
            context,
            track,
            action,
            contextTracks: contextTracks,
            enableDelete: enableDelete,
          );
        }
      },
      itemBuilder: (context) => [
        if (effectiveAllowed.contains(TrackAction.play))
          PopupMenuItem(
            value: TrackAction.play,
            child: Row(
              children: [
                const Icon(Icons.play_arrow_rounded, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(strings.trPlay, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        if (effectiveAllowed.contains(TrackAction.playNext))
          PopupMenuItem(
            value: TrackAction.playNext,
            child: Row(
              children: [
                const Icon(Icons.playlist_play_rounded, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    strings.trPlayNext,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        if (effectiveAllowed.contains(TrackAction.addToQueue))
          PopupMenuItem(
            value: TrackAction.addToQueue,
            child: Row(
              children: [
                const Icon(Icons.queue_music_rounded, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    strings.trAddQueue,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        if (effectiveAllowed.contains(TrackAction.addToPlaylist))
          PopupMenuItem(
            value: TrackAction.addToPlaylist,
            child: Row(
              children: [
                const Icon(Icons.add_to_photos_rounded, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    strings.trAddPlaylist,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        if (effectiveAllowed.contains(TrackAction.viewAlbum))
          PopupMenuItem(
            value: TrackAction.viewAlbum,
            enabled: track.album != null,
            child: Row(
              children: [
                const Icon(Icons.album_rounded, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    strings.trViewAlbum,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        if (effectiveAllowed.contains(TrackAction.viewArtist))
          PopupMenuItem(
            value: TrackAction.viewArtist,
            enabled: track.artists.isNotEmpty,
            child: Row(
              children: [
                const Icon(Icons.person_rounded, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    strings.trViewArtist,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        if (effectiveAllowed.contains(TrackAction.fileInfo))
          PopupMenuItem(
            value: TrackAction.fileInfo,
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    strings.trFileInfo,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        if (effectiveAllowed.contains(TrackAction.delete))
          PopupMenuItem(
            value: TrackAction.delete,
            child: Row(
              children: [
                const Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: Colors.redAccent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    strings.trDelete,
                    style: const TextStyle(color: Colors.redAccent),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
