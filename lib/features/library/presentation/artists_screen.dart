import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/shared/widgets/artist_card.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/library/domain/artist.dart';
import 'package:tachyon/features/search/presentation/search_screen.dart';
import 'package:tachyon/features/search/presentation/tachyon_search_controller.dart';

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
  bool _isCardView = true;

  List<Artist>? _lastSourceArtists;
  ArtistSortOption? _lastSortOption;
  bool? _lastAscending;
  List<Artist> _cachedArtists = const [];

  List<Artist> _getSortedArtists(List<Artist> source) {
    if (identical(source, _lastSourceArtists) &&
        _sortOption == _lastSortOption &&
        _ascending == _lastAscending) {
      return _cachedArtists;
    }
    final artists = List<Artist>.of(source, growable: false);
    if (artists.length > 1) {
      switch (_sortOption) {
        case ArtistSortOption.name:
          final keys = <Artist, String>{
            for (final a in artists) a: a.name.toLowerCase(),
          };
          artists.sort((a, b) {
            final cmp = keys[a]!.compareTo(keys[b]!);
            return _ascending ? cmp : -cmp;
          });
          break;
        case ArtistSortOption.albums:
          artists.sort((a, b) {
            final cmp = a.albumCount.compareTo(b.albumCount);
            return _ascending ? cmp : -cmp;
          });
          break;
        case ArtistSortOption.tracks:
          artists.sort((a, b) {
            final cmp = a.trackCount.compareTo(b.trackCount);
            return _ascending ? cmp : -cmp;
          });
          break;
      }
    }
    _lastSourceArtists = source;
    _lastSortOption = _sortOption;
    _lastAscending = _ascending;
    _cachedArtists = artists;
    return artists;
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleController>().localeStrings;
    final library = context.watch<LibraryController>();

    final artists = _getSortedArtists(library.artists);

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.arTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: strings.srTitle,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SearchScreen(
                    initialCategory: SearchFilterCategory.artists,
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
          : _isCardView
              ? GridView.builder(
                  padding: const EdgeInsets.all(16.0),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                childAspectRatio: 0.78,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: artists.length,
                  itemBuilder: (context, index) {
                    final artist = artists[index];
                    return ArtistCard(
                      artist: artist,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ArtistDetailScreen(artist: artist),
                          ),
                        );
                      },
                    );
                  },
                )
              : ListView.builder(
                  itemExtent: 72.0,
                  itemCount: artists.length,
                  itemBuilder: (context, index) {
                    final artist = artists[index];
                    return ArtistListTile(
                      artist: artist,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ArtistDetailScreen(artist: artist),
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}
