import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../locales/presentation/locale_controller.dart';
import '../../playback/presentation/playback_controller.dart';
import '../../library/domain/playlist.dart';
import '../../library/domain/track.dart';
import 'playlists_controller.dart';

class PlaylistDetailScreen extends StatefulWidget {
  final Playlist playlist;

  const PlaylistDetailScreen({super.key, required this.playlist});

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PlaylistsController>().selectPlaylist(widget.playlist);
    });
  }

  String _formatTotalDuration(List<Track> tracks) {
    final totalMs = tracks.fold<int>(0, (sum, t) => sum + t.durationMs);
    final duration = Duration(milliseconds: totalMs);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  String _formatTrackDuration(int durationMs) {
    final duration = Duration(milliseconds: durationMs);
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleController>().localeStrings;
    final playlists = context.watch<PlaylistsController>();
    final playback = context.watch<PlaybackController>();

    final currentPlaylist = playlists.selectedPlaylist ?? widget.playlist;
    final tracks = playlists.selectedPlaylistTracks;

    return Scaffold(
      appBar: AppBar(
        title: Text(currentPlaylist.name),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                    child: Icon(
                      currentPlaylist.type == PlaylistType.liked
                          ? Icons.favorite_rounded
                          : (currentPlaylist.type == PlaylistType.history
                              ? Icons.history_rounded
                              : Icons.playlist_play_rounded),
                      size: 64,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    currentPlaylist.name,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${strings.plTracksCountFormatted(tracks.length)} • ${_formatTotalDuration(tracks)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilledButton.icon(
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(strings.plPlayAll),
                        onPressed: tracks.isNotEmpty
                            ? () => playback.playAll(tracks, startIndex: 0)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.shuffle_rounded),
                        label: Text(strings.plShuffleAll),
                        onPressed: tracks.isNotEmpty
                            ? () => playback.playAll(tracks, shuffle: true)
                            : null,
                      ),
                    ],
                  ),
                  if (currentPlaylist.type == PlaylistType.user)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        strings.plReorderHint,
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (tracks.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  strings.plEmpty,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            )
          else
            SliverToBoxAdapter(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: tracks.length,
                onReorderItem: (oldIndex, newIndex) {
                  if (currentPlaylist.id != null) {
                    playlists.reorderPlaylistEntries(currentPlaylist.id!, oldIndex, newIndex);
                  }
                },
                itemBuilder: (context, index) {
                  final track = tracks[index];
                  final isPlaying = playback.currentTrack?.uri == track.uri;

                  return ListTile(
                    key: ValueKey('${track.id}_$index'),
                    leading: Icon(
                      isPlaying ? Icons.volume_up_rounded : Icons.music_note_rounded,
                      color: isPlaying ? Theme.of(context).colorScheme.primary : null,
                    ),
                    title: Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isPlaying ? Theme.of(context).colorScheme.primary : null,
                      ),
                    ),
                    subtitle: Text(
                      '${track.artistName} • ${track.albumName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatTrackDuration(track.durationMs),
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (currentPlaylist.type == PlaylistType.user && track.id != null && currentPlaylist.id != null)
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
                            tooltip: strings.plRemoveTrack,
                            onPressed: () {
                              playlists.removeTrackFromPlaylist(currentPlaylist.id!, track.id!);
                            },
                          ),
                        const Icon(Icons.drag_handle_rounded),
                      ],
                    ),
                    onTap: () => playback.playTrack(track, contextTracks: tracks),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
