import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/shared/theme/app_theme.dart';
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
                            final effectiveLocale = context
                                .read<LocaleController>()
                                .currentLocaleCode;
                            final resolvedName =
                                languagesEndonyms[effectiveLocale] ??
                                effectiveLocale;
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
                              subtitle: Text(resolvedName),
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

  void _showAppLanguageDialog(
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
            final query = searchQuery.toLowerCase().trim();
            final filteredEntries = languagesEndonyms.entries.where((e) {
              if (query.isEmpty) return true;
              return e.key.toLowerCase().contains(query) ||
                  e.value.toLowerCase().contains(query);
            }).toList();

            return AlertDialog(
              title: Text(strings.sLanguage),
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
                                settings.appLanguage == 'defaultOption';
                            final effectiveLocale = context
                                .read<LocaleController>()
                                .currentLocaleCode;
                            final resolvedName =
                                languagesEndonyms[effectiveLocale] ??
                                effectiveLocale;
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
                              subtitle: Text(resolvedName),
                              trailing: isSelected
                                  ? Icon(
                                      Icons.check_rounded,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                    )
                                  : null,
                              onTap: () {
                                settings.setAppLanguage('defaultOption');
                                Navigator.of(dialogCtx).pop();
                              },
                            );
                          }

                          final item =
                              filteredEntries[searchQuery.isEmpty
                                  ? index - 1
                                  : index];
                          final isSelected = settings.appLanguage == item.key;

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
                              settings.setAppLanguage(item.key);
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
    final localeController = context.watch<LocaleController>();
    final strings = localeController.localeStrings;
    final currentLocale = localeController.currentLocaleCode;
    final settings = context.watch<SettingsController>();
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(strings.sTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Section: Music Folders
          _buildSectionHeader(context, strings.sMusicFolders),
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.35),
              ),
            ),
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
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(
                            alpha: 0.35,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: colorScheme.outlineVariant.withValues(
                              alpha: 0.25,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.folder_rounded,
                              color: colorScheme.primary,
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                dir,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            IconButton(
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
                          ],
                        ),
                      );
                    }),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    alignment: WrapAlignment.start,
                    children: [
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.add_rounded),
                        label: Text(strings.sAddFolder),
                        onPressed: () => _showAddFolderDialog(context),
                      ),
                      FilledButton.icon(
                        icon: const Icon(Icons.sync_rounded),
                        label: Text(strings.sRescanLibrary),
                        onPressed: () {
                          context.read<LibraryController>().startScan(
                            settings.musicDirectories,
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Section: Audio Playback
          _buildSectionHeader(context, strings.sAudioSection),
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.35),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
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
                      onChanged: (val) =>
                          settings.setCrossfadeDuration(val.round()),
                    ),
                  ),
                  const Divider(),
                  SettingRow(
                    title: strings.sCrossfadeCurve,
                    description: strings.sCrossfadeCurveDesc,
                    type: ControllerType.complex,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: SegmentedButton<CrossfadeCurve>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment<CrossfadeCurve>(
                            value: CrossfadeCurve.equalPower,
                            label: Text(
                              strings.sCrossfadeCurveEqualPower,
                              textAlign: TextAlign.center,
                            ),
                          ),
                          ButtonSegment<CrossfadeCurve>(
                            value: CrossfadeCurve.linear,
                            label: Text(
                              strings.sCrossfadeCurveLinear,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                        selected: {settings.crossfadeCurve},
                        onSelectionChanged: (newSelection) =>
                            settings.setCrossfadeCurve(newSelection.first),
                      ),
                    ),
                  ),
                  const Divider(),
                  SettingRow(
                    title: strings.sGaplessPlayback,
                    description: strings.sGaplessPlaybackDesc,
                    type: ControllerType.switchCtrl,
                    child: Switch(value: true, onChanged: null),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Section: Appearance
          _buildSectionHeader(context, strings.sAppearanceSection),
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.35),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  SettingRow(
                    title: strings.sThemeMode,
                    description: strings.sThemeModeDesc,
                    type: ControllerType.complex,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final showLabels = constraints.maxWidth >= 360;
                          return SegmentedButton<ThemeMode>(
                            showSelectedIcon: false,
                            segments: [
                              ButtonSegment<ThemeMode>(
                                value: ThemeMode.system,
                                icon: const Icon(
                                  Icons.brightness_auto_rounded,
                                  size: 18,
                                ),
                                label: showLabels
                                    ? Text(strings.sThemeSystem)
                                    : null,
                                tooltip: showLabels
                                    ? null
                                    : strings.sThemeSystem,
                              ),
                              ButtonSegment<ThemeMode>(
                                value: ThemeMode.light,
                                icon: const Icon(
                                  Icons.light_mode_rounded,
                                  size: 18,
                                ),
                                label: showLabels
                                    ? Text(strings.sThemeLight)
                                    : null,
                                tooltip: showLabels
                                    ? null
                                    : strings.sThemeLight,
                              ),
                              ButtonSegment<ThemeMode>(
                                value: ThemeMode.dark,
                                icon: const Icon(
                                  Icons.dark_mode_rounded,
                                  size: 18,
                                ),
                                label: showLabels
                                    ? Text(strings.sThemeDark)
                                    : null,
                                tooltip: showLabels ? null : strings.sThemeDark,
                              ),
                            ],
                            selected: {settings.themeMode},
                            onSelectionChanged: (newSelection) {
                              settings.setThemeMode(newSelection.first);
                            },
                          );
                        },
                      ),
                    ),
                  ),
                  const Divider(),
                  SettingRow(
                    title: strings.sThemeOled,
                    description: strings.sThemeOledDesc,
                    type: ControllerType.switchCtrl,
                    child: Switch(
                      value: settings.isOledMode,
                      onChanged: settings.themeMode == ThemeMode.light
                          ? null
                          : (val) => settings.setIsOledMode(val),
                    ),
                  ),
                  const Divider(),
                  SettingRow(
                    title: strings.sAccentColor,
                    description: strings.sAccentColorDesc,
                    type: ControllerType.complex,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10.0),
                      child: Wrap(
                        key: const Key('accent_colors_wrap'),
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final color
                              in TachyonColors.predefinedAccentColors)
                            _buildColorCircle(
                              context: context,
                              color: color,
                              isSelected:
                                  settings.accentColorValue == color.toARGB32(),
                              onTap: () =>
                                  settings.setAccentColor(color.toARGB32()),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(),
                  SettingRow(
                    title: strings.sCustomBackground,
                    description: strings.sCustomBackgroundDesc,
                    type: ControllerType.complex,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (settings.customBackgroundPath == null) ...[
                            FilledButton.tonalIcon(
                              icon: const Icon(Icons.image_outlined),
                              label: Text(strings.sSelectBackgroundImage),
                              onPressed: () async {
                                final picked =
                                    await FilePickerService.pickImage(
                                      dialogTitle:
                                          strings.sSelectBackgroundImage,
                                    );
                                if (picked != null) {
                                  final success = await settings
                                      .setCustomBackground(picked);
                                  if (!success && context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          strings.sCustomBackgroundFileError,
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                            ),
                          ] else ...[
                            Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: colorScheme.outlineVariant
                                            .withValues(alpha: 0.5),
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Image.file(
                                      File(settings.customBackgroundPath!),
                                      width: 52,
                                      height: 52,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => const Icon(
                                        Icons.broken_image_rounded,
                                        size: 32,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                FilledButton.tonalIcon(
                                  icon: const Icon(
                                    Icons.photo_library_outlined,
                                  ),
                                  label: Text(strings.sChangeBackgroundImage),
                                  onPressed: () async {
                                    final picked =
                                        await FilePickerService.pickImage(
                                          dialogTitle:
                                              strings.sChangeBackgroundImage,
                                        );
                                    if (picked != null) {
                                      await settings.setCustomBackground(
                                        picked,
                                      );
                                    }
                                  },
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                  ),
                                  tooltip: strings.sRemoveBackgroundImage,
                                  color: colorScheme.error,
                                  onPressed: () =>
                                      settings.setCustomBackground(null),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (settings.customBackgroundPath != null) ...[
                    const Divider(),
                    SettingRow(
                      title: strings.sBackgroundBlur,
                      description: '${settings.backgroundBlurSigma.round()} px',
                      type: ControllerType.slider,
                      child: Slider(
                        value: settings.backgroundBlurSigma,
                        min: 0.0,
                        max: 50.0,
                        divisions: 50,
                        label: '${settings.backgroundBlurSigma.round()} px',
                        onChanged: (val) =>
                            settings.setBackgroundBlurSigma(val),
                      ),
                    ),
                    const Divider(),
                    SettingRow(
                      title: strings.sBackgroundDim,
                      description:
                          '${(settings.backgroundDimOpacity * 100).round()}%',
                      type: ControllerType.slider,
                      child: Slider(
                        value: settings.backgroundDimOpacity,
                        min: 0.20,
                        max: 0.95,
                        divisions: 15,
                        label:
                            '${(settings.backgroundDimOpacity * 100).round()}%',
                        onChanged: (val) =>
                            settings.setBackgroundDimOpacity(val),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Section: Language
          _buildSectionHeader(context, strings.sLanguageSection),
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.35),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  SettingRow(
                    title: strings.sLanguage,
                    description: strings.sLanguageDesc,
                    type: ControllerType.dropdown,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () =>
                          _showAppLanguageDialog(context, settings, strings),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(
                            alpha: 0.45,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: colorScheme.outlineVariant.withValues(
                              alpha: 0.35,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                (settings.appLanguage == 'defaultOption')
                                    ? '${strings.sTranslationLangDefault} (${languagesEndonyms[currentLocale] ?? currentLocale})'
                                    : (languagesEndonyms[settings
                                              .appLanguage] ??
                                          settings.appLanguage),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_drop_down_rounded),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Divider(),
                  SettingRow(
                    title: strings.sTranslationTargetLang,
                    description: strings.sTranslationTargetLangDesc,
                    type: ControllerType.dropdown,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _showTranslationLanguageDialog(
                        context,
                        settings,
                        strings,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(
                            alpha: 0.45,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: colorScheme.outlineVariant.withValues(
                              alpha: 0.35,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                settings.lyricsTranslationTargetLang ==
                                        'defaultOption'
                                    ? '${strings.sTranslationLangDefault} (${languagesEndonyms[currentLocale] ?? currentLocale})'
                                    : (languagesEndonyms[settings
                                              .lyricsTranslationTargetLang] ??
                                          settings.lyricsTranslationTargetLang),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down_rounded),
                          ],
                        ),
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
            elevation: 0,
            color: colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.35),
              ),
            ),
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

  Widget _buildColorCircle({
    required BuildContext context,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final isLightColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.light;
    final checkColor = isLightColor ? Colors.black : Colors.white;

    return Semantics(
      button: true,
      selected: isSelected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.onSurface
                  : Colors.transparent,
              width: isSelected ? 2.5 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: isSelected
              ? Center(
                  child: Icon(Icons.check_rounded, size: 20, color: checkColor),
                )
              : null,
        ),
      ),
    );
  }
}
