import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/shared/widgets/artist_card.dart';
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
  bool _isCardView = true;

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
                    childAspectRatio: 0.8,
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
