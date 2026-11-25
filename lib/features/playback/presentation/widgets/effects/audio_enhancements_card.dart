import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';
import 'package:tachyon/shared/utils/duration_formatter.dart';

/// Audio Enhancements Card.
///
/// Features:
/// - Dynamic Volume Normalization (EBU R128 / ReplayGain track loudness matching).
/// - Non-destructive Skip Silence detection with selectable mode & saved-time readout.
/// - True-Peak Brickwall Limiter to avoid inter-sample distortion and digital clipping.
/// - Downmix to Mono Audio for single-earphone listening or accessibility.
class AudioEnhancementsCard extends StatelessWidget {
  const AudioEnhancementsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.read<SettingsController>();
    final playback = Provider.of<PlaybackController?>(context, listen: false);
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
        child: ListenableBuilder(
          listenable: settings.enhancementsListenable,
          builder: (context, _) {
            return Column(
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
                      onChanged: settings.setVolumeNormalization,
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
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  strings.sSkipSilence,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (playback != null)
                                ValueListenableBuilder<Duration>(
                                  valueListenable:
                                      playback.silenceSavedDurationListenable,
                                  builder: (context, saved, _) {
                                    if (saved <= Duration.zero) {
                                      return const SizedBox.shrink();
                                    }
                                    return Container(
                                      margin: const EdgeInsets.only(left: 8),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colorScheme.primaryContainer
                                            .withValues(alpha: 0.6),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '-${saved.toFormattedString()}',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: colorScheme
                                                  .onPrimaryContainer,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    );
                                  },
                                ),
                            ],
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
                      onChanged: settings.setSkipSilence,
                    ),
                  ],
                ),
                if (settings.skipSilence) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: SegmentedButton<SilenceSkipMode>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment<SilenceSkipMode>(
                            value: SilenceSkipMode.trimEdges,
                            label: Text('Edges'),
                          ),
                          ButtonSegment<SilenceSkipMode>(
                            value: SilenceSkipMode.continuous,
                            label: Text('Continuous'),
                          ),
                          ButtonSegment<SilenceSkipMode>(
                            value: SilenceSkipMode.all,
                            label: Text('All'),
                          ),
                        ],
                        selected: {
                          settings.silenceSkipMode == SilenceSkipMode.disabled
                              ? SilenceSkipMode.all
                              : settings.silenceSkipMode,
                        },
                        onSelectionChanged: (selected) {
                          settings.setSilenceSkipMode(selected.first);
                        },
                      ),
                    ),
                  ),
                ],
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
                      onChanged: settings.setLimiter,
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
                    Switch(value: settings.mono, onChanged: settings.setMono),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
