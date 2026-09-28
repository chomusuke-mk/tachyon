import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/shared/widgets/album_art_image.dart';
import 'package:tachyon/shared/widgets/track_tile.dart';
import 'package:tachyon/features/library/presentation/album_detail_screen.dart';
import 'package:tachyon/features/library/presentation/artist_detail_screen.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';

import 'tachyon_search_controller.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleController>().localeStrings;
    final searchCtrl = context.watch<TachyonSearchController>();
    final currentTrackUri = context.select<PlaybackController, String?>(
      (c) => c.currentTrack?.uri,
    );
    final playback = context.read<PlaybackController>();
    final colorScheme = Theme.of(context).colorScheme;

    final matchedTracks = searchCtrl.matchedTracks;
    final matchedAlbums = searchCtrl.matchedAlbums;
    final matchedArtists = searchCtrl.matchedArtists;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _textController,
          autofocus: false,
          decoration: InputDecoration(
            hintText: strings.srHint,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _textController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded),
                    onPressed: () {
                      _textController.clear();
                      searchCtrl.clear();
                    },
                  )
                : null,
          ),
          onChanged: (query) => searchCtrl.onQueryChanged(query),
        ),
      ),
      body: Column(
        children: [
          // Filter Chips Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Row(
              children: [
                FilterChip(
                  label: Text(strings.srFilterAll),
                  selected: searchCtrl.category == SearchFilterCategory.all,
                  onSelected: (_) =>
                      searchCtrl.setCategory(SearchFilterCategory.all),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text(strings.srTracksFound),
                  selected: searchCtrl.category == SearchFilterCategory.tracks,
                  onSelected: (_) =>
                      searchCtrl.setCategory(SearchFilterCategory.tracks),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text(strings.srAlbumsFound),
                  selected: searchCtrl.category == SearchFilterCategory.albums,
                  onSelected: (_) =>
                      searchCtrl.setCategory(SearchFilterCategory.albums),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text(strings.srArtistsFound),
                  selected: searchCtrl.category == SearchFilterCategory.artists,
                  onSelected: (_) =>
                      searchCtrl.setCategory(SearchFilterCategory.artists),
                ),
              ],
            ),
          ),

          if (searchCtrl.isSearching)
            const LinearProgressIndicator(minHeight: 2.0),

          // Main Results Body
          Expanded(
            child: searchCtrl.isEmptyQuery
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_rounded,
                          size: 64,
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.4,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          strings.srTitle,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          strings.srHint,
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  )
                : (!searchCtrl.hasResults && !searchCtrl.isSearching
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_off_rounded,
                                size: 64,
                                color: colorScheme.onSurfaceVariant.withValues(
                                  alpha: 0.4,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                strings.srNoResults,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 32.0,
                                ),
                                child: Text(
                                  strings.srNoResultsDesc,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView(
                          children: [
                            // Tracks category or section in All
                            if ((searchCtrl.category ==
                                        SearchFilterCategory.all ||
                                    searchCtrl.category ==
                                        SearchFilterCategory.tracks) &&
                                matchedTracks.isNotEmpty) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  16,
                                  16,
                                  8,
                                ),
                                child: Text(
                                  strings.srTracksFound,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.primary,
                                      ),
                                ),
                              ),
                              ...matchedTracks.map((track) {
                                final isPlaying =
                                    currentTrackUri == track.uri;
                                return TrackTile(
                                  key: ValueKey('search_${track.uri}'),
                                  track: track,
                                  isPlaying: isPlaying,
                                  onTap: () => playback.playTrack(
                                    track,
                                    contextTracks: matchedTracks,
                                  ),
                                );
                              }),
                            ],

                            // Albums category or section in All
                            if ((searchCtrl.category ==
                                        SearchFilterCategory.all ||
                                    searchCtrl.category ==
                                        SearchFilterCategory.albums) &&
                                matchedAlbums.isNotEmpty) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  16,
                                  16,
                                  8,
                                ),
                                child: Text(
                                  strings.srAlbumsFound,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.primary,
                                      ),
                                ),
                              ),
                              SizedBox(
                                height: 170,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16.0,
                                  ),
                                  itemCount: matchedAlbums.length,
                                  separatorBuilder: (context, index) =>
                                      const SizedBox(width: 12),
                                  itemBuilder: (context, index) {
                                    final album = matchedAlbums[index];
                                    return InkWell(
                                      borderRadius: BorderRadius.circular(10.0),
                                      onTap: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) =>
                                                AlbumDetailScreen(album: album),
                                          ),
                                        );
                                      },
                                      child: SizedBox(
                                        width: 120,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(10.0),
                                              child: const SizedBox(
                                                width: 120,
                                                height: 120,
                                                child: AlbumArtImage(
                                                  uri: '',
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
                                                fontSize: 13,
                                              ),
                                            ),
                                            Text(
                                              album.artistName ?? '',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: colorScheme
                                                    .onSurfaceVariant,
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

                            // Artists category or section in All
                            if ((searchCtrl.category ==
                                        SearchFilterCategory.all ||
                                    searchCtrl.category ==
                                        SearchFilterCategory.artists) &&
                                matchedArtists.isNotEmpty) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  16,
                                  16,
                                  8,
                                ),
                                child: Text(
                                  strings.srArtistsFound,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.primary,
                                      ),
                                ),
                              ),
                              SizedBox(
                                height: 130,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16.0,
                                  ),
                                  itemCount: matchedArtists.length,
                                  separatorBuilder: (context, index) =>
                                      const SizedBox(width: 16),
                                  itemBuilder: (context, index) {
                                    final artist = matchedArtists[index];
                                    return InkWell(
                                      borderRadius: BorderRadius.circular(10.0),
                                      onTap: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) => ArtistDetailScreen(
                                              artist: artist,
                                            ),
                                          ),
                                        );
                                      },
                                      child: SizedBox(
                                        width: 90,
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            CircleAvatar(
                                              radius: 36,
                                              backgroundColor: colorScheme
                                                  .surfaceContainerHighest,
                                              child: Icon(
                                                Icons.person_rounded,
                                                size: 36,
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              artist.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
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
                            const SizedBox(height: 24),
                          ],
                        )),
          ),
        ],
      ),
    );
  }
}
