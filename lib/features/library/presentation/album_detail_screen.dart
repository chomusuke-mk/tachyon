import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/shared/widgets/album_art_image.dart';
import 'package:tachyon/shared/widgets/track_tile.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/library/domain/album.dart';
import 'package:tachyon/features/library/domain/track.dart';

import 'library_controller.dart';

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
    final library = context.watch<LibraryController>();
    final currentTrackUri = context.select<PlaybackController, String?>(
      (c) => c.currentTrack?.uri,
    );
    final playback = context.read<PlaybackController>();

    final albumTracks =
        library.allTracks
            .where(
              (t) =>
                  (album.id != null && t.albumId == album.id) ||
                  t.album == album.name,
            )
            .toList()
          ..sort((a, b) {
            final discCmp = (a.discNumber ?? 1).compareTo(b.discNumber ?? 1);
            if (discCmp != 0) return discCmp;
            return (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0);
          });

    final firstUri = albumTracks.isNotEmpty ? albumTracks.first.uri : '';

    return Scaffold(
      appBar: AppBar(title: Text(album.name)),
      body: CustomScrollView(
        slivers: [
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
                      child: AlbumArtImage(uri: firstUri, fit: BoxFit.cover),
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
                    album.artistName ?? 'Unknown Artist',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilledButton.icon(
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(strings.alPlayAll),
                        onPressed: albumTracks.isNotEmpty
                            ? () => playback.playAll(albumTracks, startIndex: 0)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.shuffle_rounded),
                        label: Text(strings.alShuffleAll),
                        onPressed: albumTracks.isNotEmpty
                            ? () => playback.playAll(albumTracks, shuffle: true)
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final track = albumTracks[index];
              final isPlaying = currentTrackUri == track.uri;

              return TrackTile(
                key: ValueKey(track.uri),
                track: track,
                isPlaying: isPlaying,
                onTap: () =>
                    playback.playTrack(track, contextTracks: albumTracks),
              );
            }, childCount: albumTracks.length),
          ),
        ],
      ),
    );
  }
}
