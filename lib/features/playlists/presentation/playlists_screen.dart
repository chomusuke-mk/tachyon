import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../locales/presentation/locale_controller.dart';
import '../../library/domain/playlist.dart';
import 'playlist_detail_screen.dart';
import 'playlists_controller.dart';

class PlaylistsScreen extends StatelessWidget {
  const PlaylistsScreen({super.key});

  void _showCreateDialog(BuildContext context) {
    final strings = context.read<LocaleController>().localeStrings;
    final controller = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(strings.plCreateNew),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: strings.plNewNameHint,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(strings.plCancelButton),
            ),
            FilledButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  context.read<PlaylistsController>().createPlaylist(name);
                }
                Navigator.of(context).pop();
              },
              child: Text(strings.plCreateButton),
            ),
          ],
        );
      },
    );
  }

  void _showRenameDialog(BuildContext context, Playlist playlist) {
    final controller = TextEditingController(text: playlist.name);

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename Playlist'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Enter playlist name',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isNotEmpty && playlist.id != null) {
                  context.read<PlaylistsController>().renamePlaylist(playlist.id!, name);
                }
                Navigator.of(context).pop();
              },
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );
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
                  context.read<PlaylistsController>().deletePlaylist(playlist.id!);
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
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_rounded),
        label: Text(strings.plCreateNew),
        onPressed: () => _showCreateDialog(context),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Special Playlists: Liked Songs & History
          if (likedPlaylist != null)
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: colorScheme.primary,
                  child: const Icon(Icons.favorite_rounded, color: Colors.white),
                ),
                title: Text(
                  strings.plLikedSongs,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(strings.plTracksCountFormatted(likedPlaylist.trackCount)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PlaylistDetailScreen(playlist: likedPlaylist),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
          if (historyPlaylist != null)
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  child: Icon(Icons.history_rounded, color: colorScheme.onSurfaceVariant),
                ),
                title: Text(
                  strings.plHistory,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(strings.plTracksCountFormatted(historyPlaylist.trackCount)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.delete_sweep_rounded, size: 20),
                      tooltip: 'Clear History',
                      onPressed: () => playlistsCtrl.clearHistory(),
                    ),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PlaylistDetailScreen(playlist: historyPlaylist),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),

          // User Playlists Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
            child: Text(
              'Your Playlists (${userPlaylists.length})',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          if (userPlaylists.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32.0),
              child: Center(
                child: Text(
                  strings.plNoPlaylists,
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ),
            )
          else
            ...userPlaylists.map((playlist) {
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: colorScheme.secondaryContainer,
                    child: Icon(Icons.playlist_play_rounded, color: colorScheme.onSecondaryContainer),
                  ),
                  title: Text(
                    playlist.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(strings.plTracksCountFormatted(playlist.trackCount)),
                  trailing: PopupMenuButton<String>(
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
                            Text(strings.plRename),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.redAccent),
                            const SizedBox(width: 12),
                            Text(strings.plDelete, style: const TextStyle(color: Colors.redAccent)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PlaylistDetailScreen(playlist: playlist),
                      ),
                    );
                  },
                ),
              );
            }),
        ],
      ),
    );
  }
}
