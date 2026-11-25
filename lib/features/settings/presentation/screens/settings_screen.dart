import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/core/constants/languages.dart';
import 'package:tachyon/features/locales/presentation/controllers/locale_controller.dart';
import 'package:tachyon/features/settings/presentation/controllers/settings_controller.dart';
import 'package:tachyon/features/settings/presentation/widgets/appearance_settings_section.dart';
import 'package:tachyon/features/settings/presentation/widgets/audio_settings_section.dart';
import 'package:tachyon/features/settings/presentation/widgets/language_picker_dialog.dart';
import 'package:tachyon/features/settings/presentation/widgets/music_sources_section.dart';
import 'package:tachyon/shared/theme/app_theme.dart';
import 'package:tachyon/shared/widgets/app_icon.dart';
import 'package:tachyon/shared/widgets/setting_row.dart';

/// Application settings screen organizing library sources, audio engine tuning,
/// appearance customization, language preferences, and version information.
class SettingsScreen extends StatelessWidget {
  /// Creates a [SettingsScreen].
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final localeController = context.watch<LocaleController>();
    final strings = localeController.localeStrings;
    final currentLocale = localeController.currentLocaleCode;
    final settings = context.watch<SettingsController>();
    final colorScheme = Theme.of(context).colorScheme;
    final isDesktop = TachyonBreakpoints.isDesktop(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            if (!isDesktop) const AppIcon(),
            Text(strings.sTitle),
          ],
        ),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          MusicSourcesSection(settings: settings, strings: strings),
          const SizedBox(height: 20),
          AudioSettingsSection(settings: settings, strings: strings),
          const SizedBox(height: 20),
          AppearanceSettingsSection(settings: settings, strings: strings),
          const SizedBox(height: 20),
          SettingsSectionCard(
            title: strings.sLanguageSection,
            child: Column(
              children: [
                SettingRow(
                  title: strings.sLanguage,
                  description: strings.sLanguageDesc,
                  type: ControllerType.dropdown,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => LanguagePickerDialog.show(
                      context,
                      title: strings.sLanguage,
                      currentSelectedValue: settings.appLanguage,
                      strings: strings,
                      onSelected: settings.setAppLanguage,
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
                              (settings.appLanguage == 'defaultOption')
                                  ? '${strings.sTranslationLangDefault} (${languagesEndonyms[currentLocale] ?? currentLocale})'
                                  : (languagesEndonyms[settings.appLanguage] ??
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
                    onTap: () => LanguagePickerDialog.show(
                      context,
                      title: strings.sTranslationTargetLang,
                      currentSelectedValue:
                          settings.lyricsTranslationTargetLang,
                      strings: strings,
                      onSelected: settings.setLyricsTranslationTargetLang,
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
          const SizedBox(height: 20),
          SettingsSectionCard(
            title: strings.sAboutSection,
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
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
