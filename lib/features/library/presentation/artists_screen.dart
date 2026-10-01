import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/shared/widgets/album_art_image.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/library/domain/artist.dart';

import 'artist_detail_screen.dart';
import 'library_controller.dart';

enum ArtistSortOption { name, albums, tracks }

class ArtistsScreen extends StatefulWidget {
  const ArtistsScreen({super.key});

  @override
  State<ArtistsScreen> createState() => _ArtistsScreenState();
}

class _ArtistsScreenState extends State<ArtistsScreen> {
  ArtistSortOption _sortOption = ArtistSortOption.name;
  bool _ascending = true;

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleController>().localeStrings;
    final library = context.watch<LibraryController>();

    final artists = List<Artist>.from(library.artists);
    artists.sort((a, b) {
      int cmp;
      switch (_sortOption) {
        case ArtistSortOption.name:
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          break;
        case ArtistSortOption.albums:
          cmp = a.albumCount.compareTo(b.albumCount);
          break;
        case ArtistSortOption.tracks:
          cmp = a.trackCount.compareTo(b.trackCount);
          break;
      }
      return _ascending ? cmp : -cmp;
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.arTitle),
        actions: [
          PopupMenuButton<ArtistSortOption>(
            icon: const Icon(Icons.sort_rounded),
            tooltip: strings.arSort,
            onSelected: (option) {
              setState(() {
                if (_sortOption == option) {
                  _ascending = !_ascending;
                } else {
                  _sortOption = option;
                  _ascending = true;
                }
              });
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: ArtistSortOption.name,
                child: Text(strings.arSortName),
              ),
              PopupMenuItem(
                value: ArtistSortOption.albums,
                child: Text(strings.arSortAlbums),
              ),
              PopupMenuItem(
                value: ArtistSortOption.tracks,
                child: Text(strings.arSortTracks),
              ),
            ],
          ),
        ],
      ),
      body: artists.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.person_outline_rounded,
                    size: 64,
                    color: Theme.of(context).colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    strings.arNoArtists,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    strings.arNoArtistsDesc,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(16.0),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                childAspectRatio: 0.8,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: artists.length,
              itemBuilder: (context, index) {
                final artist = artists[index];
                final artistTrack = library.allTracks
                    .where(
                      (t) =>
                          (artist.id != null && t.artistId == artist.id) ||
                          t.artist == artist.name,
                    )
                    .firstOrNull;
                final coverFilePath = artistTrack?.filePath ?? '';

                return InkWell(
                  borderRadius: BorderRadius.circular(12.0),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ArtistDetailScreen(artist: artist),
                      ),
                    );
                  },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 54,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: coverFilePath.isNotEmpty
                            ? ClipOval(
                                child: SizedBox(
                                  width: 108,
                                  height: 108,
                                  child: AlbumArtImage(
                                    filePath: coverFilePath,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              )
                            : Icon(
                                Icons.person_rounded,
                                size: 48,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        artist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${strings.arAlbumsCountFormatted(artist.albumCount)} • ${strings.arTracksCountFormatted(artist.trackCount)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
