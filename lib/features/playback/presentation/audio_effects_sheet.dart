import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/widgets/effects/audio_enhancements_card.dart';
import 'package:tachyon/features/playback/presentation/widgets/effects/equalizer_effect_card.dart';
import 'package:tachyon/features/playback/presentation/widgets/effects/playback_tuning_card.dart';
import 'package:tachyon/features/playback/presentation/widgets/effects/reverb_effect_card.dart';
import 'package:tachyon/features/playback/presentation/widgets/effects/spatial_audio_effect_card.dart';

/// Modal bottom sheet or dialog presenting advanced audio controls and effects:
/// - Playback Tuning (Speed, Pitch, Volume Boost)
/// - Crossfade Transitions (Auto duration, Manual skip duration)
/// - Audio Enhancements (Volume Normalization, Skip Silence, True-Peak Limiter, Mono Audio)
/// - Stereo & Spatial Processing (Stereo Balance, Stereo Width, Bauer Crossfeed bs2b)
/// - Algorithmic Studio Reverb (Freeverb model with room size, damping, width, wet/dry)
/// - 10-Band Graphic & Parametric Equalizer with RBJ response curve and preamp gain
class AudioEffectsSheet extends StatelessWidget {
  final bool isDialog;

  const AudioEffectsSheet({super.key, this.isDialog = false});

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleController>().localeStrings;
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
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.4,
                      ),
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
                      color: colorScheme.primaryContainer.withValues(
                        alpha: 0.5,
                      ),
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

              const Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Card 1: Playback Tuning (Speed, Pitch, Volume)
                      PlaybackTuningCard(),
                      SizedBox(height: 12),

                      // Card 2: Crossfade Durations
                      CrossfadeDurationsCard(),
                      SizedBox(height: 12),

                      // Card 3: Audio Enhancements (Volume Normalization, Skip Silence, Limiter, Mono)
                      AudioEnhancementsCard(),
                      SizedBox(height: 12),

                      // Card 4: Stereo & Spatial Processing
                      SpatialAudioEffectCard(),
                      SizedBox(height: 12),

                      // Card 5: Studio Reverb
                      ReverbEffectCard(),
                      SizedBox(height: 12),

                      // Card 6: 10-Band Graphic Equalizer
                      EqualizerEffectCard(),
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
