import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:tachyon/core/constants/languages.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/lyrics_controller.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';

enum LyricsDialogTab { sources, translation }

/// Modal dialog for configuring active lyrics sources (Local, lrclib.net, lyrics.ovh)
/// and lyrics translation (source language, target language).
class LyricsSourcesDialog extends StatefulWidget {
  const LyricsSourcesDialog({super.key});

  /// Displays the [LyricsSourcesDialog] as an adaptive Material 3 dialog.
  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => const LyricsSourcesDialog(),
    );
  }

  @override
  State<LyricsSourcesDialog> createState() => _LyricsSourcesDialogState();
}

class _LyricsSourcesDialogState extends State<LyricsSourcesDialog> {
  LyricsDialogTab _selectedTab = LyricsDialogTab.sources;
  late bool _enableLocal;
  late bool _enableLrclib;
  late bool _enableLyricsOvh;

  @override
  void initState() {
    super.initState();
    final controller = context.read<LyricsController>();
    _enableLocal = controller.enableLocalSources;
    _enableLrclib = controller.enableLrclib;
    _enableLyricsOvh = controller.enableLyricsOvh;
  }

  void _updateLocal(bool value) {
    // Invariant: At least one source must remain enabled
    if (!value && !_enableLrclib && !_enableLyricsOvh) return;
    setState(() => _enableLocal = value);
    context.read<LyricsController>().setSourcesConfig(local: value);
  }

  void _updateLrclib(bool value) {
    if (!value && !_enableLocal && !_enableLyricsOvh) return;
    setState(() => _enableLrclib = value);
    context.read<LyricsController>().setSourcesConfig(lrclib: value);
  }

  void _updateLyricsOvh(bool value) {
    if (!value && !_enableLocal && !_enableLrclib) return;
    setState(() => _enableLyricsOvh = value);
    context.read<LyricsController>().setSourcesConfig(lyricsOvh: value);
  }

  Future<void> _handleReSearch() async {
    final controller = context.read<LyricsController>();
    controller.setSourcesConfig(
      local: _enableLocal,
      lrclib: _enableLrclib,
      lyricsOvh: _enableLyricsOvh,
    );
    Navigator.of(context).pop();
    await controller.forceReSearch();
  }

  Future<void> _showLanguagePicker({
    required BuildContext context,
    required String title,
    required String currentCode,
    required bool includeAuto,
    required ValueChanged<String> onSelected,
  }) async {
    final strings = context.read<LocaleController>().localeStrings;
    var searchQuery = '';

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final colorScheme = Theme.of(context).colorScheme;
            final query = searchQuery.toLowerCase().trim();

            final filteredEntries = languagesEndonyms.entries.where((e) {
              if (query.isEmpty) return true;
              return e.key.toLowerCase().contains(query) ||
                  e.value.toLowerCase().contains(query);
            }).toList();

            final showAuto = includeAuto &&
                (query.isEmpty ||
                    'auto'.contains(query) ||
                    strings.npLyricsLangAuto.toLowerCase().contains(query));

            final itemCount = filteredEntries.length + (showAuto ? 1 : 0);

            return AlertDialog(
              title: Text(title),
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
                        itemCount: itemCount,
                        itemBuilder: (context, index) {
                          if (showAuto && index == 0) {
                            final isSelected = currentCode == 'auto' ||
                                currentCode == 'autodetect';
                            return ListTile(
                              leading: Icon(
                                Icons.auto_awesome_rounded,
                                color: isSelected ? colorScheme.primary : null,
                              ),
                              title: Text(
                                strings.npLyricsLangAuto,
                                style: TextStyle(
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              trailing: isSelected
                                  ? Icon(
                                      Icons.check_rounded,
                                      color: colorScheme.primary,
                                    )
                                  : null,
                              onTap: () {
                                onSelected('auto');
                                Navigator.of(dialogCtx).pop();
                              },
                            );
                          }

                          final itemIndex = showAuto ? index - 1 : index;
                          final item = filteredEntries[itemIndex];
                          final isSelected = currentCode == item.key;

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
                                    color: colorScheme.primary,
                                  )
                                : null,
                            onTap: () {
                              onSelected(item.key);
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
                  child: Text(strings.npLyricsSourcesCloseBtn),
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final settings = context.watch<SettingsController>();
    final lyricsController = context.watch<LyricsController>();

    final hasAnySource = _enableLocal || _enableLrclib || _enableLyricsOvh;

    final sourceCode = settings.lyricsTranslationSourceLang;
    final sourceLangDisplay =
        (sourceCode == 'auto' || sourceCode == 'autodetect')
            ? strings.npLyricsLangAuto
            : (languagesEndonyms[sourceCode] ?? sourceCode);

    final targetCode = settings.lyricsTranslationTargetLang;
    final effectiveTarget = targetCode == 'defaultOption'
        ? lyricsController.getEffectiveTargetLanguage()
        : targetCode;
    final targetLangDisplay =
        languagesEndonyms[targetCode] ??
        (languagesEndonyms[effectiveTarget] ?? targetCode);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      title: Center(
        child: SegmentedButton<LyricsDialogTab>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment<LyricsDialogTab>(
              value: LyricsDialogTab.sources,
              label: Text(strings.npLyricsTabSources),
              icon: const Icon(Icons.tune_rounded, size: 18),
            ),
            ButtonSegment<LyricsDialogTab>(
              value: LyricsDialogTab.translation,
              label: Text(strings.npLyricsTabTranslation),
              icon: const Icon(Icons.translate_rounded, size: 18),
            ),
          ],
          selected: {_selectedTab},
          onSelectionChanged: (newSelection) {
            setState(() => _selectedTab = newSelection.first);
          },
        ),
      ),
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      content: SingleChildScrollView(
        child: _selectedTab == LyricsDialogTab.sources
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1. Local Sources Switch
                  SwitchListTile.adaptive(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    secondary: Icon(
                      Icons.audio_file_outlined,
                      color: _enableLocal
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                    title: Text(
                      strings.npLyricsSourceLocal,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      strings.npLyricsSourceLocalDesc,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    value: _enableLocal,
                    onChanged: _updateLocal,
                  ),
                  const Divider(height: 8, indent: 16, endIndent: 16),

                  // 2. Primary Remote API (lrclib.net) Switch
                  SwitchListTile.adaptive(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    secondary: Icon(
                      Icons.cloud_sync_outlined,
                      color: _enableLrclib
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                    title: Text(
                      strings.npLyricsSourceLrclib,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      strings.npLyricsSourceLrclibDesc,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    value: _enableLrclib,
                    onChanged: _updateLrclib,
                  ),
                  const Divider(height: 8, indent: 16, endIndent: 16),

                  // 3. Fallback Remote API (lyrics.ovh) Switch
                  SwitchListTile.adaptive(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    secondary: Icon(
                      Icons.cloud_outlined,
                      color: _enableLyricsOvh
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                    title: Text(
                      strings.npLyricsSourceOvh,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      strings.npLyricsSourceOvhDesc,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    value: _enableLyricsOvh,
                    onChanged: _updateLyricsOvh,
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Source Language Tile
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    leading: Icon(
                      Icons.language_rounded,
                      color: colorScheme.primary,
                    ),
                    title: Text(
                      strings.npLyricsSourceLang,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      sourceLangDisplay,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: const Icon(Icons.arrow_drop_down_rounded),
                    onTap: () => _showLanguagePicker(
                      context: context,
                      title: strings.npLyricsSourceLang,
                      currentCode: sourceCode,
                      includeAuto: true,
                      onSelected: (code) async {
                        await settings.setLyricsTranslationSourceLang(code);
                        if (lyricsController.isTranslated &&
                            lyricsController.hasLyrics) {
                          await lyricsController.translateLyrics(
                            sourceLanguage: code,
                            force: true,
                          );
                        }
                      },
                    ),
                  ),
                  const Divider(height: 8, indent: 16, endIndent: 16),

                  // Target Language Tile
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    leading: Icon(
                      Icons.translate_rounded,
                      color: colorScheme.primary,
                    ),
                    title: Text(
                      strings.npLyricsTargetLang,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      targetLangDisplay,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: const Icon(Icons.arrow_drop_down_rounded),
                    onTap: () => _showLanguagePicker(
                      context: context,
                      title: strings.npLyricsTargetLang,
                      currentCode: targetCode,
                      includeAuto: false,
                      onSelected: (code) async {
                        await settings.setLyricsTranslationTargetLang(code);
                        if (lyricsController.isTranslated &&
                            lyricsController.hasLyrics) {
                          await lyricsController.translateLyrics(
                            targetLanguage: code,
                            force: true,
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.npLyricsSourcesCloseBtn),
        ),
        if (_selectedTab == LyricsDialogTab.sources)
          FilledButton.icon(
            onPressed: hasAnySource ? _handleReSearch : null,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(strings.npLyricsSourcesResearchBtn),
          )
        else if (lyricsController.hasLyrics)
          FilledButton.icon(
            onPressed: () async {
              Navigator.of(context).pop();
              await lyricsController.translateLyrics(force: true);
            },
            icon: const Icon(Icons.translate_rounded, size: 18),
            label: Text(strings.npLyricsRetranslateBtn),
          ),
      ],
    );
  }
}
