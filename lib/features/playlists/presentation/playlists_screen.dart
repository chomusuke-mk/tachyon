import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/library/domain/playlist.dart';

import 'playlist_cover_helper.dart';
import 'playlist_detail_screen.dart';
import 'playlists_controller.dart';

class PlaylistsScreen extends StatelessWidget {
  const PlaylistsScreen({super.key});

  void _showCreateDialog(BuildContext context) {
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

  void _showRenameDialog(BuildContext context, Playlist playlist) {
    final controller = TextEditingController(text: playlist.name);

    final strings = context.read<LocaleController>().localeStrings;
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(strings.plRename),
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
                if (name.isNotEmpty && playlist.id != null) {
                  context.read<PlaylistsController>().renamePlaylist(
                    playlist.id!,
                    name,
                  );
                }
                Navigator.of(dialogContext).pop();
              },
              child: Text(strings.plRename),
            ),
          ],
        );
      },
    ).then((_) => controller.dispose());
  }

  void _showDeleteDialog(BuildContext context, Playlist playlist) {
    final strings = context.read<LocaleController>().localeStrings;

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(strings.plDelete),
          content: Text(strings.plDeleteConfirmFormatted(playlist.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(strings.plCancelButton),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () {
                if (playlist.id != null) {
                  context.read<PlaylistsController>().deletePlaylist(
                    playlist.id!,
                  );
                }
                Navigator.of(context).pop();
              },
              child: Text(strings.plDelete),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleController>().localeStrings;
    final playlistsCtrl = context.watch<PlaylistsController>();
    final colorScheme = Theme.of(context).colorScheme;

    final likedPlaylist = playlistsCtrl.likedSongsPlaylist;
    final historyPlaylist = playlistsCtrl.historyPlaylist;
    final userPlaylists = playlistsCtrl.userPlaylists;

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.plTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: strings.plCreateNew,
            onPressed: () => _showCreateDialog(context),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Special Playlists: Liked Songs & History
                  if (likedPlaylist != null)
                    RepaintBoundary(
                      child: Card(
                        margin: const EdgeInsets.only(bottom: 8.0),
                        clipBehavior: Clip.antiAlias,
                        child: Material(
                          type: MaterialType.transparency,
                          child: ListTile(
                            leading: buildPlaylistLeading(context, likedPlaylist),
                            title: Text(
                              strings.plLikedSongs,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              strings.plTracksCountFormatted(
                                likedPlaylist.trackCount,
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      PlaylistDetailScreen(playlist: likedPlaylist),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  if (historyPlaylist != null)
                    RepaintBoundary(
                      child: Card(
                        margin: const EdgeInsets.only(bottom: 8.0),
                        clipBehavior: Clip.antiAlias,
                        child: Material(
                          type: MaterialType.transparency,
                          child: ListTile(
                            leading: buildPlaylistLeading(context, historyPlaylist),
                            title: Text(
                              strings.plHistory,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              strings.plTracksCountFormatted(
                                historyPlaylist.trackCount,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_sweep_rounded,
                                    size: 20,
                                  ),
                                  tooltip: strings.srClearHistory,
                                  onPressed: () => playlistsCtrl.clearHistory(),
                                ),
                                const Icon(Icons.chevron_right_rounded),
                              ],
                            ),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => PlaylistDetailScreen(
                                    playlist: historyPlaylist,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),

                  // User Playlists Section Title
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4.0,
                      vertical: 4.0,
                    ),
                    child: Text(
                      '${strings.plTitle} (${userPlaylists.length})',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (userPlaylists.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40.0),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.playlist_play_rounded,
                        size: 48,
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        strings.plNoPlaylists,
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 80.0),
              sliver: SliverFixedExtentList.builder(
                itemExtent: 80.0,
                itemCount: userPlaylists.length,
                itemBuilder: (context, index) {
                  final playlist = userPlaylists[index];
                  return Card(
                    key: ValueKey(playlist.id ?? playlist.name),
                    margin: const EdgeInsets.only(bottom: 8.0),
                    clipBehavior: Clip.antiAlias,
                    child: Material(
                      type: MaterialType.transparency,
                      child: ListTile(
                        leading: buildPlaylistLeading(context, playlist),
                        title: Text(
                          playlist.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          strings.plTracksCountFormatted(playlist.trackCount),
                        ),
                        trailing: PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert_rounded),
                          tooltip: '',
                          onSelected: (value) {
                            if (value == 'rename') {
                              _showRenameDialog(context, playlist);
                            } else if (value == 'delete') {
                              _showDeleteDialog(context, playlist);
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'rename',
                              child: Row(
                                children: [
                                  const Icon(Icons.edit_rounded, size: 20),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      strings.plRename,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
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
                                      strings.plDelete,
                                      style: const TextStyle(
                                        color: Colors.redAccent,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  PlaylistDetailScreen(playlist: playlist),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
