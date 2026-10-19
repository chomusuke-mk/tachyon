import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/shared/theme/app_theme.dart';
import 'package:tachyon/shared/widgets/album_card.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/core/store/domain/album.dart';
import 'package:tachyon/features/search/presentation/search_screen.dart';
import 'package:tachyon/features/search/presentation/tachyon_search_controller.dart';
import 'package:tachyon/shared/widgets/app_icon.dart';

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

  List<Album>? _lastSourceAlbums;
  AlbumSortOption? _lastSortOption;
  bool? _lastAscending;
  List<Album> _cachedAlbums = const [];

  List<Album> _getSortedAlbums(List<Album> source) {
    if (identical(source, _lastSourceAlbums) &&
        _sortOption == _lastSortOption &&
        _ascending == _lastAscending) {
      return _cachedAlbums;
    }
    final albums = List<Album>.of(source, growable: false);
    if (albums.length > 1) {
      switch (_sortOption) {
        case AlbumSortOption.title:
          final keys = <Album, String>{
            for (final a in albums) a: a.name.toLowerCase(),
          };
          albums.sort((a, b) {
            final cmp = keys[a]!.compareTo(keys[b]!);
            return _ascending ? cmp : -cmp;
          });
          break;
        case AlbumSortOption.artist:
          final keys = <Album, String>{
            for (final a in albums) a: (a.artist?.name ?? '').toLowerCase(),
          };
          albums.sort((a, b) {
            final cmp = keys[a]!.compareTo(keys[b]!);
            return _ascending ? cmp : -cmp;
          });
          break;
        case AlbumSortOption.year:
          albums.sort((a, b) {
            final cmp = (a.year ?? 0).compareTo(b.year ?? 0);
            return _ascending ? cmp : -cmp;
          });
          break;
        case AlbumSortOption.trackCount:
          albums.sort((a, b) {
            final cmp = a.trackCount.compareTo(b.trackCount);
            return _ascending ? cmp : -cmp;
          });
          break;
      }
    }
    _lastSourceAlbums = source;
    _lastSortOption = _sortOption;
    _lastAscending = _ascending;
    _cachedAlbums = albums;
    return albums;
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleController>().localeStrings;
    final library = context.watch<LibraryController>();
    final isDesktop = TachyonBreakpoints.isDesktop(context);

    final albums = _getSortedAlbums(library.albums);

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
