import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../locales/presentation/locale_controller.dart';
import '../domain/playback_state.dart';
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
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
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),

            // 1. Playback Speed (0.5x - 1.5x)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(strings.npSpeed, style: theme.textTheme.titleSmall),
                Text('${playback.rate.toStringAsFixed(2)}x', style: theme.textTheme.labelLarge),
              ],
            ),
            Slider(
              value: playback.rate.clamp(0.5, 1.5),
              min: 0.5,
              max: 1.5,
              divisions: 20,
              onChanged: playback.setRate,
            ),
            Wrap(
              spacing: 8,
              children: [0.5, 0.75, 1.0, 1.25, 1.5].map((preset) {
                return ChoiceChip(
                  label: Text('${preset}x'),
                  selected: (playback.rate - preset).abs() < 0.01,
                  onSelected: (_) => playback.setRate(preset),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // 2. Pitch Shifting (0.5 - 1.5)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(strings.npPitch, style: theme.textTheme.titleSmall),
                Text(playback.pitch.toStringAsFixed(2), style: theme.textTheme.labelLarge),
              ],
            ),
            Slider(
              value: playback.pitch.clamp(0.5, 1.5),
              min: 0.5,
              max: 1.5,
              divisions: 20,
              onChanged: playback.setPitch,
            ),
            TextButton.icon(
              onPressed: () => playback.setPitch(1.0),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Reset Pitch (1.0)'),
            ),
            const SizedBox(height: 16),

            // 3. Volume Boost (up to 200%)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(strings.npVolumeBoost, style: theme.textTheme.titleSmall),
                Text('${(playback.volume * 100).round()}%', style: theme.textTheme.labelLarge),
              ],
            ),
            Slider(
              value: playback.volume.clamp(0.0, 2.0),
              min: 0.0,
              max: 2.0,
              divisions: 40,
              onChanged: playback.setVolume,
            ),
            const SizedBox(height: 16),

            // 4. ReplayGain Normalization Mode
            Text(strings.npReplayGain, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<ReplayGainMode>(
              segments: [
                ButtonSegment(
                  value: ReplayGainMode.off,
                  label: Text(strings.npReplayGainOff),
                ),
                ButtonSegment(
                  value: ReplayGainMode.track,
                  label: Text(strings.npReplayGainTrack),
                ),
                ButtonSegment(
                  value: ReplayGainMode.album,
                  label: Text(strings.npReplayGainAlbum),
                ),
              ],
              selected: {playback.replayGain},
              onSelectionChanged: (set) => playback.setReplayGain(set.first),
            ),
            const SizedBox(height: 16),

            // 5. ReplayGain Preamp Gain
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(strings.npPreamp, style: theme.textTheme.titleSmall),
                Text(
                  '${playback.replayGainPreamp >= 0 ? '+' : ''}${playback.replayGainPreamp.toStringAsFixed(1)} dB',
                  style: theme.textTheme.labelLarge,
                ),
              ],
            ),
            Slider(
              value: playback.replayGainPreamp.clamp(-15.0, 15.0),
              min: -15.0,
              max: 15.0,
              divisions: 30,
              onChanged: playback.setReplayGainPreamp,
            ),
          ],
        ),
      ),
    );
  }
}
