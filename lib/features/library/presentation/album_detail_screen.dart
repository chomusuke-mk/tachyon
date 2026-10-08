import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/shared/widgets/album_art_image.dart';
import 'package:tachyon/shared/widgets/ambient_backdrop.dart';
import 'package:tachyon/shared/widgets/track_tile.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/library/domain/album.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';
import 'package:tachyon/features/playback/presentation/now_playing_screen.dart';
import 'package:tachyon/features/shell/mini_player_bar.dart';
import 'package:tachyon/shared/theme/app_theme.dart';

class AlbumDetailScreen extends StatelessWidget {
  final Album album;

  const AlbumDetailScreen({super.key, required this.album});

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

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleController>().localeStrings;
    final library = context.watch<LibraryController?>();
    final playback = context.read<PlaybackController>();

    final currentAlbum = (album.id != null && library != null
            ? library.store.getAlbumById(album.id!)
            : null) ??
        album;
    final albumTracks = currentAlbum.tracks;

    final isDesktop = TachyonBreakpoints.isDesktop(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(album.name),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: AmbientBackdrop(thumbnailHash: album.thumbnailHash),
          ),
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
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16.0),
                        child: SizedBox(
                          width: 200,
                          height: 200,
                          child: AlbumArtImage(
                            thumbnailHash: album.thumbnailHash,
                            quality: ThumbnailQuality.high,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        album.name,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        album.artist?.name ?? strings.trUnknownArtist,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${album.year ?? ''} • ${strings.alTracksCountFormatted(albumTracks.length)} • ${_formatTotalDuration(albumTracks)}',
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
                            label: Text(strings.alPlayAll),
                            onPressed: albumTracks.isNotEmpty
                                ? () => playback.playAll(
                                    albumTracks,
                                    startIndex: 0,
                                  )
                                : null,
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.shuffle_rounded),
                            label: Text(strings.alShuffleAll),
                            onPressed: albumTracks.isNotEmpty
                                ? () => playback.playAll(
                                    albumTracks,
                                    shuffle: true,
                                  )
                                : null,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SliverList.builder(
                itemCount: albumTracks.length,
                itemBuilder: (context, index) {
                  final track = albumTracks[index];
                  return TrackTile(
                    key: ValueKey(track.filePath),
                    track: track,
                    contextTracks: albumTracks,
                    allowedActions: const {
                      TrackAction.play,
                      TrackAction.playNext,
                      TrackAction.addToQueue,
                      TrackAction.addToPlaylist,
                      TrackAction.viewArtist,
                      TrackAction.fileInfo,
                    },
                  );
                },
              ),
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
