import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/library/presentation/album_detail_screen.dart';
import 'package:tachyon/features/library/presentation/artist_detail_screen.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/playlists/presentation/playlists_controller.dart';
import 'package:tachyon/shared/utils/toast_utils.dart';

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

T? _tryRead<T>(BuildContext context) {
  try {
    return context.read<T>();
  } catch (_) {
    return null;
  }
}

abstract final class TrackActionHelper {
  static Future<void> handleTrackAction(
    BuildContext context,
    Track track,
    TrackAction action, {
    List<Track>? contextTracks,
    bool enableDelete = true,
  }) async {
    final playback = _tryRead<PlaybackController>(context);

    switch (action) {
      case TrackAction.play:
        playback?.playTrack(track, contextTracks: contextTracks);
        break;
      case TrackAction.playNext:
        playback?.playNext(track);
        break;
      case TrackAction.addToQueue:
        playback?.addToQueue(track);
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

  static void showAddToPlaylistDialog(BuildContext context, Track track) {
    final strings = context.read<LocaleController>().localeStrings;
    final controller = _tryRead<PlaylistsController>(context);
    if (controller == null) return;
    final playlists = controller.userPlaylists;

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(strings.trAddPlaylist),
          content: playlists.isEmpty
              ? Text(strings.plNoPlaylists)
              : SizedBox(
                  width: 300,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: playlists.length,
                    itemBuilder: (context, index) {
                      final pl = playlists[index];
                      return ListTile(
                        leading: const Icon(Icons.playlist_add_rounded),
                        title: Text(pl.name),
                        onTap: () {
                          if (track.id != null && pl.id != null) {
                            controller.addTrackToPlaylist(pl.id!, track.id!);
                          }
                          Navigator.of(context).pop();
                          ToastUtils.showSuccess(
                            strings.trAddedToPlaylistFormatted(pl.name),
                          );
                        },
                      );
                    },
                  ),
                ),
          actions: [
            TextButton(
              onPressed: () => showCreatePlaylistDialog(context),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.secondary,
              ),
              child: Text(strings.plCreateNew),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(strings.selCancel),
            ),
          ],
        );
      },
    );
  }

  static void showCreatePlaylistDialog(BuildContext context) {
    final strings = context.read<LocaleController>().localeStrings;
    final controller = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(strings.plCreateNew),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(hintText: strings.plNewNameHint),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(strings.plCancelButton),
            ),
            FilledButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  context.read<PlaylistsController>().createPlaylist(name);
                }
                Navigator.of(dialogContext).pop();
              },
              child: Text(strings.plCreateButton),
            ),
          ],
        );
      },
    ).then((_) => controller.dispose());
  }

  static void showTrackInfoDialog(BuildContext context, Track track) {
    final strings = context.read<LocaleController>().localeStrings;
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(track.title),
          content: SingleChildScrollView(
            child: ListBody(
              children: [
                _infoRow(strings.trFilePath, track.filePath),
                if (track.artists.isNotEmpty)
                  _infoRow(
                    strings.trSortArtist,
                    track.artists.map((a) => a.name).join(', '),
                  ),
                if (track.album != null && track.album!.name.isNotEmpty)
                  _infoRow(strings.trSortAlbum, track.album!.name),
                if (track.codec != null)
                  _infoRow(strings.trCodec, track.codec!.toUpperCase()),
                if (track.bitrate != null)
                  _infoRow(strings.npBitrate, '${track.bitrate! ~/ 1000} kbps'),
                if (track.sampleRate != null)
                  _infoRow(strings.npSampleRate, '${track.sampleRate} Hz'),
                if (track.channels != null)
                  _infoRow(strings.npChannels, track.channels.toString()),
                if (track.year != null)
                  _infoRow(strings.alReleaseYear, track.year.toString()),
                _infoRow(
                  strings.trSortDuration,
                  '${(track.durationMs / 1000).toStringAsFixed(1)} s',
                ),
                _infoRow(
                  strings.trFileSize,
                  '${(track.fileSize / (1024 * 1024)).toStringAsFixed(2)} MB',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(strings.clClose),
            ),
          ],
        );
      },
    );
  }

  static void showDeleteTrackDialog(BuildContext context, Track track) {
    final strings = context.read<LocaleController>().localeStrings;
    final controller = _tryRead<LibraryController>(context);
    if (controller == null) return;
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(strings.trDelete),
          content: Text(strings.trDeleteConfirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(strings.selCancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () {
                controller.deleteTrack(track);
                Navigator.of(context).pop();
              },
              child: Text(strings.trDelete),
            ),
          ],
        );
      },
    );
  }

  static Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          SelectableText(value, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

class TrackPopupMenuButton extends StatelessWidget {
  final Track track;
  final List<Track>? contextTracks;
  final bool enableDelete;
  final Set<TrackAction>? allowedActions;
  final void Function(TrackAction action)? onActionSelected;

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
