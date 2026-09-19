import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/widgets/album_art_image.dart';
import '../../locales/presentation/locale_controller.dart';
import '../domain/album.dart';
import 'album_detail_screen.dart';
import 'library_controller.dart';

enum AlbumSortOption {
  title,
  artist,
  year,
  trackCount,
}

class AlbumsScreen extends StatefulWidget {
  const AlbumsScreen({super.key});

  @override
  State<AlbumsScreen> createState() => _AlbumsScreenState();
}

class _AlbumsScreenState extends State<AlbumsScreen> {
  AlbumSortOption _sortOption = AlbumSortOption.title;
  bool _ascending = true;

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleController>().localeStrings;
    final library = context.watch<LibraryController>();

    final albums = List<Album>.from(library.albums);
    albums.sort((a, b) {
      int cmp;
      switch (_sortOption) {
        case AlbumSortOption.title:
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          break;
        case AlbumSortOption.artist:
          cmp = (a.artistName ?? '').toLowerCase().compareTo((b.artistName ?? '').toLowerCase());
          break;
        case AlbumSortOption.year:
          cmp = (a.year ?? 0).compareTo(b.year ?? 0);
          break;
        case AlbumSortOption.trackCount:
          cmp = a.trackCount.compareTo(b.trackCount);
          break;
      }
      return _ascending ? cmp : -cmp;
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.alTitle),
        actions: [
          PopupMenuButton<AlbumSortOption>(
            icon: const Icon(Icons.sort_rounded),
            tooltip: strings.alSort,
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
                value: AlbumSortOption.title,
                child: Text(strings.alSortTitle),
              ),
              PopupMenuItem(
                value: AlbumSortOption.artist,
                child: Text(strings.alSortArtist),
              ),
              PopupMenuItem(
                value: AlbumSortOption.year,
                child: Text(strings.alSortYear),
              ),
              PopupMenuItem(
                value: AlbumSortOption.trackCount,
                child: Text(strings.alSortTrackCount),
              ),
            ],
          ),
        ],
      ),
      body: albums.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.album_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    strings.alNoAlbums,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    strings.alNoAlbumsDesc,
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
                maxCrossAxisExtent: 220,
                childAspectRatio: 0.72,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: albums.length,
              itemBuilder: (context, index) {
                final album = albums[index];
                // Find a track from this album to get a cover URI
                final albumTrack = library.allTracks
                    .where((t) => (album.id != null && t.albumId == album.id) || t.album == album.name)
                    .firstOrNull;
                final coverUri = albumTrack?.uri ?? '';

                return InkWell(
                  borderRadius: BorderRadius.circular(12.0),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AlbumDetailScreen(album: album),
                      ),
                    );
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12.0),
                          child: AspectRatio(
                            aspectRatio: 1.0,
                            child: AlbumArtImage(
                              uri: coverUri,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        album.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        album.artistName ?? 'Unknown Artist',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        strings.alTracksCountFormatted(album.trackCount),
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
