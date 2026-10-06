import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/features/library/domain/genre.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/playback/presentation/now_playing_screen.dart';
import 'package:tachyon/features/shell/mini_player_bar.dart';
import 'package:tachyon/shared/theme/app_theme.dart';
import 'package:tachyon/shared/widgets/album_art_image.dart';
import 'package:tachyon/shared/widgets/ambient_backdrop.dart';
import 'package:tachyon/shared/widgets/track_tile.dart';

/// Finds the cover thumbnail hash for a genre by picking the first available
/// thumbnail hash among its internal tracks or albums (fastest/easiest access).
String? findGenreCoverHash(Genre genre) {
  for (final track in genre.tracks) {
    final hash = track.thumbnailHash ?? track.album?.thumbnailHash;
    if (hash != null && hash.trim().isNotEmpty) {
      return hash.trim();
    }
  }
  return null;
}

class GenreDetailScreen extends StatelessWidget {
  final Genre genre;

  const GenreDetailScreen({super.key, required this.genre});

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
    final currentTrack = context.select<PlaybackController, Track?>(
      (c) => c.currentTrack,
    );
    final playback = context.read<PlaybackController>();

    final currentGenre = (genre.id != null && library != null
            ? library.store.getGenreById(genre.id!)
            : null) ??
        genre;
    final genreTracks = currentGenre.tracks;
    final coverHash = findGenreCoverHash(currentGenre);
    final isDesktop = TachyonBreakpoints.isDesktop(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(currentGenre.name),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.play_arrow_rounded),
            tooltip: strings.gPlayAll,
            onPressed: genreTracks.isNotEmpty
                ? () => playback.playAll(genreTracks, startIndex: 0)
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.shuffle_rounded),
            tooltip: strings.gShuffleAll,
            onPressed: genreTracks.isNotEmpty
                ? () => playback.playAll(genreTracks, shuffle: true)
                : null,
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: AmbientBackdrop(thumbnailHash: coverHash),
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
                            thumbnailHash: coverHash,
                            quality: ThumbnailQuality.high,
                            fit: BoxFit.cover,
                            fallback: Container(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHigh,
                              child: Center(
                                child: Icon(
                                  Icons.category_rounded,
                                  size: 80,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        currentGenre.name,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${strings.gTracksCountFormatted(genreTracks.length)} • ${_formatTotalDuration(genreTracks)}',
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
                            label: Text(strings.gPlayAll),
                            onPressed: genreTracks.isNotEmpty
                                ? () => playback.playAll(
                                    genreTracks,
                                    startIndex: 0,
                                  )
                                : null,
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.shuffle_rounded),
                            label: Text(strings.gShuffleAll),
                            onPressed: genreTracks.isNotEmpty
                                ? () => playback.playAll(
                                    genreTracks,
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
              if (genreTracks.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      strings.gNoGenresDesc,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              else
                SliverList.builder(
                  itemCount: genreTracks.length,
                  itemBuilder: (context, index) {
                    final track = genreTracks[index];
                    final isPlaying =
                        currentTrack == track || playback.isCurrentTrack(track);

                    return TrackTile(
                      key: ValueKey(track.filePath),
                      track: track,
                      isPlaying: isPlaying,
                      onTap: () => playback.playTrack(
                        track,
                        contextTracks: genreTracks,
                      ),
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
