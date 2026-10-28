import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/widgets/effects/studio_knob.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';

/// Algorithmic Studio Reverb Card (Freeverb model).
///
/// Features:
/// - Acoustic preset selection dropdown (Studio, Small Room, Concert Hall, Cathedral, Plate, Ambient, Custom, Off).
/// - 5 High-precision rotary dials (`StudioKnob`):
///   * Room Size (0% - 100%)
///   * High-Frequency Damping (0% - 100%)
///   * Stereo Reflection Width (0% - 100%)
///   * Wet Level (0.00x - 2.00x)
///   * Dry Level (0.00x - 2.00x)
class ReverbEffectCard extends StatelessWidget {
  const ReverbEffectCard({super.key});

  static const _validPresets = [
    'off',
    'smallRoom',
    'studio',
    'concertHall',
    'cathedral',
    'plate',
    'ambient',
    'custom',
  ];

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final strings = context.watch<LocaleController>().localeStrings;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
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
            // Section Header
            Row(
              children: [
                Icon(
                  Icons.blur_on_rounded,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.sReverb,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        strings.sReverbDesc,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 20),

            // Presets Dropdown
              LayoutBuilder(
                builder: (context, constraints) {
                  final bool isNarrow = constraints.maxWidth < 360;

                  final dropdownWidget = Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.45,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.4,
                        ),
                      ),
                    ),
                    child: DropdownButton<String>(
                      value: _validPresets.contains(settings.reverbPreset)
                          ? settings.reverbPreset
                          : 'custom',
                      underline: const SizedBox(),
                      borderRadius: BorderRadius.circular(12),
                      isDense: true,
                      isExpanded: true,
                      items: [
                        DropdownMenuItem(
                          value: 'off',
                          child: Text(
                            strings.sReverbPresetOff,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'smallRoom',
                          child: Text(
                            strings.sReverbPresetSmallRoom,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'studio',
                          child: Text(
                            strings.sReverbPresetStudio,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'concertHall',
                          child: Text(
                            strings.sReverbPresetConcertHall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'cathedral',
                          child: Text(
                            strings.sReverbPresetCathedral,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'plate',
                          child: Text(
                            strings.sReverbPresetPlate,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'ambient',
                          child: Text(
                            strings.sReverbPresetAmbient,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'custom',
                          child: Text(
                            strings.sReverbPresetCustom,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          settings.setReverbPreset(val);
                        }
                      },
                    ),
                  );

                  final resetButton = IconButton(
                    icon: const Icon(Icons.restore_rounded),
                    tooltip: strings.sReverbPresetOff,
                    iconSize: 20,
                    color: colorScheme.onSurfaceVariant,
                    onPressed: () => settings.setReverbPreset('off'),
                  );

                  if (isNarrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                strings.sReverbPreset,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            resetButton,
                          ],
                        ),
                        const SizedBox(height: 6),
                        SizedBox(width: double.infinity, child: dropdownWidget),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(
                        child: Text(
                          strings.sReverbPreset,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      resetButton,
                      const SizedBox(width: 4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 170),
                        child: dropdownWidget,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),

              // 5 Rotary Studio Knobs
              LayoutBuilder(
                builder: (context, constraints) {
                  final knobs = [
                    StudioKnob(
                      label: strings.sReverbRoomSize,
                      value: settings.reverbRoomSize,
                      min: 0.0,
                      max: 1.0,
                      unit: '%',
                      activeColor: colorScheme.primary,
                      onChanged: settings.setReverbRoomSize,
                    ),
                    StudioKnob(
                      label: strings.sReverbDamping,
                      value: settings.reverbDamping,
                      min: 0.0,
                      max: 1.0,
                      unit: '%',
                      activeColor: colorScheme.tertiary,
                      onChanged: settings.setReverbDamping,
                    ),
                    StudioKnob(
                      label: strings.sReverbWidth,
                      value: settings.reverbWidth,
                      min: 0.0,
                      max: 1.0,
                      unit: '%',
                      activeColor: const Color(0xFF10B981),
                      onChanged: settings.setReverbWidth,
                    ),
                    StudioKnob(
                      label: strings.sReverbWet,
                      value: settings.reverbWet,
                      min: 0.0,
                      max: 2.0,
                      decimals: 2,
                      unit: 'x',
                      activeColor: const Color(0xFFF59E0B),
                      onChanged: settings.setReverbWet,
                    ),
                    StudioKnob(
                      label: strings.sReverbDry,
                      value: settings.reverbDry,
                      min: 0.0,
                      max: 2.0,
                      decimals: 2,
                      unit: 'x',
                      activeColor: const Color(0xFFF43F5E),
                      onChanged: settings.setReverbDry,
                    ),
                  ];

                  return Center(
                    child: Wrap(
                      alignment: WrapAlignment.spaceEvenly,
                      runAlignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 12,
                      children: knobs,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      );
  }
}
