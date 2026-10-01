import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/shared/widgets/track_tile.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/library/domain/genre.dart';

import 'library_controller.dart';

class GenresScreen extends StatefulWidget {
  const GenresScreen({super.key});

  @override
  State<GenresScreen> createState() => _GenresScreenState();
}

class _GenresScreenState extends State<GenresScreen> {
  Genre? _selectedGenre;

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleController>().localeStrings;
    final library = context.watch<LibraryController>();
    final currentTrackFilePath = context.select<PlaybackController, String?>(
      (c) => c.currentTrack?.filePath,
    );
    final playback = context.read<PlaybackController>();

    if (_selectedGenre != null) {
      final target = _selectedGenre!.name.toLowerCase();
      final genreTracks = library.allTracks
          .where((t) => t.genres.any((g) => g.toLowerCase() == target))
          .toList();

      return Scaffold(
        appBar: AppBar(
          title: Text(_selectedGenre!.name),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => setState(() => _selectedGenre = null),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.play_arrow_rounded),
              tooltip: strings.gPlayAll,
              onPressed: genreTracks.isNotEmpty
                  ? () => playback.playAll(genreTracks, startIndex: 0)
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.shuffle_rounded),
              tooltip: strings.gShuffleAll,
              onPressed: genreTracks.isNotEmpty
                  ? () => playback.playAll(genreTracks, shuffle: true)
                  : null,
            ),
          ],
        ),
        body: ListView.builder(
          itemExtent: 72.0,
          itemCount: genreTracks.length,
          itemBuilder: (context, index) {
            final track = genreTracks[index];
            final isPlaying = currentTrackFilePath == track.filePath;

            return TrackTile(
              key: ValueKey(track.filePath),
              track: track,
              isPlaying: isPlaying,
              onTap: () =>
                  playback.playTrack(track, contextTracks: genreTracks),
            );
          },
        ),
      );
    }

    final genres = library.genres;

    return Scaffold(
      appBar: AppBar(title: Text(strings.gTitle)),
      body: genres.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.category_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    strings.gNoGenres,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    strings.gNoGenresDesc,
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
                maxCrossAxisExtent: 200,
                childAspectRatio: 1.4,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: genres.length,
              itemBuilder: (context, index) {
                final genre = genres[index];
                final colorScheme = Theme.of(context).colorScheme;

                return Card(
                  color: colorScheme.surfaceContainer,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12.0),
                    onTap: () => setState(() => _selectedGenre = genre),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.music_note_rounded,
                            color: colorScheme.primary,
                          ),
                          const Spacer(),
                          Text(
                            genre.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            strings.gTracksCountFormatted(genre.trackCount),
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
