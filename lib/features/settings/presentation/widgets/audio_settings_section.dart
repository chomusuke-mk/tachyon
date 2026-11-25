import 'package:material_ui/material_ui.dart';
import 'package:tachyon/core/constants/app_defaults.dart';
import 'package:tachyon/core/playback/domain/crossfade_config.dart';
import 'package:tachyon/features/locales/domain/locale.dart';
import 'package:tachyon/features/settings/presentation/controllers/settings_controller.dart';
import 'package:tachyon/features/settings/presentation/widgets/music_sources_section.dart';
import 'package:tachyon/shared/widgets/setting_row.dart';

/// Settings section configuring audio playback features including crossfade,
/// ReplayGain normalization, silence skipping, limiter, mono mix, and output
/// device change handling.
class AudioSettingsSection extends StatelessWidget {
  /// Settings controller managing persisted audio preferences.
  final SettingsController settings;

  /// Localized setting labels and descriptions.
  final AppStringKey strings;

  /// Creates an [AudioSettingsSection].
  const AudioSettingsSection({
    super.key,
    required this.settings,
    required this.strings,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsSectionCard(
      title: strings.sAudioSection,
      child: Column(
        children: [
          SettingRow(
            title: strings.npCrossfadeAuto,
            description: '${settings.crossfadeDuration}s',
            type: ControllerType.slider,
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
              label: '${settings.crossfadeDuration}s',
              onChanged: (val) => settings.setCrossfadeDuration(val.round()),
            ),
          ),
          const Divider(),
          SettingRow(
            title: strings.npCrossfadeManual,
            description: '${settings.crossfadeManualDuration}s',
            type: ControllerType.slider,
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
              label: '${settings.crossfadeManualDuration}s',
              onChanged: (val) =>
                  settings.setCrossfadeManualDuration(val.round()),
            ),
          ),
          const Divider(),
          SettingRow(
            title: strings.sCrossfadeCurve,
            description: strings.sCrossfadeCurveDesc,
            type: ControllerType.complex,
            child: Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: SegmentedButton<CrossfadeCurve>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment<CrossfadeCurve>(
                    value: CrossfadeCurve.equalPower,
                    label: Text(
                      strings.sCrossfadeCurveEqualPower,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  ButtonSegment<CrossfadeCurve>(
                    value: CrossfadeCurve.linear,
                    label: Text(
                      strings.sCrossfadeCurveLinear,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
                selected: {settings.crossfadeCurve},
                onSelectionChanged: (newSelection) =>
                    settings.setCrossfadeCurve(newSelection.first),
              ),
            ),
          ),
          const Divider(),
          SettingRow(
            title: strings.sReplayGainMode,
            description: strings.sReplayGainModeDesc,
            type: ControllerType.switchCtrl,
            child: Switch(
              value: settings.volumeNormalization,
              onChanged: (val) => settings.setVolumeNormalization(val),
            ),
          ),
          const Divider(),
          SettingRow(
            title: strings.sSkipSilence,
            description: strings.sSkipSilenceDesc,
            type: ControllerType.switchCtrl,
            child: Switch(
              value: settings.skipSilence,
              onChanged: (val) => settings.setSkipSilence(val),
            ),
          ),
          const Divider(),
          SettingRow(
            title: strings.sLimiter,
            description: strings.sLimiterDesc,
            type: ControllerType.switchCtrl,
            child: Switch(
              value: settings.limiterEnabled,
              onChanged: (val) => settings.setLimiter(val),
            ),
          ),
          const Divider(),
          SettingRow(
            title: strings.sMonoAudio,
            description: strings.sMonoAudioDesc,
            type: ControllerType.switchCtrl,
            child: Switch(
              value: settings.mono,
              onChanged: (val) => settings.setMono(val),
            ),
          ),
          const Divider(),
          SettingRow(
            title: strings.sGaplessPlayback,
            description: strings.sGaplessPlaybackDesc,
            type: ControllerType.switchCtrl,
            child: const Switch(value: true, onChanged: null),
          ),
          const Divider(),
          SettingRow(
            title: strings.sPauseOnDeviceChange,
            description: strings.sPauseOnDeviceChangeDesc,
            type: ControllerType.switchCtrl,
            child: Switch(
              value: settings.pauseOnDeviceChange,
              onChanged: (val) => settings.setPauseOnDeviceChange(val),
            ),
          ),
        ],
      ),
    );
  }
}
