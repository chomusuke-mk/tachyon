import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/shared/widgets/album_card.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/library/domain/album.dart';
import 'package:tachyon/features/search/presentation/search_screen.dart';
import 'package:tachyon/features/search/presentation/tachyon_search_controller.dart';

import 'album_detail_screen.dart';
import 'library_controller.dart';

enum AlbumSortOption { title, artist, year, trackCount }

class AlbumsScreen extends StatefulWidget {
  const AlbumsScreen({super.key});

  @override
  State<AlbumsScreen> createState() => _AlbumsScreenState();
}

class _AlbumsScreenState extends State<AlbumsScreen> {
  AlbumSortOption _sortOption = AlbumSortOption.title;
  bool _ascending = true;
  bool _isCardView = true;

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
          cmp = (a.artist?.name ?? '').toLowerCase().compareTo(
            (b.artist?.name ?? '').toLowerCase(),
          );
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
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: strings.srTitle,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SearchScreen(
                    initialCategory: SearchFilterCategory.albums,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: Icon(
              _isCardView
                  ? Icons.view_list_rounded
                  : Icons.grid_view_rounded,
            ),
            tooltip: _isCardView
                ? strings.commonViewAsList
                : strings.commonViewAsCards,
            onPressed: () {
              setState(() {
                _isCardView = !_isCardView;
              });
            },
          ),
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
                    color: Theme.of(context).colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.5),
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
          : _isCardView
              ? GridView.builder(
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
                    return AlbumCard(
                      album: album,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => AlbumDetailScreen(album: album),
                          ),
                        );
                      },
                    );
                  },
                )
              : ListView.builder(
                  itemExtent: 72.0,
                  itemCount: albums.length,
                  itemBuilder: (context, index) {
                    final album = albums[index];
                    return AlbumListTile(
                      album: album,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => AlbumDetailScreen(album: album),
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}
