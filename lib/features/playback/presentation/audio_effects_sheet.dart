import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';

import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/domain/playback_state.dart';

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
                  onPressed: () => playback.setRate(1.0),
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
                    value: playback.rate.clamp(0.5, 1.5),
                    min: 0.5,
                    max: 1.5,
                    divisions: 20,
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
                  onPressed: () => playback.setPitch(1.0),
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
                    value: playback.pitch.clamp(0.5, 1.5),
                    min: 0.5,
                    max: 1.5,
                    divisions: 20,
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
                  onPressed: () => playback.setVolume(100.0),
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
                    value: playback.volume.clamp(100.0, 200.0),
                    min: 100.0,
                    max: 200.0,
                    divisions: 100,
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
                      2.0,
                      30.0,
                    ),
                    min: 2.0,
                    max: 30.0,
                    divisions: 28,
                    onChanged: (val) =>
                        settings.setCrossfadeDuration(val.round()),
                  ),
                ),
                Text(
                  '${settings.crossfadeDuration}s',
                  style: theme.textTheme.labelLarge,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
