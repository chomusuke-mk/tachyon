import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/core/constants/app_defaults.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';

/// Playback Tuning Card (Speed, Pitch, Volume Boost).
class PlaybackTuningCard extends StatelessWidget {
  const PlaybackTuningCard({super.key});

  @override
  Widget build(BuildContext context) {
    final rate = context.select<PlaybackController, double>((c) => c.rate);
    final pitch = context.select<PlaybackController, double>((c) => c.pitch);
    final volume = context.select<PlaybackController, double>((c) => c.volume);
    final playback = context.read<PlaybackController>();
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
            // Playback Speed
            Row(
              children: [
                Icon(Icons.speed_rounded, size: 18, color: colorScheme.primary),
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
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
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
                  onPressed: () =>
                      playback.setRate(AppDefaults.playbackRateDefault),
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
                    divisions:
                        ((AppDefaults.playbackRateMax -
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
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
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
                  onPressed: () =>
                      playback.setPitch(AppDefaults.playbackPitchDefault),
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
                    divisions:
                        ((AppDefaults.playbackPitchMax -
                                    AppDefaults.playbackPitchMin) /
                                0.05)
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
                    strings.npVolume,
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
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${(volume * 100).round()}%',
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
                  onPressed: () => playback.setVolume(1.0),
                  iconSize: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
                Expanded(
                  child: Slider.adaptive(
                    value: volume.clamp(0.0, 2.0),
                    min: 0.0,
                    max: 2.0,
                    divisions: 40,
                    onChanged: playback.setVolume,
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

/// Crossfade Durations Card (Auto duration & Manual skip duration).
class CrossfadeDurationsCard extends StatelessWidget {
  const CrossfadeDurationsCard({super.key});

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
                  tooltip: '${AppDefaults.crossfadeManualDefaultDuration}s',
                  onPressed: () => settings.setCrossfadeManualDuration(
                    AppDefaults.crossfadeManualDefaultDuration,
                  ),
                  iconSize: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
                Expanded(
                  child: Slider(
                    value: settings.crossfadeManualDuration.toDouble().clamp(
                      AppDefaults.crossfadeManualMinDuration.toDouble(),
                      AppDefaults.crossfadeManualMaxDuration.toDouble(),
                    ),
                    min: AppDefaults.crossfadeManualMinDuration.toDouble(),
                    max: AppDefaults.crossfadeManualMaxDuration.toDouble(),
                    divisions:
                        AppDefaults.crossfadeManualMaxDuration -
                        AppDefaults.crossfadeManualMinDuration,
                    onChanged: (val) =>
                        settings.setCrossfadeManualDuration(val.round()),
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
