import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/library/domain/playlist.dart';
import 'package:tachyon/features/library/domain/track.dart';

import 'package:tachyon/shared/widgets/album_art_image.dart';
import 'package:tachyon/shared/widgets/ambient_backdrop.dart';
import 'package:tachyon/shared/widgets/track_tile.dart';
import 'package:tachyon/shared/theme/app_theme.dart';
import 'package:tachyon/features/playback/presentation/now_playing_screen.dart';
import 'package:tachyon/features/shell/mini_player_bar.dart';

import 'playlist_cover_helper.dart';
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

  Widget _buildHeaderCover(
    BuildContext context,
    Playlist playlist,
    String? coverHash,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    final fallbackWidget = Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Icon(
        playlist.type == PlaylistType.liked
            ? Icons.favorite_rounded
            : (playlist.type == PlaylistType.history
                  ? Icons.history_rounded
                  : Icons.playlist_play_rounded),
        size: 64,
        color: colorScheme.onPrimaryContainer,
      ),
    );

    if (coverHash == null || coverHash.isEmpty) {
      return fallbackWidget;
    }

    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16.0),
          child: SizedBox(
            width: 140,
            height: 140,
            child: AlbumArtImage(
              thumbnailHash: coverHash,
              quality: ThumbnailQuality.high,
              fit: BoxFit.cover,
              fallback: fallbackWidget,
            ),
          ),
        ),
        if (playlist.type == PlaylistType.liked)
          Positioned(
            right: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.favorite_rounded,
                size: 16,
                color: Colors.white,
              ),
            ),
          ),
        if (playlist.type == PlaylistType.history)
          Positioned(
            right: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.history_rounded,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleController>().localeStrings;
    final playlists = context.watch<PlaylistsController>();
    final playback = context.read<PlaybackController>();

    final isSelected = playlists.selectedPlaylist?.id == widget.playlist.id;
    final currentPlaylist = isSelected
        ? playlists.selectedPlaylist!
        : widget.playlist;
    final tracks = isSelected && playlists.selectedPlaylistTracks.isNotEmpty
        ? playlists.selectedPlaylistTracks
        : currentPlaylist.entries
              .map((e) => e.track)
              .whereType<Track>()
              .toList();
    final coverHash = findPlaylistCoverHash(currentPlaylist, tracks);
    final isDesktop = TachyonBreakpoints.isDesktop(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(currentPlaylist.name),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Stack(
        children: [
          Positioned.fill(child: AmbientBackdrop(thumbnailHash: coverHash)),
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(
                  height: MediaQuery.paddingOf(context).top + kToolbarHeight,
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      _buildHeaderCover(context, currentPlaylist, coverHash),
                      const SizedBox(height: 16),
                      Text(
                        currentPlaylist.name,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
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
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton.icon(
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: Text(strings.plPlayAll),
                            onPressed: tracks.isNotEmpty
                                ? () => playback.playAll(tracks, startIndex: 0)
                                : null,
                          ),
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
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              else if (currentPlaylist.type == PlaylistType.user)
                SliverReorderableList(
                  itemCount: tracks.length,
                  onReorderItem: (oldIndex, newIndex) {
                    if (currentPlaylist.id != null) {
                      playlists.reorderPlaylistEntries(
                        currentPlaylist.id!,
                        oldIndex,
                        newIndex,
                      );
                    }
                  },
                  itemBuilder: (context, index) {
                    final track = tracks[index];
                    return TrackTile(
                      key: ValueKey('${track.id ?? track.filePath}_$index'),
                      track: track,
                      contextTracks: tracks,
                      additionalActions: [
                        if (track.id != null && currentPlaylist.id != null)
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(
                              Icons.remove_circle_outline_rounded,
                              size: 20,
                            ),
                            tooltip: strings.plRemoveTrack,
                            onPressed: () {
                              playlists.removeTrackFromPlaylist(
                                currentPlaylist.id!,
                                track.id!,
                              );
                            },
                          ),
                        ReorderableDragStartListener(
                          index: index,
                          child: const Padding(
                            padding: EdgeInsets.only(left: 4.0),
                            child: Icon(Icons.drag_handle_rounded),
                          ),
                        ),
                      ],
                    );
                  },
                )
              else
                SliverList.builder(
                  itemCount: tracks.length,
                  itemBuilder: (context, index) {
                    final track = tracks[index];
                    return TrackTile(
                      key: ValueKey('${track.id ?? track.filePath}_$index'),
                      track: track,
                      contextTracks: tracks,
                    );
                  },
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ],
      ),
      bottomNavigationBar: RepaintBoundary(
        child: MiniPlayerBar(
          isDesktop: isDesktop,
          onTap: () => NowPlayingScreen.open(context),
        ),
      ),
    );
  }
}
