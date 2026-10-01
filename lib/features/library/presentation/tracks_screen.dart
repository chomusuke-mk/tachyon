import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/shared/widgets/track_tile.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/playlists/presentation/playlists_controller.dart';
import 'package:tachyon/features/library/domain/album.dart';
import 'package:tachyon/features/library/domain/artist.dart';
import 'package:tachyon/features/library/domain/track.dart';

import 'album_detail_screen.dart';
import 'artist_detail_screen.dart';
import 'library_controller.dart';

class TracksScreen extends StatefulWidget {
  const TracksScreen({super.key});

  @override
  State<TracksScreen> createState() => _TracksScreenState();
}

class _TracksScreenState extends State<TracksScreen> {
  bool _isSelectionMode = false;
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

  void _showFileInfoDialog(BuildContext context, Track track) {
    final strings = context.read<LocaleController>().localeStrings;
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(track.title),
          content: SingleChildScrollView(
            child: ListBody(
              children: [
                _infoRow(strings.trFilePath, track.filePath),
                if (track.artist != null)
                  _infoRow(strings.trSortArtist, track.artist!),
                if (track.album != null)
                  _infoRow(strings.trSortAlbum, track.album!),
                if (track.codec != null)
                  _infoRow(strings.trCodec, track.codec!.toUpperCase()),
                if (track.bitrate != null)
                  _infoRow(strings.npBitrate, '${track.bitrate! ~/ 1000} kbps'),
                if (track.sampleRate != null)
                  _infoRow(strings.npSampleRate, '${track.sampleRate} Hz'),
                if (track.channels != null)
                  _infoRow(strings.npChannels, track.channels.toString()),
                if (track.year != null)
                  _infoRow(strings.alReleaseYear, track.year.toString()),
                _infoRow(
                  strings.trSortDuration,
                  '${(track.durationMs / 1000).toStringAsFixed(1)} s',
                ),
                _infoRow(
                  strings.trFileSize,
                  '${(track.fileSize / (1024 * 1024)).toStringAsFixed(2)} MB',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(strings.clClose),
            ),
          ],
        );
      },
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          SelectableText(value, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  void _showAddToPlaylistDialog(BuildContext context, Track track) {
    final strings = context.read<LocaleController>().localeStrings;
    final playlistsCtrl = context.read<PlaylistsController>();
    final playlists = playlistsCtrl.userPlaylists;

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(strings.trAddPlaylist),
          content: playlists.isEmpty
              ? Text(strings.plEmpty)
              : SizedBox(
                  width: 300,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: playlists.length,
                    itemBuilder: (context, index) {
                      final pl = playlists[index];
                      return ListTile(
                        leading: const Icon(Icons.playlist_add_rounded),
                        title: Text(pl.name),
                        onTap: () {
                          if (track.id != null && pl.id != null) {
                            playlistsCtrl.addTrackToPlaylist(pl.id!, track.id!);
                          }
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                strings.trAddedToPlaylistFormatted(pl.name),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(strings.selCancel),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteConfirmation(BuildContext context, Track track) {
    final strings = context.read<LocaleController>().localeStrings;
    final libraryCtrl = context.read<LibraryController>();
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(strings.trDelete),
          content: Text(strings.trDeleteConfirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(strings.selCancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () {
                libraryCtrl.deleteTrack(track);
                Navigator.of(context).pop();
              },
              child: Text(strings.trDelete),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleController>().localeStrings;
    final library = context.watch<LibraryController>();
    final currentTrackFilePath = context.select<PlaybackController, String?>(
      (c) => c.currentTrack?.filePath,
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
                      Text(strings.trSortTitle),
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
                      Text(strings.trSortArtist),
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
                      Text(strings.trSortAlbum),
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
                      Text(strings.trSortDuration),
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
                      Text(strings.trSortDateAdded),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      body: tracks.isEmpty
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
          : ListView.builder(
              itemExtent: 72.0,
              itemCount: tracks.length,
              itemBuilder: (context, index) {
                final track = tracks[index];
                final isPlaying = currentTrackFilePath == track.filePath;
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
                  onActionSelected: (action) {
                    switch (action) {
                      case TrackAction.play:
                        playback.playTrack(track, contextTracks: tracks);
                        break;
                      case TrackAction.playNext:
                        playback.playNext(track);
                        break;
                      case TrackAction.addToQueue:
                        playback.addToQueue(track);
                        break;
                      case TrackAction.addToPlaylist:
                        _showAddToPlaylistDialog(context, track);
                        break;
                      case TrackAction.viewAlbum:
                        final album =
                            library.albums
                                .where(
                                  (a) =>
                                      a.id == track.albumId ||
                                      a.name == track.album,
                                )
                                .firstOrNull ??
                            Album(
                              id: track.albumId,
                              name: track.album ?? 'Unknown Album',
                              artistName: track.artistName,
                            );
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => AlbumDetailScreen(album: album),
                          ),
                        );
                        break;
                      case TrackAction.viewArtist:
                        final artist =
                            library.artists
                                .where(
                                  (a) =>
                                      a.id == track.artistId ||
                                      a.name == track.artist,
                                )
                                .firstOrNull ??
                            Artist(
                              id: track.artistId,
                              name: track.artist ?? 'Unknown Artist',
                            );
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ArtistDetailScreen(artist: artist),
                          ),
                        );
                        break;
                      case TrackAction.fileInfo:
                        _showFileInfoDialog(context, track);
                        break;
                      case TrackAction.delete:
                        _showDeleteConfirmation(context, track);
                        break;
                    }
                  },
                );
              },
            ),
    );
  }
}
