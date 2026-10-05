import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/shared/widgets/album_art_image.dart';
import 'package:tachyon/shared/widgets/album_card.dart';
import 'package:tachyon/shared/widgets/ambient_backdrop.dart';
import 'package:tachyon/shared/widgets/track_tile.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/library/domain/artist.dart';
import 'package:tachyon/features/library/domain/thumbnail_quality.dart';
import 'package:tachyon/features/library/domain/track.dart';

import 'album_detail_screen.dart';
import 'library_controller.dart';

class ArtistDetailScreen extends StatelessWidget {
  final Artist artist;

  const ArtistDetailScreen({super.key, required this.artist});

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleController>().localeStrings;
    final library = context.watch<LibraryController>();
    final currentTrack = context.select<PlaybackController, Track?>(
      (c) => c.currentTrack,
    );
    final playback = context.read<PlaybackController>();

    final currentArtist = (artist.id != null
            ? library.store.getArtistById(artist.id!)
            : null) ??
        artist;
    final artistTracks = currentArtist.tracks;
    final artistAlbums = currentArtist.albums;

    final firstFilePath =
        artistTracks.firstOrNull?.filePath ?? '';

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(artist.name),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: AmbientBackdrop(
              filePath: firstFilePath,
              artistName: artist.name,
            ),
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
                  CircleAvatar(
                    radius: 64,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .primaryContainer,
                    child: firstFilePath.isNotEmpty
                        ? ClipOval(
                            child: SizedBox(
                              width: 128,
                              height: 128,
                              child: AlbumArtImage(
                                filePath: firstFilePath,
                                artistName: artist.name,
                                quality: ThumbnailQuality.high,
                                fit: BoxFit.cover,
                              ),
                            ),
                          )
                        : Icon(
                            Icons.person_rounded,
                            size: 64,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    artist.name,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${strings.arAlbumsCountFormatted(artistAlbums.length)} • ${strings.arTracksCountFormatted(artistTracks.length)}',
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
                        label: Text(strings.arPlayAll),
                        onPressed: artistTracks.isNotEmpty
                            ? () =>
                                  playback.playAll(artistTracks, startIndex: 0)
                            : null,
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.shuffle_rounded),
                        label: Text(strings.arShuffleAll),
                        onPressed: artistTracks.isNotEmpty
                            ? () =>
                                  playback.playAll(artistTracks, shuffle: true)
                            : null,
                      ),
                    ],
                  ),
                  if (artistAlbums.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        strings.arDiscography,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 160,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: artistAlbums.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final album = artistAlbums[index];
                          return AlbumCard(
                            album: album,
                            width: 110,
                            subtitle: album.year?.toString(),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      AlbumDetailScreen(album: album),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      strings.arAllTracks,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final track = artistTracks[index];
              final isPlaying = currentTrack == track;

              return TrackTile(
                key: ValueKey(track.filePath),
                track: track,
                isPlaying: isPlaying,
                onTap: () =>
                    playback.playTrack(track, contextTracks: artistTracks),
              );
            }, childCount: artistTracks.length),
          ),
        ],
      ),
        ],
      ),
);
  }
}
