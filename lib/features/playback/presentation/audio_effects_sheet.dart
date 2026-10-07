import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/core/constants/app_defaults.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';

/// Modal bottom sheet or dialog presenting advanced audio controls and effects:
/// - Playback Speed (0.5x - 1.5x with reset)
/// - Pitch Shifting (0.5 - 1.5 with reset)
/// - Volume Boost (up to 200% with reset)
/// - Crossfade Transitions (Auto duration, Manual skip duration)
/// - 10-Band Graphic Equalizer with Presets and Adaptive Spacing
class AudioEffectsSheet extends StatelessWidget {
  final bool isDialog;

  const AudioEffectsSheet({super.key, this.isDialog = false});

  @override
  Widget build(BuildContext context) {
    final rate = context.select<PlaybackController, double>((c) => c.rate);
    final pitch = context.select<PlaybackController, double>((c) => c.pitch);
    final volume = context.select<PlaybackController, double>((c) => c.volume);
    final playback = context.read<PlaybackController>();
    final strings = context.watch<LocaleController>().localeStrings;
    final settings = context.watch<SettingsController>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 360;
        final horizontalPad = isCompact ? 12.0 : 20.0;

        return Container(
          padding: EdgeInsets.fromLTRB(
            horizontalPad,
            isDialog ? 20 : 12,
            horizontalPad,
            isDialog ? 20 : 32,
          ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle for bottom sheet mode
          if (!isDialog) ...[
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Title & Close Button
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.tune_rounded,
                  color: colorScheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  strings.npAudioControls,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Card 1: Playback Tuning (Speed, Pitch, Volume)
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
                          Row(
                            children: [
                              Icon(
                                Icons.speed_rounded,
                                size: 18,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  strings.npSpeed,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
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
                                  color: colorScheme.surfaceContainerHighest
                                      .withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${rate.toStringAsFixed(2)}x',
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
                                tooltip: '1.0x',
                                onPressed: () => playback
                                    .setRate(AppDefaults.playbackRateDefault),
                                iconSize: 20,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              Expanded(
                                child: Slider.adaptive(
                                  value: rate.clamp(
                                    AppDefaults.playbackRateMin,
                                    AppDefaults.playbackRateMax,
                                  ),
                                  min: AppDefaults.playbackRateMin,
                                  max: AppDefaults.playbackRateMax,
                                  divisions: ((AppDefaults.playbackRateMax -
                                              AppDefaults.playbackRateMin) /
                                          0.1)
                                      .round(),
                                  onChanged: playback.setRate,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 16),

                          // Pitch Shifting
                          Row(
                            children: [
                              Icon(
                                Icons.keyboard_voice_rounded,
                                size: 18,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  strings.npPitch,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
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
                                  color: colorScheme.surfaceContainerHighest
                                      .withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  pitch.toStringAsFixed(2),
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
                                tooltip: '1.0',
                                onPressed: () => playback
                                    .setPitch(AppDefaults.playbackPitchDefault),
                                iconSize: 20,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              Expanded(
                                child: Slider(
                                  value: pitch.clamp(
                                    AppDefaults.playbackPitchMin,
                                    AppDefaults.playbackPitchMax,
                                  ),
                                  min: AppDefaults.playbackPitchMin,
                                  max: AppDefaults.playbackPitchMax,
                                  divisions: ((AppDefaults.playbackPitchMax -
                                              AppDefaults.playbackPitchMin) /
                                          0.1)
                                      .round(),
                                  onChanged: playback.setPitch,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 16),

                          // Volume Boost
                          Row(
                            children: [
                              Icon(
                                Icons.volume_up_rounded,
                                size: 18,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  strings.npVolumeBoost,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
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
                                  color: colorScheme.surfaceContainerHighest
                                      .withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${volume.toStringAsFixed(0)}%',
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
                                tooltip: '100%',
                                onPressed: () => playback
                                    .setVolume(AppDefaults.volumeBoostDefault),
                                iconSize: 20,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              Expanded(
                                child: Slider(
                                  value: volume.clamp(
                                    AppDefaults.volumeBoostMin,
                                    AppDefaults.volumeBoostMax,
                                  ),
                                  min: AppDefaults.volumeBoostMin,
                                  max: AppDefaults.volumeBoostMax,
                                  divisions: (AppDefaults.volumeBoostMax -
                                          AppDefaults.volumeBoostMin)
                                      .round(),
                                  onChanged: playback.setVolume,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Card 2: Crossfade Durations
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
                          Row(
                            children: [
                              Icon(
                                Icons.swap_horiz_rounded,
                                size: 18,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  strings.sCrossfadeEnable,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Auto Crossfade Duration
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  strings.npCrossfadeAuto,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${settings.crossfadeDuration}s',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.restore_rounded),
                                tooltip: '${AppDefaults.crossfadeDefaultDuration}s',
                                onPressed: () => settings.setCrossfadeDuration(
                                  AppDefaults.crossfadeDefaultDuration,
                                ),
                                iconSize: 20,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              Expanded(
                                child: Slider(
                                  value: settings.crossfadeDuration
                                      .toDouble()
                                      .clamp(
                                        AppDefaults.crossfadeMinDuration
                                            .toDouble(),
                                        AppDefaults.crossfadeMaxDuration
                                            .toDouble(),
                                      ),
                                  min: AppDefaults.crossfadeMinDuration
                                      .toDouble(),
                                  max: AppDefaults.crossfadeMaxDuration
                                      .toDouble(),
                                  divisions: AppDefaults.crossfadeMaxDuration -
                                      AppDefaults.crossfadeMinDuration,
                                  onChanged: (val) => settings
                                      .setCrossfadeDuration(val.round()),
                                ),
                              ),
                            ],
                          ),

                          // Manual Skip Crossfade Duration
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  strings.npCrossfadeManual,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${settings.crossfadeManualDuration}s',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.restore_rounded),
                                tooltip: '3s',
                                onPressed: () =>
                                    settings.setCrossfadeManualDuration(3),
                                iconSize: 20,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              Expanded(
                                child: Slider(
                                  value: settings.crossfadeManualDuration
                                      .toDouble()
                                      .clamp(0.0, 10.0),
                                  min: 0.0,
                                  max: 10.0,
                                  divisions: 10,
                                  onChanged: (val) => settings
                                      .setCrossfadeManualDuration(val.round()),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Card 3: 10-Band Graphic Equalizer
                  const _EqualizerSection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  },
);
}
}

class _EqualizerSection extends StatelessWidget {
  const _EqualizerSection();

  static const _bandFrequencies = [
    '60Hz',
    '170Hz',
    '310Hz',
    '600Hz',
    '1kHz',
    '3kHz',
    '6kHz',
    '12kHz',
    '14kHz',
    '16kHz',
  ];

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final strings = context.watch<LocaleController>().localeStrings;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isEnabled = settings.equalizerEnabled;
    final gains = settings.equalizerGains;

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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
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
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Switch.adaptive(
                  value: isEnabled,
                  onChanged: (val) => settings.setEqualizerEnabled(val),
                ),
              ],
            ),
            if (isEnabled) ...[
              const SizedBox(height: 14),
              // Preset Selector Row in modern container
              LayoutBuilder(
                builder: (context, constraints) {
                  final bool isNarrow = constraints.maxWidth < 360;
                  final dropdownWidget = Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                    child: DropdownButton<String>(
                      value: settings.equalizerPreset,
                      underline: const SizedBox(),
                      borderRadius: BorderRadius.circular(12),
                      isDense: true,
                      isExpanded: true,
                      items: [
                        DropdownMenuItem(
                          value: 'flat',
                          child: Text(strings.sEqPresetFlat, overflow: TextOverflow.ellipsis),
                        ),
                        DropdownMenuItem(
                          value: 'rock',
                          child: Text(strings.sEqPresetRock, overflow: TextOverflow.ellipsis),
                        ),
                        DropdownMenuItem(
                          value: 'pop',
                          child: Text(strings.sEqPresetPop, overflow: TextOverflow.ellipsis),
                        ),
                        DropdownMenuItem(
                          value: 'jazz',
                          child: Text(strings.sEqPresetJazz, overflow: TextOverflow.ellipsis),
                        ),
                        DropdownMenuItem(
                          value: 'classical',
                          child: Text(strings.sEqPresetClassical, overflow: TextOverflow.ellipsis),
                        ),
                        DropdownMenuItem(
                          value: 'bassBoost',
                          child: Text(strings.sEqPresetBassBoost, overflow: TextOverflow.ellipsis),
                        ),
                        DropdownMenuItem(
                          value: 'custom',
                          child: Text(strings.sEqPresetCustom, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          settings.setEqualizerPreset(val);
                        }
                      },
                    ),
                  );

                  if (isNarrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.sEqualizerPreset,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: double.infinity,
                          child: dropdownWidget,
                        ),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(
                        child: Text(
                          strings.sEqualizerPreset,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 170),
                        child: dropdownWidget,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),

              // Adaptive 10-Band Equalizer Sliders
              LayoutBuilder(
                builder: (context, constraints) {
                  final double availableWidth = constraints.maxWidth;
                  final double eqWidth = availableWidth.clamp(0.0, 520.0);
                  final double bandColumnWidth = eqWidth / 10;
                  final bool isNarrow = bandColumnWidth < 34.0;
                  final double sliderWidth = (bandColumnWidth * 0.9).clamp(18.0, 32.0);

                  return Center(
                    child: SizedBox(
                      width: eqWidth,
                      height: 175,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(10, (index) {
                          final gain = index < gains.length ? gains[index] : 0.0;
                          final freqLabel = index < _bandFrequencies.length
                              ? _bandFrequencies[index]
                              : '${index + 1}';

                          return SizedBox(
                            width: bandColumnWidth,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  height: 14,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      '${gain > 0 ? '+' : ''}${gain.toStringAsFixed(1)}',
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        fontSize: isNarrow ? 8.5 : 10,
                                        fontWeight: gain != 0.0
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: gain != 0.0
                                            ? colorScheme.primary
                                            : colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                SizedBox(
                                  height: 110,
                                  width: sliderWidth,
                                  child: RotatedBox(
                                    quarterTurns: 3,
                                    child: SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        trackHeight: isNarrow ? 2.0 : 3.0,
                                        thumbShape: RoundSliderThumbShape(
                                          enabledThumbRadius: isNarrow ? 3.5 : 5.0,
                                        ),
                                        overlayShape: RoundSliderOverlayShape(
                                          overlayRadius: isNarrow ? 7.0 : 10.0,
                                        ),
                                      ),
                                      child: Slider(
                                        value: gain.clamp(-24.0, 24.0),
                                        min: -24.0,
                                        max: 24.0,
                                        onChanged: (val) {
                                          settings.setEqualizerBandGain(
                                            index,
                                            val,
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                SizedBox(
                                  height: 14,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      freqLabel,
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        fontSize: isNarrow ? 8.5 : 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
