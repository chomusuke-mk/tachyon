import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/core/constants/app_defaults.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';

import 'package:tachyon/features/locales/presentation/locale_controller.dart';

import 'playback_controller.dart';

/// Modal bottom sheet presenting advanced audio controls and effects:
/// - Playback Speed (0.5x - 1.5x with presets)
/// - Pitch Shifting (0.5 - 1.5 with reset)
/// - Volume Boost (up to 200%)
/// - ReplayGain Normalization Mode (Off, Track, Album)
/// - ReplayGain Preamp (-15 dB to +15 dB)
class AudioEffectsSheet extends StatelessWidget {
  const AudioEffectsSheet({super.key});

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

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
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
            const SizedBox(height: 16),

            // Title
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(Icons.equalizer_rounded),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  overflow: TextOverflow.ellipsis,
                  strings.npAudioControls,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
            const SizedBox(height: 20),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1. Playback Speed (0.5x - 1.5x)
                  Text(strings.npSpeed, style: theme.textTheme.titleSmall),
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.speed_rounded),
                        onPressed: () =>
                            playback.setRate(AppDefaults.playbackRateDefault),
                        iconSize: 25,
                        color: colorScheme.onSurfaceVariant,
                        constraints: const BoxConstraints(
                          minWidth: 24,
                          minHeight: 24,
                        ),
                        style: IconButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                        ),
                      ),
                      Expanded(
                        child: Slider.adaptive(
                          value: rate.clamp(
                            AppDefaults.playbackRateMin,
                            AppDefaults.playbackRateMax,
                          ),
                          min: AppDefaults.playbackRateMin,
                          max: AppDefaults.playbackRateMax,
                          divisions:
                              ((AppDefaults.playbackRateMax -
                                          AppDefaults.playbackRateMin) /
                                      0.1)
                                  .round(),
                          onChanged: playback.setRate,
                        ),
                      ),
                      Text(
                        rate.toStringAsFixed(2),
                        style: theme.textTheme.labelLarge,
                      ),
                    ],
                  ),
                  // 2. Pitch Shifting (0.5 - 1.5)
                  Text(strings.npPitch, style: theme.textTheme.titleSmall),
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.keyboard_voice_rounded,
                          size: 25,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        onPressed: () =>
                            playback.setPitch(AppDefaults.playbackPitchDefault),
                        iconSize: 25,
                        color: colorScheme.onSurfaceVariant,
                        constraints: const BoxConstraints(
                          minWidth: 24,
                          minHeight: 24,
                        ),
                        style: IconButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: pitch.clamp(
                            AppDefaults.playbackPitchMin,
                            AppDefaults.playbackPitchMax,
                          ),
                          min: AppDefaults.playbackPitchMin,
                          max: AppDefaults.playbackPitchMax,
                          divisions:
                              ((AppDefaults.playbackPitchMax -
                                          AppDefaults.playbackPitchMin) /
                                      0.1)
                                  .round(),
                          onChanged: playback.setPitch,
                        ),
                      ),
                      Text(
                        pitch.toStringAsFixed(2),
                        style: theme.textTheme.labelLarge,
                      ),
                    ],
                  ),

                  // 3. Volume Boost (up to 200%)
                  Text(
                    strings.npVolumeBoost,
                    style: theme.textTheme.titleSmall,
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.headphones_rounded,
                          size: 25,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        onPressed: () =>
                            playback.setVolume(AppDefaults.volumeBoostDefault),
                        iconSize: 25,
                        color: colorScheme.onSurfaceVariant,
                        constraints: const BoxConstraints(
                          minWidth: 24,
                          minHeight: 24,
                        ),
                        style: IconButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: volume.clamp(
                            AppDefaults.volumeBoostMin,
                            AppDefaults.volumeBoostMax,
                          ),
                          min: AppDefaults.volumeBoostMin,
                          max: AppDefaults.volumeBoostMax,
                          divisions:
                              ((AppDefaults.volumeBoostMax -
                                      AppDefaults.volumeBoostMin))
                                  .round(),
                          onChanged: playback.setVolume,
                        ),
                      ),
                      Text(
                        volume.toStringAsFixed(0),
                        style: theme.textTheme.labelLarge,
                      ),
                    ],
                  ),
                    const Divider(height: 32),
                    Text(
                      strings.sCrossfadeEnable,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Auto Crossfade Duration
                    Text(
                      strings.npCrossfadeAuto,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.swap_horiz_rounded),
                          onPressed: () => settings.setCrossfadeDuration(
                            AppDefaults.crossfadeDefaultDuration,
                          ),
                          iconSize: 24,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        Expanded(
                          child: Slider(
                            value: settings.crossfadeDuration.toDouble().clamp(
                              AppDefaults.crossfadeMinDuration.toDouble(),
                              AppDefaults.crossfadeMaxDuration.toDouble(),
                            ),
                            min: AppDefaults.crossfadeMinDuration.toDouble(),
                            max: AppDefaults.crossfadeMaxDuration.toDouble(),
                            divisions: AppDefaults.crossfadeMaxDuration -
                                AppDefaults.crossfadeMinDuration,
                            onChanged: (val) =>
                                settings.setCrossfadeDuration(val.round()),
                          ),
                        ),
                        Container(
                          constraints: const BoxConstraints(minWidth: 32),
                          child: Text(
                            '${settings.crossfadeDuration}s',
                            style: theme.textTheme.labelLarge,
                          ),
                        ),
                      ],
                    ),
                    // Manual Skip Crossfade Duration
                    Text(
                      strings.npCrossfadeManual,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.skip_next_rounded),
                          onPressed: () =>
                              settings.setCrossfadeManualDuration(3),
                          iconSize: 24,
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
                            onChanged: (val) =>
                                settings.setCrossfadeManualDuration(val.round()),
                          ),
                        ),
                        Container(
                          constraints: const BoxConstraints(minWidth: 32),
                          child: Text(
                            '${settings.crossfadeManualDuration}s',
                            style: theme.textTheme.labelLarge,
                          ),
                        ),
                      ],
                    ),
                    const _EqualizerSection(),
                  ],
                ),
              ),
            ),
          ],
        ),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.tune_rounded, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  strings.sEqualizerTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Switch.adaptive(
              value: isEnabled,
              onChanged: (val) => settings.setEqualizerEnabled(val),
            ),
          ],
        ),
        if (isEnabled) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                strings.sEqualizerPreset,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              DropdownButton<String>(
                value: settings.equalizerPreset,
                underline: const SizedBox(),
                borderRadius: BorderRadius.circular(12),
                items: [
                  DropdownMenuItem(value: 'flat', child: Text(strings.sEqPresetFlat)),
                  DropdownMenuItem(value: 'rock', child: Text(strings.sEqPresetRock)),
                  DropdownMenuItem(value: 'pop', child: Text(strings.sEqPresetPop)),
                  DropdownMenuItem(value: 'jazz', child: Text(strings.sEqPresetJazz)),
                  DropdownMenuItem(value: 'classical', child: Text(strings.sEqPresetClassical)),
                  DropdownMenuItem(value: 'bassBoost', child: Text(strings.sEqPresetBassBoost)),
                  DropdownMenuItem(value: 'custom', child: Text(strings.sEqPresetCustom)),
                ],
                onChanged: (val) {
                  if (val != null) {
                    settings.setEqualizerPreset(val);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(10, (index) {
                  final gain = index < gains.length ? gains[index] : 0.0;
                  final freqLabel = index < _bandFrequencies.length
                      ? _bandFrequencies[index]
                      : '${index + 1}';
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${gain > 0 ? '+' : ''}${gain.toStringAsFixed(1)}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 10,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 120,
                          width: 32,
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 12,
                                ),
                              ),
                              child: Slider(
                                value: gain.clamp(-24.0, 24.0),
                                min: -24.0,
                                max: 24.0,
                                onChanged: (val) {
                                  settings.setEqualizerBandGain(index, val);
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          freqLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

