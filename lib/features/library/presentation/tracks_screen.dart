import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/shared/widgets/album_art_image.dart';
import 'package:tachyon/shared/widgets/track_tile.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/playlists/presentation/playlists_controller.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/search/presentation/search_screen.dart';
import 'package:tachyon/features/search/presentation/tachyon_search_controller.dart';

import 'library_controller.dart';

class TracksScreen extends StatefulWidget {
  const TracksScreen({super.key});

  @override
  State<TracksScreen> createState() => _TracksScreenState();
}

class _TracksScreenState extends State<TracksScreen> {
  bool _isSelectionMode = false;
  bool _isCardView = false;
  final Set<int> _selectedTrackIds = <int>{};

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedTrackIds.clear();
      }
    });
  }

  void _toggleTrackSelection(int trackId) {
    setState(() {
      if (_selectedTrackIds.contains(trackId)) {
        _selectedTrackIds.remove(trackId);
        if (_selectedTrackIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedTrackIds.add(trackId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleController>().localeStrings;
    final library = context.watch<LibraryController>();
    final currentTrack = context.select<PlaybackController, Track?>(
      (c) => c.currentTrack,
    );
    final playback = context.read<PlaybackController>();
    final playlists = context.watch<PlaylistsController>();

    final tracks = library.tracks;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isSelectionMode
              ? strings.selSelectedCountFormatted(_selectedTrackIds.length)
              : strings.trTitle,
        ),
        actions: [
          if (_isSelectionMode) ...[
            TextButton(
              onPressed: () {
                final selectedTracks = tracks
                    .where(
                      (t) => t.id != null && _selectedTrackIds.contains(t.id!),
                    )
                    .toList();
                if (selectedTracks.isNotEmpty) {
                  playback.playAll(selectedTracks);
                }
                _toggleSelectionMode();
              },
              child: Text(strings.npPlay),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: strings.selCancel,
              onPressed: _toggleSelectionMode,
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.search_rounded),
              tooltip: strings.srTitle,
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SearchScreen(
                      initialCategory: SearchFilterCategory.tracks,
                    ),
                  ),
                );
              },
            ),
            IconButton(
              icon: Icon(
                _isCardView ? Icons.view_list_rounded : Icons.grid_view_rounded,
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
            IconButton(
              icon: const Icon(Icons.checklist_rounded),
              tooltip: strings.selSelect,
              onPressed: _toggleSelectionMode,
            ),
            PopupMenuButton<TrackSortOption>(
              icon: const Icon(Icons.sort_rounded),
              tooltip: strings.trSort,
              onSelected: (option) => library.setSortOption(option),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: TrackSortOption.title,
                  child: Row(
                    children: [
                      if (library.sortOption == TrackSortOption.title)
                        Icon(
                          library.sortAscending
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                          size: 16,
                        ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          strings.trSortTitle,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: TrackSortOption.artist,
                  child: Row(
                    children: [
                      if (library.sortOption == TrackSortOption.artist)
                        Icon(
                          library.sortAscending
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                          size: 16,
                        ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          strings.trSortArtist,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: TrackSortOption.album,
                  child: Row(
                    children: [
                      if (library.sortOption == TrackSortOption.album)
                        Icon(
                          library.sortAscending
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                          size: 16,
                        ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          strings.trSortAlbum,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: TrackSortOption.duration,
                  child: Row(
                    children: [
                      if (library.sortOption == TrackSortOption.duration)
                        Icon(
                          library.sortAscending
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                          size: 16,
                        ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          strings.trSortDuration,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: TrackSortOption.dateAdded,
                  child: Row(
                    children: [
                      if (library.sortOption == TrackSortOption.dateAdded)
                        Icon(
                          library.sortAscending
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                          size: 16,
                        ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          strings.trSortDateAdded,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      body: ((library.isLoading || library.isScanning) && tracks.isEmpty)
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      strings.trLoadingTracks,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    const SizedBox(
                      width: 200,
                      child: LinearProgressIndicator(
                        key: Key('tracks_loading_indicator'),
                        borderRadius: BorderRadius.all(Radius.circular(4)),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : tracks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  Icon(
                    Icons.music_off_rounded,
                    size: 64,
                    color: Theme.of(context).colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    strings.trNoTracks,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0),
                    child: Text(
                      strings.trNoTracksDesc,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : _isCardView
          ? GridView.builder(
              padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 80.0),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                childAspectRatio: 0.72,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: tracks.length,
              itemBuilder: (context, index) {
                final track = tracks[index];
                final isPlaying =
                    currentTrack == track || playback.isCurrentTrack(track);
                final isSelected =
                    track.id != null && _selectedTrackIds.contains(track.id!);

                return Material(
                  type: MaterialType.transparency,
                  borderRadius: BorderRadius.circular(12.0),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12.0),
                  onTap: () {
                    if (_isSelectionMode && track.id != null) {
                      _toggleTrackSelection(track.id!);
                    } else {
                      playback.playTrack(track, contextTracks: tracks);
                    }
                  },
                  onLongPress: () {
                    if (!_isSelectionMode && track.id != null) {
                      _toggleSelectionMode();
                      _toggleTrackSelection(track.id!);
                    }
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12.0),
                              child: AspectRatio(
                                aspectRatio: 1.0,
                                child: AlbumArtImage(
                                  thumbnailHash:
                                      track.thumbnailHash ??
                                      track.album?.thumbnailHash,
                                  quality: ThumbnailQuality.medium,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            if (isPlaying)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.all(4.0),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primaryContainer,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.graphic_eq_rounded,
                                    size: 16,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer,
                                  ),
                                ),
                              ),
                            if (_isSelectionMode)
                              Positioned(
                                top: 8,
                                left: 8,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context).colorScheme.surface
                                              .withValues(alpha: 0.8),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isSelected
                                        ? Icons.check_circle_rounded
                                        : Icons.radio_button_unchecked_rounded,
                                    size: 24,
                                    color: isSelected
                                        ? Theme.of(context)
                                              .colorScheme
                                              .onPrimary
                                        : Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: isPlaying
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        track.artists.isNotEmpty
                            ? track.artists.map((a) => a.name).join(', ')
                            : strings.trUnknownArtist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              );
              },
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 80.0),
              itemExtent: 72.0,
              scrollCacheExtent: const ScrollCacheExtent.pixels(720.0),
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: true,
              itemCount: tracks.length,
              itemBuilder: (context, index) {
                final track = tracks[index];
                final isPlaying =
                    currentTrack == track || playback.isCurrentTrack(track);
                final isLiked =
                    track.id != null && playlists.isTrackLiked(track.id!);
                final isSelected =
                    track.id != null && _selectedTrackIds.contains(track.id!);

                return TrackTile(
                  key: ValueKey(track.filePath),
                  track: track,
                  isPlaying: isPlaying,
                  isSelected: isSelected,
                  isSelectionMode: _isSelectionMode,
                  isLiked: isLiked,
                  onTap: () {
                    if (_isSelectionMode && track.id != null) {
                      _toggleTrackSelection(track.id!);
                    } else {
                      playback.playTrack(track, contextTracks: tracks);
                    }
                  },
                  onLongPress: () {
                    if (!_isSelectionMode && track.id != null) {
                      _toggleSelectionMode();
                      _toggleTrackSelection(track.id!);
                    }
                  },
                  onSelectChanged: (val) {
                    if (track.id != null) {
                      _toggleTrackSelection(track.id!);
                    }
                  },
                  onToggleLike: () => playlists.toggleLikeTrack(track),
                  onActionSelected: (action) => _handleTrackAction(
                    context,
                    track,
                    tracks,
                    action,
                    playback,
                  ),
                );
              },
            ),
      floatingActionButton: (tracks.isNotEmpty && !_isSelectionMode)
          ? FloatingActionButton(
              tooltip: strings.trShuffleAll,
              onPressed: () => playback.playAll(tracks, shuffle: true),
              child: const Icon(Icons.shuffle_rounded),
            )
          : null,
    );
  }

  void _handleTrackAction(
    BuildContext context,
    Track track,
    List<Track> tracks,
    TrackAction action,
    PlaybackController playback,
  ) {
    TrackActionHelper.handleTrackAction(
      context,
      track,
      action,
      contextTracks: tracks,
      enableDelete: true,
    );
  }
}
