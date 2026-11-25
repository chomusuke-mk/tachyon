import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/core/store/domain/playlist.dart';
import 'package:tachyon/core/store/domain/track.dart';
import 'package:tachyon/features/library/presentation/controllers/library_controller.dart';
import 'package:tachyon/features/locales/presentation/controllers/locale_controller.dart';
import 'package:tachyon/features/playlists/presentation/controllers/playlists_controller.dart';
import 'package:tachyon/features/playlists/presentation/widgets/playlist_cover_helper.dart';
import 'package:tachyon/features/playlists/presentation/widgets/playlist_dialogs.dart';
import 'package:tachyon/shared/utils/toast_utils.dart';

enum _QueueAddMode { cancel, addAnyway, onlyNew }

/// Modal dialogs invoked from track action menus and queue controls for
/// playlist assignment, file metadata inspection, and library deletion.
abstract final class TrackActionDialogs {
  /// Opens a dialog prompting the user to add [track] to an existing or newly
  /// created playlist.
  static void showAddToPlaylistDialog(BuildContext context, Track track) {
    _showPlaylistPickerDialog(
      context,
      onSelectPlaylist: (dialogContext, controller, pl, strings) async {
        if (pl.id == null) return;

        final alreadyIn = pl.entries.any((entry) {
          if (track.id != null && entry.track?.id != null) {
            return entry.track!.id == track.id;
          }
          return entry.track?.filePath == track.filePath;
        });

        if (alreadyIn) {
          final confirmed = await showDialog<bool>(
            context: dialogContext,
            builder: (confirmContext) {
              return AlertDialog(
                icon: Icon(
                  Icons.warning_amber_rounded,
                  color: Theme.of(confirmContext).colorScheme.error,
                  size: 28,
                ),
                title: Text(strings.plDuplicateTitle),
                content: Text(strings.plDuplicateConfirmFormatted(pl.name)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(confirmContext).pop(false),
                    child: Text(strings.plCancelButton),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(confirmContext).pop(true),
                    child: Text(strings.plAddAnyway),
                  ),
                ],
              );
            },
          );
          if (confirmed != true) return;
        }

        if (track.id != null) {
          await controller.addTrackToPlaylist(pl.id!, track.id!);
        }
        if (dialogContext.mounted) {
          Navigator.of(dialogContext).pop();
        }
        ToastUtils.showSuccess(strings.trAddedToPlaylistFormatted(pl.name));
      },
    );
  }

  /// Opens a dialog prompting the user to add all local library tracks in
  /// [queue] into a selected playlist, handling duplicate entries explicitly.
  static void showAddQueueToPlaylistDialog(
    BuildContext context,
    List<AudioSource<AudioPlayable>> queue,
  ) {
    final queueTracks = queue
        .map((e) => e.track)
        .whereType<Track>()
        .where((t) => t.id != null)
        .toList();
    if (queueTracks.isEmpty) return;

    _showPlaylistPickerDialog(
      context,
      onSelectPlaylist: (dialogContext, controller, pl, strings) async {
        if (pl.id == null) return;

        final existingTrackIds = pl.entries
            .map((e) => e.track?.id)
            .whereType<int>()
            .toSet();

        final duplicates = queueTracks
            .where((t) => existingTrackIds.contains(t.id))
            .toList();
        final newTracks = queueTracks
            .where((t) => !existingTrackIds.contains(t.id))
            .toList();

        List<Track>? tracksToAdd;
        if (duplicates.isNotEmpty) {
          final choice = await showDialog<_QueueAddMode>(
            context: dialogContext,
            builder: (confirmContext) {
              return AlertDialog(
                icon: Icon(
                  Icons.warning_amber_rounded,
                  color: Theme.of(confirmContext).colorScheme.error,
                  size: 28,
                ),
                title: Text(strings.plDuplicateQueueTitle),
                content: Text(
                  strings.plDuplicateQueueConfirmFormatted(pl.name),
                ),
                actions: [
                  TextButton(
                    onPressed: () =>
                        Navigator.of(confirmContext).pop(_QueueAddMode.cancel),
                    child: Text(strings.plCancelButton),
                  ),
                  FilledButton.tonal(
                    onPressed: () => Navigator.of(
                      confirmContext,
                    ).pop(_QueueAddMode.addAnyway),
                    child: Text(strings.plAddAnyway),
                  ),
                  FilledButton(
                    onPressed: newTracks.isNotEmpty
                        ? () => Navigator.of(
                            confirmContext,
                          ).pop(_QueueAddMode.onlyNew)
                        : null,
                    child: Text(
                      strings.plInsertOnlyNewFormatted(newTracks.length),
                    ),
                  ),
                ],
              );
            },
          );

          if (choice == null || choice == _QueueAddMode.cancel) {
            return;
          } else if (choice == _QueueAddMode.addAnyway) {
            tracksToAdd = queueTracks;
          } else if (choice == _QueueAddMode.onlyNew) {
            tracksToAdd = newTracks;
          }
        } else {
          tracksToAdd = queueTracks;
        }

        if (tracksToAdd != null && tracksToAdd.isNotEmpty) {
          final trackIds = tracksToAdd.map((t) => t.id!).toList();
          await controller.addTracksToPlaylist(pl.id!, trackIds);
        }

        if (dialogContext.mounted) {
          Navigator.of(dialogContext).pop();
        }
        ToastUtils.showSuccess(strings.trAddedToPlaylistFormatted(pl.name));
      },
    );
  }

  static void _showPlaylistPickerDialog(
    BuildContext context, {
    required Future<void> Function(
      BuildContext dialogContext,
      PlaylistsController controller,
      Playlist playlist,
      dynamic strings,
    )
    onSelectPlaylist,
  }) {
    final strings = context.read<LocaleController>().localeStrings;
    final controller = context.read<PlaylistsController>();

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        bool isProcessing = false;

        return ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final playlists = controller.userPlaylists;
            final colorScheme = Theme.of(context).colorScheme;

            Future<void> handleTap(Playlist pl) async {
              if (isProcessing) return;
              isProcessing = true;
              try {
                await onSelectPlaylist(dialogContext, controller, pl, strings);
              } finally {
                isProcessing = false;
              }
            }

            return AlertDialog(
              title: Text(strings.trAddPlaylist),
              content: playlists.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 24.0,
                        horizontal: 8.0,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.playlist_remove_rounded,
                            size: 48,
                            color: colorScheme.onSurfaceVariant.withAlpha(128),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            strings.plNoPlaylists,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 360,
                        maxHeight:
                            MediaQuery.sizeOf(dialogContext).height * 0.6,
                      ),
                      child: SizedBox(
                        width: 320,
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: playlists.length,
                          itemBuilder: (context, index) {
                            final pl = playlists[index];
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4.0,
                              ),
                              leading: buildPlaylistLeading(
                                dialogContext,
                                pl,
                                size: 40,
                              ),
                              title: Text(
                                pl.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                strings.plTracksCountFormatted(pl.trackCount),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.add_rounded),
                                tooltip: strings.sAdd,
                                onPressed: () => handleTap(pl),
                              ),
                              onTap: () => handleTap(pl),
                            );
                          },
                        ),
                      ),
                    ),
              actions: [
                TextButton(
                  onPressed: () => PlaylistDialogs.showCreate(dialogContext),
                  style: TextButton.styleFrom(
                    foregroundColor: colorScheme.secondary,
                  ),
                  child: Text(strings.plCreateNew),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(strings.selCancel),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Displays detailed file path, codec, sample rate, duration, and tag
  /// metadata for [track].
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

  /// Displays a destructive confirmation dialog before removing [track] from
  /// the library index and disk.
  static void showDeleteTrackDialog(BuildContext context, Track track) {
    final strings = context.read<LocaleController>().localeStrings;
    final controller = context.read<LibraryController>();
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
