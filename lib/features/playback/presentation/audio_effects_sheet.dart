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
    final playback = context.watch<PlaybackController>();
    final strings = context.watch<LocaleController>().localeStrings;
    final settings = context.watch<SettingsController>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: SingleChildScrollView(
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
            Text(
              strings.npAudioControls,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),

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
                    value: playback.rate.clamp(
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
                  playback.rate.toStringAsFixed(2),
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
                    value: playback.pitch.clamp(
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
                  playback.pitch.toStringAsFixed(2),
                  style: theme.textTheme.labelLarge,
                ),
              ],
            ),

            // 3. Volume Boost (up to 200%)
            Text(strings.npVolumeBoost, style: theme.textTheme.titleSmall),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [],
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
                    value: playback.volume.clamp(
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
                  playback.volume.toStringAsFixed(0),
                  style: theme.textTheme.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              value: settings.crossfadeEnabled,
              onChanged: (val) => settings.setCrossfadeEnabled(val),
              title: Text(
                strings.sCrossfadeEnable,
                style: theme.textTheme.titleSmall,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.swap_horiz_rounded,
                    size: 25,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  onPressed: () => settings.setCrossfadeDuration(2),
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
                    value: settings.crossfadeDuration.toDouble().clamp(
                      AppDefaults.crossfadeMinDuration.toDouble(),
                      AppDefaults.crossfadeMaxDuration.toDouble(),
                    ),
                    min: AppDefaults.crossfadeMinDuration.toDouble(),
                    max: AppDefaults.crossfadeMaxDuration.toDouble(),
                    divisions:
                        AppDefaults.crossfadeMaxDuration -
                        AppDefaults.crossfadeMinDuration,
                    onChanged: (val) =>
                        settings.setCrossfadeDuration(val.round()),
                  ),
                ),
                Container(
                  constraints: const BoxConstraints(minWidth: 25),
                  child: Text(
                    '${settings.crossfadeDuration}s',
                    style: theme.textTheme.labelLarge,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
