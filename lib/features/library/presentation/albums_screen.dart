import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/shared/theme/app_theme.dart';
import 'package:tachyon/shared/widgets/album_card.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/search/presentation/search_screen.dart';
import 'package:tachyon/features/search/presentation/tachyon_search_controller.dart';
import 'package:tachyon/shared/widgets/app_icon.dart';

import 'album_detail_screen.dart';
import 'library_controller.dart';

class AlbumsScreen extends StatefulWidget {
  const AlbumsScreen({super.key});

  @override
  State<AlbumsScreen> createState() => _AlbumsScreenState();
}

class _AlbumsScreenState extends State<AlbumsScreen> {
  bool _isCardView = true;

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleController>().localeStrings;
    final library = context.watch<LibraryController>();
    final isDesktop = TachyonBreakpoints.isDesktop(context);

    final albums = library.albums;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [if (!isDesktop) AppIcon(), Text(strings.alTitle)],
        ),
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
            onSelected: (option) => library.setAlbumSortOption(option),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: AlbumSortOption.title,
                child: Row(
                  children: [
                    if (library.albumSortOption == AlbumSortOption.title)
                      Icon(
                        library.albumSortAscending
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 16,
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        strings.alSortTitle,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: AlbumSortOption.artist,
                child: Row(
                  children: [
                    if (library.albumSortOption == AlbumSortOption.artist)
                      Icon(
                        library.albumSortAscending
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 16,
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        strings.alSortArtist,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: AlbumSortOption.year,
                child: Row(
                  children: [
                    if (library.albumSortOption == AlbumSortOption.year)
                      Icon(
                        library.albumSortAscending
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 16,
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        strings.alSortYear,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: AlbumSortOption.trackCount,
                child: Row(
                  children: [
                    if (library.albumSortOption == AlbumSortOption.trackCount)
                      Icon(
                        library.albumSortAscending
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 16,
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        strings.alSortTrackCount,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
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
