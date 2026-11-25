import 'package:material_ui/material_ui.dart';
import 'package:tachyon/core/platform/file_picker_service.dart';
import 'package:tachyon/core/storage/persistent_binary_storage.dart';
import 'package:tachyon/features/locales/domain/locale.dart';
import 'package:tachyon/features/settings/presentation/controllers/settings_controller.dart';
import 'package:tachyon/features/settings/presentation/widgets/music_sources_section.dart';
import 'package:tachyon/shared/theme/app_theme.dart';
import 'package:tachyon/shared/utils/toast_utils.dart';
import 'package:tachyon/shared/widgets/setting_row.dart';

/// Settings section configuring theme mode, OLED black surfaces, accent color
/// swatches, and custom background image blur/dim controls.
class AppearanceSettingsSection extends StatelessWidget {
  /// Settings controller managing persisted visual preferences.
  final SettingsController settings;

  /// Localized labels and feedback messages.
  final AppStringKey strings;

  /// Creates an [AppearanceSettingsSection].
  const AppearanceSettingsSection({
    super.key,
    required this.settings,
    required this.strings,
  });

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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SettingsSectionCard(
      title: strings.sAppearanceSection,
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
                        label: showLabels ? Text(strings.sThemeSystem) : null,
                        tooltip: showLabels ? null : strings.sThemeSystem,
                      ),
                      ButtonSegment<ThemeMode>(
                        value: ThemeMode.light,
                        icon: const Icon(Icons.light_mode_rounded, size: 18),
                        label: showLabels ? Text(strings.sThemeLight) : null,
                        tooltip: showLabels ? null : strings.sThemeLight,
                      ),
                      ButtonSegment<ThemeMode>(
                        value: ThemeMode.dark,
                        icon: const Icon(Icons.dark_mode_rounded, size: 18),
                        label: showLabels ? Text(strings.sThemeDark) : null,
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
                  for (final color in TachyonColors.predefinedAccentColors)
                    _buildColorCircle(
                      context: context,
                      color: color,
                      isSelected:
                          settings.accentColorValue == color.toARGB32(),
                      onTap: () => settings.setAccentColor(color.toARGB32()),
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
                        final picked = await FilePickerService.pickImage(
                          dialogTitle: strings.sSelectBackgroundImage,
                        );
                        if (picked != null) {
                          final success = await settings.setCustomBackground(
                            picked,
                          );
                          if (!success && context.mounted) {
                            ToastUtils.showError(
                              strings.sCustomBackgroundFileError,
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
                                color: colorScheme.outlineVariant.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child:
                                PersistentBinaryStorage.buildLocalOrOpfsImage(
                                  settings.customBackgroundPath!,
                                  width: 52,
                                  height: 52,
                                  cacheWidth: 104,
                                  fit: BoxFit.cover,
                                  fallback: const Icon(
                                    Icons.broken_image_rounded,
                                    size: 32,
                                  ),
                                ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.tonalIcon(
                          icon: const Icon(Icons.photo_library_outlined),
                          label: Text(strings.sChangeBackgroundImage),
                          onPressed: () async {
                            final picked = await FilePickerService.pickImage(
                              dialogTitle: strings.sChangeBackgroundImage,
                            );
                            if (picked != null) {
                              await settings.setCustomBackground(picked);
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded),
                          tooltip: strings.sRemoveBackgroundImage,
                          color: colorScheme.error,
                          onPressed: () => settings.setCustomBackground(null),
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
                onChanged: (val) => settings.setBackgroundBlurSigma(val),
              ),
            ),
            const Divider(),
            SettingRow(
              title: strings.sBackgroundDim,
              description: '${(settings.backgroundDimOpacity * 100).round()}%',
              type: ControllerType.slider,
              child: Slider(
                value: settings.backgroundDimOpacity,
                min: 0.20,
                max: 0.95,
                divisions: 15,
                label: '${(settings.backgroundDimOpacity * 100).round()}%',
                onChanged: (val) => settings.setBackgroundDimOpacity(val),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
