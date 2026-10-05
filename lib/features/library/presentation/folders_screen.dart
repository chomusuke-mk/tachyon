import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:tachyon/shared/widgets/track_tile.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';

import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/shared/utils/file_picker_service.dart';

import 'library_controller.dart';

class FoldersScreen extends StatelessWidget {
  const FoldersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleController>().localeStrings;
    final library = context.watch<LibraryController>();
    final currentTrack = context.select<PlaybackController, Track?>(
      (c) => c.currentTrack,
    );
    final playback = context.read<PlaybackController>();
    final settings = context.watch<SettingsController>();

    final currentFolder = library.currentFolderPath;
    final musicDirs = settings.musicDirectories;

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.fTitle),
        actions: [
          if (currentFolder != null) ...[
            IconButton(
              icon: const Icon(Icons.arrow_upward_rounded),
              tooltip: strings.fNavigateUp,
              onPressed: library.navigateUpFolder,
            ),
            IconButton(
              icon: const Icon(Icons.sync_rounded),
              tooltip: strings.fScanFolder,
              onPressed: () => library.startScan([currentFolder]),
            ),
          ],
        ],
      ),
      body: currentFolder == null
          ? (musicDirs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.folder_off_rounded,
                          size: 64,
                          color: Theme.of(context).colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          strings.fEmptyFolder,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          strings.sBrowseFoldersDesc,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          icon: const Icon(Icons.add_rounded),
                          label: Text(strings.sAddFolder),
                          onPressed: () async {
                            final picked = await FilePickerService.pickDirectory(
                              dialogTitle: strings.sAddFolderTitle,
                            );
                            if (picked != null) {
                              final added = await settings.addMusicDirectory(picked);
                              if (context.mounted && !added) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(strings.sFolderErrorInvalid)),
                                );
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: musicDirs.length,
                    itemBuilder: (context, index) {
                      final dirPath = musicDirs[index];
                      return ListTile(
                        leading: const Icon(Icons.folder_special_rounded),
                        title: Text(p.basename(dirPath)),
                        subtitle: Text(dirPath),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => library.navigateToFolder(dirPath),
                      );
                    },
                  ))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Breadcrumbs header
                Container(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        InkWell(
                          onTap: () => library.navigateToFolder(
                            musicDirs.firstOrNull ?? currentFolder,
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.home_rounded, size: 18),
                              const SizedBox(width: 4),
                              Text(
                                strings.fBreadcrumbRoot,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.chevron_right_rounded, size: 16),
                            ],
                          ),
                        ),
                        Text(
                          currentFolder,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),

                // Folder items: subdirectories then audio tracks
                Expanded(
                  child: ListView(
                    children: [
                      ...library.currentFolderSubdirectories.map((subDir) {
                        return ListTile(
                          leading: const Icon(
                            Icons.folder_rounded,
                            color: Colors.amber,
                          ),
                          title: Text(p.basename(subDir)),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => library.navigateToFolder(subDir),
                        );
                      }),
                      ...library.currentFolderTracks.map((track) {
                        final isPlaying = currentTrack == track;
                        return TrackTile(
                          key: ValueKey(track.filePath),
                          track: track,
                          isPlaying: isPlaying,
                          onTap: () => playback.playTrack(
                            track,
                            contextTracks: library.currentFolderTracks,
                          ),
                        );
                      }),
                      if (library.currentFolderSubdirectories.isEmpty &&
                          library.currentFolderTracks.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Center(
                            child: Text(
                              strings.fEmptyFolder,
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
