import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/shared/widgets/album_art_image.dart';
import 'package:tachyon/shared/widgets/track_tile.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/library/domain/artist.dart';

import 'album_detail_screen.dart';
import 'library_controller.dart';

class ArtistDetailScreen extends StatelessWidget {
  final Artist artist;

  const ArtistDetailScreen({super.key, required this.artist});

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleController>().localeStrings;
    final library = context.watch<LibraryController>();
    final playback = context.watch<PlaybackController>();

    final artistTracks = library.allTracks
        .where(
          (t) =>
              (artist.id != null && t.artistId == artist.id) ||
              t.artist == artist.name,
        )
        .toList();

    final artistAlbums = library.albums
        .where(
          (a) =>
              (artist.id != null && a.artistId == artist.id) ||
              a.artistName == artist.name,
        )
        .toList();

    final firstUri = artistTracks.isNotEmpty ? artistTracks.first.uri : '';

    return Scaffold(
      appBar: AppBar(title: Text(artist.name)),
      body: CustomScrollView(
        slivers: [
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
                    child: firstUri.isNotEmpty
                        ? ClipOval(
                            child: SizedBox(
                              width: 128,
                              height: 128,
                              child: AlbumArtImage(
                                uri: firstUri,
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilledButton.icon(
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(strings.arPlayAll),
                        onPressed: artistTracks.isNotEmpty
                            ? () =>
                                  playback.playAll(artistTracks, startIndex: 0)
                            : null,
                      ),
                      const SizedBox(width: 12),
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
                          final albumTrack = library.allTracks
                              .where(
                                (t) =>
                                    (album.id != null &&
                                        t.albumId == album.id) ||
                                    t.album == album.name,
                              )
                              .firstOrNull;
                          final coverUri = albumTrack?.uri ?? '';

                          return InkWell(
                            borderRadius: BorderRadius.circular(8.0),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      AlbumDetailScreen(album: album),
                                ),
                              );
                            },
                            child: SizedBox(
                              width: 110,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8.0),
                                    child: SizedBox(
                                      width: 110,
                                      height: 110,
                                      child: AlbumArtImage(
                                        uri: coverUri,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    album.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (album.year != null)
                                    Text(
                                      album.year.toString(),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outline,
                                      ),
                                    ),
                                ],
                              ),
                            ),
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
              final isPlaying = playback.currentTrack?.uri == track.uri;

              return TrackTile(
                key: ValueKey(track.uri),
                track: track,
                isPlaying: isPlaying,
                onTap: () =>
                    playback.playTrack(track, contextTracks: artistTracks),
              );
            }, childCount: artistTracks.length),
          ),
        ],
      ),
    );
  }
}
