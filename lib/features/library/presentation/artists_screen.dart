import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/shared/theme/app_theme.dart';
import 'package:tachyon/shared/widgets/app_icon.dart';
import 'package:tachyon/shared/widgets/artist_card.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/search/presentation/search_screen.dart';
import 'package:tachyon/features/search/presentation/tachyon_search_controller.dart';

import 'artist_detail_screen.dart';
import 'library_controller.dart';

class ArtistsScreen extends StatefulWidget {
  const ArtistsScreen({super.key});

  @override
  State<ArtistsScreen> createState() => _ArtistsScreenState();
}

class _ArtistsScreenState extends State<ArtistsScreen> {
  bool _isCardView = true;

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleController>().localeStrings;
    final library = context.watch<LibraryController>();
    final isDesktop = TachyonBreakpoints.isDesktop(context);

    final artists = library.artists;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [if (!isDesktop) AppIcon(), Text(strings.arTitle)],
        ),
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
            onSelected: (option) => library.setArtistSortOption(option),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: ArtistSortOption.name,
                child: Row(
                  children: [
                    if (library.artistSortOption == ArtistSortOption.name)
                      Icon(
                        library.artistSortAscending
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 16,
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        strings.arSortName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: ArtistSortOption.albums,
                child: Row(
                  children: [
                    if (library.artistSortOption == ArtistSortOption.albums)
                      Icon(
                        library.artistSortAscending
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 16,
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        strings.arSortAlbums,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: ArtistSortOption.tracks,
                child: Row(
                  children: [
                    if (library.artistSortOption == ArtistSortOption.tracks)
                      Icon(
                        library.artistSortAscending
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 16,
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        strings.arSortTracks,
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
