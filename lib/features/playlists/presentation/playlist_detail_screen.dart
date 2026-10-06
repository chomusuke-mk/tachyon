import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/library/domain/playlist.dart';
import 'package:tachyon/features/library/domain/track.dart';

import 'package:tachyon/shared/widgets/album_art_image.dart';
import 'package:tachyon/shared/widgets/ambient_backdrop.dart';

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

  String _formatTrackDuration(int durationMs) {
    final duration = Duration(milliseconds: durationMs);
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
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

  Widget _buildTrackLeading(BuildContext context, Track track, bool isPlaying) {
    return Stack(
      alignment: Alignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8.0),
          child: SizedBox(
            width: 48,
            height: 48,
            child: AlbumArtImage(
              thumbnailHash: track.thumbnailHash ?? track.album?.thumbnailHash,
              quality: ThumbnailQuality.low,
              fit: BoxFit.cover,
            ),
          ),
        ),
        if (isPlaying)
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: Icon(
              Icons.equalizer_rounded,
              color: Theme.of(context).colorScheme.primary,
              size: 24,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleController>().localeStrings;
    final playlists = context.watch<PlaylistsController>();
    final currentTrack = context.select<PlaybackController, Track?>(
      (c) => c.currentTrack,
    );
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
                    final isPlaying =
                        currentTrack == track || playback.isCurrentTrack(track);

                    final artistNames = track.artists
                        .map((a) => a.name)
                        .join(', ');
                    final albumName = track.album?.name ?? '';
                    final subtitleParts = [
                      if (artistNames.isNotEmpty) artistNames,
                      if (albumName.isNotEmpty) albumName,
                    ];

                    return ListTile(
                      key: ValueKey('${track.id ?? track.filePath}_$index'),
                      leading: _buildTrackLeading(context, track, isPlaying),
                      title: Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isPlaying
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurface,
                            ),
                      ),
                      subtitle: subtitleParts.isNotEmpty
                          ? Text(
                              subtitleParts.join(' • '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            )
                          : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatTrackDuration(track.durationMs),
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                          if (track.id != null && currentPlaylist.id != null)
                            IconButton(
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
                              padding: EdgeInsets.only(left: 8.0),
                              child: Icon(Icons.drag_handle_rounded),
                            ),
                          ),
                        ],
                      ),
                      onTap: () =>
                          playback.playTrack(track, contextTracks: tracks),
                    );
                  },
                )
              else
                SliverList.builder(
                  itemCount: tracks.length,
                  itemBuilder: (context, index) {
                    final track = tracks[index];
                    final isPlaying =
                        currentTrack == track || playback.isCurrentTrack(track);

                    final artistNames = track.artists
                        .map((a) => a.name)
                        .join(', ');
                    final albumName = track.album?.name ?? '';
                    final subtitleParts = [
                      if (artistNames.isNotEmpty) artistNames,
                      if (albumName.isNotEmpty) albumName,
                    ];

                    return ListTile(
                      key: ValueKey('${track.id ?? track.filePath}_$index'),
                      leading: _buildTrackLeading(context, track, isPlaying),
                      title: Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isPlaying
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurface,
                            ),
                      ),
                      subtitle: subtitleParts.isNotEmpty
                          ? Text(
                              subtitleParts.join(' • '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            )
                          : null,
                      trailing: Text(
                        _formatTrackDuration(track.durationMs),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      onTap: () =>
                          playback.playTrack(track, contextTracks: tracks),
                    );
                  },
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ],
      ),
    );
  }
}
