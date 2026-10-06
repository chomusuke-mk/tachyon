import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/core/constants/app_defaults.dart';
import 'package:tachyon/core/constants/languages.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';
import 'package:tachyon/features/locales/domain/locale.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/shared/utils/file_picker_service.dart';
import 'package:tachyon/shared/widgets/setting_row.dart';

import 'settings_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _showAddFolderDialog(BuildContext context) {
    final controller = TextEditingController();
    final settings = context.read<SettingsController>();
    final strings = context.read<LocaleController>().localeStrings;

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: Text(strings.sAddFolderTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: strings.sFolderPathHint,
                  labelText: strings.sFolderPathLabel,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.folder_open_rounded),
                    tooltip: strings.sBrowseFolder,
                    onPressed: () async {
                      final picked = await FilePickerService.pickDirectory(
                        dialogTitle: strings.sAddFolderTitle,
                      );
                      if (picked != null) {
                        controller.text = picked;
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.folder_open_rounded),
                label: Text(strings.sBrowseFolder),
                onPressed: () async {
                  final picked = await FilePickerService.pickDirectory(
                    dialogTitle: strings.sAddFolderTitle,
                  );
                  if (picked != null) {
                    controller.text = picked;
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text(strings.sCancel),
            ),
            FilledButton(
              onPressed: () async {
                final path = controller.text.trim();
                if (path.isNotEmpty) {
                  final added = await settings.addMusicDirectory(path);
                  if (dialogCtx.mounted) {
                    Navigator.of(dialogCtx).pop();
                    if (!added && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(strings.sFolderErrorInvalid)),
                      );
                    } else if (added && context.mounted) {
                      context.read<LibraryController>().startScan(
                        settings.musicDirectories,
                      );
                    }
                  }
                }
              },
              child: Text(strings.sAdd),
            ),
          ],
        );
      },
    );
  }

  void _showTranslationLanguageDialog(
    BuildContext context,
    SettingsController settings,
    AppStringKey strings,
  ) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filteredEntries = languagesEndonyms.entries.where((e) {
              final query = searchQuery.toLowerCase().trim();
              if (query.isEmpty) return true;
              return e.key.toLowerCase().contains(query) ||
                  e.value.toLowerCase().contains(query);
            }).toList();

            return AlertDialog(
              title: Text(strings.sTranslationTargetLang),
              content: SizedBox(
                width: 400,
                height: 450,
                child: Column(
                  children: [
                    TextField(
                      autofocus: false,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded),
                        hintText: strings.srHint,
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (val) {
                        setDialogState(() {
                          searchQuery = val;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: searchQuery.isEmpty
                            ? filteredEntries.length + 1
                            : filteredEntries.length,
                        itemBuilder: (context, index) {
                          if (searchQuery.isEmpty && index == 0) {
                            final isSelected =
                                settings.lyricsTranslationTargetLang ==
                                'defaultOption';
                            return ListTile(
                              leading: Icon(
                                Icons.auto_awesome_rounded,
                                color: isSelected
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                              title: Text(
                                strings.sTranslationLangDefault,
                                style: TextStyle(
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              trailing: isSelected
                                  ? Icon(
                                      Icons.check_rounded,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                    )
                                  : null,
                              onTap: () {
                                settings.setLyricsTranslationTargetLang(
                                  'defaultOption',
                                );
                                Navigator.of(dialogCtx).pop();
                              },
                            );
                          }

                          final item =
                              filteredEntries[searchQuery.isEmpty
                                  ? index - 1
                                  : index];
                          final isSelected =
                              settings.lyricsTranslationTargetLang == item.key;

                          return ListTile(
                            title: Text(
                              item.value,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            subtitle: Text(item.key),
                            trailing: isSelected
                                ? Icon(
                                    Icons.check_rounded,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                  )
                                : null,
                            onTap: () {
                              settings.setLyricsTranslationTargetLang(item.key);
                              Navigator.of(dialogCtx).pop();
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: Text(strings.sCancel),
                ),
              ],
            );
          },
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
    final progress = library.scanProgress;
    final scanPercentage = progress.progressValue != null
        ? (progress.progressValue! * 100).toInt()
        : null;

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
                        strings.sNoFoldersYet,
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
                            settings.removeMusicDirectory(dir);
                            context.read<LibraryController>().startScan(
                              settings.musicDirectories,
                            );
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
                              ? (scanPercentage != null
                                    ? strings.sScanningProgressFormatted(
                                        scanPercentage,
                                      )
                                    : (strings
                                              .scanStageText(progress.stage)
                                              .isNotEmpty
                                          ? strings.scanStageText(
                                              progress.stage,
                                            )
                                          : strings.sRescanLibrary))
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
                    LinearProgressIndicator(value: progress.progressValue),
                    const SizedBox(height: 6),
                    Text(
                      '${strings.scanStageText(progress.stage)}${progress.progressLabel != null ? ' ${progress.progressLabel}' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
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
                      value: settings.crossfadeDuration.toDouble().clamp(
                        AppDefaults.crossfadeMinDuration.toDouble(),
                        AppDefaults.crossfadeMaxDuration.toDouble(),
                      ),
                      min: AppDefaults.crossfadeMinDuration.toDouble(),
                      max: AppDefaults.crossfadeMaxDuration.toDouble(),
                      divisions:
                          AppDefaults.crossfadeMaxDuration -
                          AppDefaults.crossfadeMinDuration,
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
                      value:
                          (settings.appLanguage == 'en' ||
                              settings.appLanguage == 'es')
                          ? settings.appLanguage
                          : 'default',
                      items: [
                        DropdownMenuItem(
                          value: 'default',
                          child: Text(strings.sTranslationLangDefault),
                        ),
                        const DropdownMenuItem(
                          value: 'en',
                          child: Text('English'),
                        ),
                        const DropdownMenuItem(
                          value: 'es',
                          child: Text('Español'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) settings.setAppLanguage(val);
                      },
                    ),
                  ),
                  const Divider(),
                  SettingRow(
                    title: strings.sTranslationTargetLang,
                    description: strings.sTranslationTargetLangDesc,
                    type: ControllerType.dropdown,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                      ),
                      onPressed: () => _showTranslationLanguageDialog(
                        context,
                        settings,
                        strings,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              settings.lyricsTranslationTargetLang ==
                                      'defaultOption'
                                  ? strings.sTranslationLangDefault
                                  : (languagesEndonyms[settings
                                            .lyricsTranslationTargetLang] ??
                                        settings.lyricsTranslationTargetLang),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down_rounded),
                        ],
                      ),
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
