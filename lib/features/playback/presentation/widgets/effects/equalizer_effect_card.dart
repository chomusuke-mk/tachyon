import 'package:flutter/material.dart';
import 'package:miniaudio_player/miniaudio_player.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/widgets/effects/eq_curve_painter.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';

/// Interactive 10-Band Graphic & Parametric Equalizer Card.
///
/// Features:
/// - Real-time biquad response curve preview using [EqCurvePainter] with app theme palette.
/// - Soft vertical frequency axis grid lines showing which point corresponds to each band.
/// - Interactive touch & drag interaction directly on the curve nodes.
/// - Master Preamp slider (-12 dB to +12 dB) with one-tap reset.
/// - Presets dropdown positioned directly below the preamp with a dedicated Reset-to-Flat button.
/// - Frequency projections and gain readouts below the graph.
class EqualizerEffectCard extends StatelessWidget {
  const EqualizerEffectCard({super.key});

  static const _validPresets = [
    'flat',
    'rock',
    'pop',
    'jazz',
    'classical',
    'bassBoost',
    'custom',
  ];

  static const _shortFreqLabels = [
    '31',
    '63',
    '125',
    '250',
    '500',
    '1k',
    '2k',
    '4k',
    '8k',
    '16k',
  ];

  void _handleGraphInteraction(
    Offset localPos,
    Size size,
    SettingsController settings,
  ) {
    if (size.width <= 0 || size.height <= 0) return;

    int closestBand = 0;
    double minDistance = double.infinity;
    for (int i = 0; i < EqCurvePainter.bandCount; i++) {
      final bandX = EqCurvePainter.getXForBand(i, size.width);
      final dist = (bandX - localPos.dx).abs();
      if (dist < minDistance) {
        minDistance = dist;
        closestBand = i;
      }
    }

    final centerY = size.height / 2;
    final verticalAmplitude = size.height * 0.38;
    final normalized = -((localPos.dy - centerY) / verticalAmplitude);
    final gainDb = (normalized * 12.0).clamp(-12.0, 12.0);

    settings.setEqualizerBandGain(closestBand, gainDb);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final strings = context.watch<LocaleController>().localeStrings;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final gains = settings.equalizerGains;
    final equalizer = Equalizer.fromList(
      gains.length == 10 ? gains : List.filled(10, 0.0),
    );

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
            // Card Header with Icon and Title
            Row(
              children: [
                Icon(
                  Icons.equalizer_rounded,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    strings.sEqualizerTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 1. Master Preamp Slider (-12 dB to +12 dB)
              Row(
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      strings.sPreamp,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.5,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${settings.preampDb > 0 ? '+' : ''}${settings.preampDb.toStringAsFixed(1)} dB',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.restore_rounded),
                    tooltip: '0.0 dB',
                    onPressed: () => settings.setPreamp(0.0),
                    iconSize: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  Expanded(
                    child: Slider.adaptive(
                      value: settings.preampDb.clamp(-12.0, 12.0),
                      min: -12.0,
                      max: 12.0,
                      divisions: 48,
                      onChanged: (val) => settings.setPreamp(val),
                    ),
                  ),
                ],
              ),
              const Divider(height: 16),

              // 2. Presets Dropdown positioned below Preamp with Reset button (Resets to Flat)
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 360;

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
                      value: _validPresets.contains(settings.equalizerPreset)
                          ? settings.equalizerPreset
                          : 'custom',
                      underline: const SizedBox(),
                      borderRadius: BorderRadius.circular(12),
                      isDense: true,
                      isExpanded: true,
                      items: [
                        DropdownMenuItem(
                          value: 'flat',
                          child: Text(
                            strings.sEqPresetFlat,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'rock',
                          child: Text(
                            strings.sEqPresetRock,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'pop',
                          child: Text(
                            strings.sEqPresetPop,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'jazz',
                          child: Text(
                            strings.sEqPresetJazz,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'classical',
                          child: Text(
                            strings.sEqPresetClassical,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'bassBoost',
                          child: Text(
                            strings.sEqPresetBassBoost,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'custom',
                          child: Text(
                            strings.sEqPresetCustom,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          settings.setEqualizerPreset(val);
                        }
                      },
                    ),
                  );

                  final resetButton = IconButton(
                    icon: const Icon(Icons.restore_rounded),
                    tooltip: strings.sEqPresetFlat,
                    iconSize: 20,
                    color: colorScheme.onSurfaceVariant,
                    onPressed: () {
                      settings.setEqualizerPreset('flat');
                      settings.setPreamp(0.0);
                    },
                  );

                  if (isNarrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                strings.sEqualizerPreset,
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
                          strings.sEqualizerPreset,
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
              const SizedBox(height: 14),

              // 3. Interactive Biquad Response Curve Graph with App Theme Colors
              LayoutBuilder(
                builder: (context, constraints) {
                  const graphHeight = 130.0;
                  final width = constraints.maxWidth;

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) {
                      _handleGraphInteraction(
                        details.localPosition,
                        Size(width, graphHeight),
                        settings,
                      );
                    },
                    onPanUpdate: (details) {
                      _handleGraphInteraction(
                        details.localPosition,
                        Size(width, graphHeight),
                        settings,
                      );
                    },
                    child: Container(
                      width: width,
                      height: graphHeight,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.35,
                          ),
                          width: 1.0,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: CustomPaint(
                          size: Size(width, graphHeight),
                          painter: EqCurvePainter(
                            equalizer: equalizer,
                            activeColor: colorScheme.primary,
                            backgroundColor: colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.35),
                            gridLineColor: colorScheme.outlineVariant
                                .withValues(alpha: 0.3),
                            zeroLineColor: colorScheme.outlineVariant
                                .withValues(alpha: 0.5),
                            labelColor: colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.75),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),

              // 4. Projections below each point outside the graph
              LayoutBuilder(
                builder: (context, constraints) {
                  return Row(
                    children: [
                      const Expanded(flex: 1, child: SizedBox.shrink()),
                      for (int i = 0; i < EqCurvePainter.bandCount; i++) ...[
                        Expanded(
                          flex: 2,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _shortFreqLabels[i],
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: colorScheme.onSurfaceVariant,
                                  fontFamily: 'monospace',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                gains[i] > 0
                                    ? '+${gains[i].toStringAsFixed(1)}'
                                    : gains[i].toStringAsFixed(1),
                                style: TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w700,
                                  color: gains[i] != 0.0
                                      ? colorScheme.primary
                                      : colorScheme.onSurfaceVariant.withValues(
                                          alpha: 0.5,
                                        ),
                                  fontFamily: 'monospace',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                      const Expanded(flex: 1, child: SizedBox.shrink()),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      );
  }
}
