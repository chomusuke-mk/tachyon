import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';

/// Audio Enhancements Card.
///
/// Features:
/// - Dynamic Volume Normalization (EBU R128 / ReplayGain track loudness matching).
/// - Non-destructive Skip Silence detection during playback.
/// - True-Peak Brickwall Limiter to avoid inter-sample distortion and digital clipping.
/// - Downmix to Mono Audio for single-earphone listening or accessibility.
class AudioEnhancementsCard extends StatelessWidget {
  const AudioEnhancementsCard({super.key});

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
            // Volume Normalization
            Row(
              children: [
                Icon(
                  Icons.auto_fix_high_rounded,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.sReplayGainMode,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        strings.sReplayGainModeDesc,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Switch(
                  value: settings.volumeNormalization,
                  onChanged: (val) => settings.setVolumeNormalization(val),
                ),
              ],
            ),
            const Divider(height: 24),

            // Skip Silence
            Row(
              children: [
                Icon(
                  Icons.graphic_eq_rounded,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.sSkipSilence,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        strings.sSkipSilenceDesc,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Switch(
                  value: settings.skipSilence,
                  onChanged: (val) => settings.setSkipSilence(val),
                ),
              ],
            ),
            const Divider(height: 24),

            // True-Peak Limiter
            Row(
              children: [
                Icon(
                  Icons.shield_rounded,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.sLimiter,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        strings.sLimiterDesc,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Switch(
                  value: settings.limiterEnabled,
                  onChanged: (val) => settings.setLimiter(val),
                ),
              ],
            ),
            const Divider(height: 24),

            // Mono Audio
            Row(
              children: [
                Icon(
                  Icons.volume_down_rounded,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.sMonoAudio,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        strings.sMonoAudioDesc,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Switch(
                  value: settings.mono,
                  onChanged: (val) => settings.setMono(val),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
