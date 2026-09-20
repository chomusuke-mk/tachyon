import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';

import 'package:tachyon/core/services/cover_cache_service.dart';
import 'package:tachyon/shared/widgets/setting_row.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';

import 'settings_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _showAddFolderDialog(BuildContext context) {
    final controller = TextEditingController();
    final settings = context.read<SettingsController>();

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Music Folder'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: '/path/to/music',
              labelText: 'Directory Path',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final path = controller.text.trim();
                if (path.isNotEmpty) {
                  final added = await settings.addMusicDirectory(path);
                  if (context.mounted) {
                    Navigator.of(context).pop();
                    if (!added) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Directory does not exist or is already added',
                          ),
                        ),
                      );
                    }
                  }
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  void _showClearCacheConfirmation(BuildContext context) {
    final strings = context.read<LocaleController>().localeStrings;
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(strings.sClearCache),
          content: Text(strings.sClearCacheDesc),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () async {
                CoverCacheService? cache;
                try {
                  cache = context.read<CoverCacheService?>();
                } catch (_) {
                  cache = null;
                }
                if (cache != null) {
                  await cache.clearCache();
                }
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Cover cache cleared successfully'),
                    ),
                  );
                }
              },
              child: const Text('Clear'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleController>().localeStrings;
    final settings = context.watch<SettingsController>();
    final library = context.watch<LibraryController>();
    final colorScheme = Theme.of(context).colorScheme;

    final isScanning = library.isScanning;
    final scanPercentage = (library.scanProgress.progress * 100).toInt();

    return Scaffold(
      appBar: AppBar(title: Text(strings.sTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Section: Music Folders
          _buildSectionHeader(context, strings.sMusicFolders),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.sMusicFoldersDesc,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (settings.musicDirectories.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(
                        'No music folders added yet.',
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: colorScheme.outline,
                        ),
                      ),
                    )
                  else
                    ...settings.musicDirectories.map((dir) {
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.folder_rounded),
                        title: Text(
                          dir,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 20,
                          ),
                          tooltip: strings.sRemoveFolder,
                          onPressed: () {
                            context
                                .read<LibraryController>()
                                .deleteTracksInFolder(dir);
                            settings.removeMusicDirectory(dir);
                          },
                        ),
                      );
                    }),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 10,
                    alignment: WrapAlignment.start,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.add_rounded),
                        label: Text(strings.sAddFolder),
                        onPressed: () => _showAddFolderDialog(context),
                      ),
                      FilledButton.icon(
                        icon: isScanning
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.sync_rounded),
                        label: Text(
                          isScanning
                              ? strings.sScanningProgressFormatted(
                                  scanPercentage,
                                )
                              : strings.sRescanLibrary,
                        ),
                        onPressed: isScanning
                            ? () => library.cancelScan()
                            : () =>
                                  library.startScan(settings.musicDirectories),
                      ),
                    ],
                  ),
                  if (isScanning) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: library.scanProgress.progress,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Section: Audio Playback
          _buildSectionHeader(context, strings.sAudioSection),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  SettingRow(
                    title: strings.sCrossfadeEnable,
                    description: strings.sCrossfadeEnableDesc,
                    type: ControllerType.switchCtrl,
                    child: Switch(
                      value: settings.crossfadeEnabled,
                      onChanged: (val) => settings.setCrossfadeEnabled(val),
                    ),
                  ),
                  const Divider(),
                  SettingRow(
                    title: strings.sCrossfadeDuration,
                    description: '${settings.crossfadeDuration}s',
                    type: ControllerType.slider,
                    child: Slider(
                      value: settings.crossfadeDuration.toDouble(),
                      min: 2.0,
                      max: 30.0,
                      divisions: 28,
                      label: '${settings.crossfadeDuration}s',
                      onChanged: settings.crossfadeEnabled
                          ? (val) => settings.setCrossfadeDuration(val.round())
                          : null,
                    ),
                  ),
                  const Divider(),
                  SettingRow(
                    title: strings.sCrossfadeCurve,
                    description: strings.sCrossfadeCurveDesc,
                    type: ControllerType.dropdown,
                    child: DropdownButton<CrossfadeCurve>(
                      isExpanded: true,
                      value: settings.crossfadeCurve,
                      items: [
                        DropdownMenuItem(
                          value: CrossfadeCurve.equalPower,
                          child: Text(strings.sCrossfadeCurveEqualPower),
                        ),
                        DropdownMenuItem(
                          value: CrossfadeCurve.linear,
                          child: Text(strings.sCrossfadeCurveLinear),
                        ),
                      ],
                      onChanged: settings.crossfadeEnabled
                          ? (val) {
                              if (val != null) settings.setCrossfadeCurve(val);
                            }
                          : null,
                    ),
                  ),
                  const Divider(),
                  SettingRow(
                    title: strings.sGaplessPlayback,
                    description: strings.sGaplessPlaybackDesc,
                    type: ControllerType.switchCtrl,
                    child: Switch(
                      value: true,
                      onChanged:
                          null, // Gapless is always active in Tachyon engine
                    ),
                  ),
                  const Divider(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Section: Appearance
          _buildSectionHeader(context, strings.sAppearanceSection),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  SettingRow(
                    title: strings.sThemeMode,
                    description: strings.sThemeModeDesc,
                    type: ControllerType.dropdown,
                    child: DropdownButton<ThemeMode>(
                      isExpanded: true,
                      value: settings.themeMode,
                      items: [
                        DropdownMenuItem(
                          value: ThemeMode.system,
                          child: Text(strings.sThemeSystem),
                        ),
                        DropdownMenuItem(
                          value: ThemeMode.light,
                          child: Text(strings.sThemeLight),
                        ),
                        DropdownMenuItem(
                          value: ThemeMode.dark,
                          child: Text(strings.sThemeDark),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) settings.setThemeMode(val);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Section: Language
          _buildSectionHeader(context, strings.sLanguageSection),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  SettingRow(
                    title: strings.sLanguage,
                    description: strings.sLanguageDesc,
                    type: ControllerType.dropdown,
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: settings.appLanguage == 'es' ? 'es' : 'en',
                      items: const [
                        DropdownMenuItem(value: 'en', child: Text('English')),
                        DropdownMenuItem(value: 'es', child: Text('Español')),
                      ],
                      onChanged: (val) {
                        if (val != null) settings.setAppLanguage(val);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Section: About & Maintenance
          _buildSectionHeader(context, strings.sAboutSection),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(strings.sAppVersion),
                    trailing: const Text(
                      '0.1.0',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(strings.sClearCache),
                    subtitle: Text(strings.sClearCacheDesc),
                    trailing: OutlinedButton(
                      onPressed: () => _showClearCacheConfirmation(context),
                      child: const Text('Clear'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
