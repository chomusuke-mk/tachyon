import 'package:flutter/material.dart';
import 'package:miniaudio_player/miniaudio_player.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';

/// Stereo & Spatial Audio Processing Card.
///
/// Features:
/// - Continuous stereo balance control (-1.0 Left to +1.0 Right).
/// - Spatializer width expansion (0.0x Mono to 2.0x Ultra-wide).
/// - Bauer stereophonic-to-binaural crossfeed filter (bs2b) for headphone listening.
class SpatialAudioEffectCard extends StatelessWidget {
  const SpatialAudioEffectCard({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final strings = context.watch<LocaleController>().localeStrings;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final balance = settings.balance;
    final spatializerWidth = settings.spatializerWidth;

    final String balanceLabel;
    if (balance == 0.0) {
      balanceLabel = strings.sStereoBalanceCenter;
    } else if (balance < 0.0) {
      balanceLabel = 'L ${(-balance * 100).round()}%';
    } else {
      balanceLabel = 'R ${(balance * 100).round()}%';
    }

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
            // Section Header
            Row(
              children: [
                Icon(
                  Icons.headphones_rounded,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    strings.sAudioDspSection,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Stereo Balance
            Row(
              children: [
                Expanded(
                  child: Text(
                    strings.sStereoBalance,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
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
                    balanceLabel,
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
                  tooltip: strings.sStereoBalanceCenter,
                  onPressed: () => settings.setBalance(0.0),
                  iconSize: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
                Expanded(
                  child: Slider.adaptive(
                    value: balance.clamp(-1.0, 1.0),
                    min: -1.0,
                    max: 1.0,
                    divisions: 40,
                    onChanged: (val) => settings.setBalance(val),
                  ),
                ),
              ],
            ),
            const Divider(height: 16),

            // Stereo Width (Spatializer)
            Row(
              children: [
                Expanded(
                  child: Text(
                    strings.sSpatializer,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
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
                    '${spatializerWidth.toStringAsFixed(2)}x',
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
                  onPressed: () => settings.setSpatializer(1.0),
                  iconSize: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
                Expanded(
                  child: Slider.adaptive(
                    value: spatializerWidth.clamp(0.0, 2.0),
                    min: 0.0,
                    max: 2.0,
                    divisions: 40,
                    onChanged: (val) => settings.setSpatializer(val),
                  ),
                ),
              ],
            ),
            const Divider(height: 16),

            // Bauer Crossfeed Dropdown
            LayoutBuilder(
              builder: (context, constraints) {
                final bool isNarrow = constraints.maxWidth < 360;
                final dropdownWidget = Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.45,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: DropdownButton<CrossfeedMode>(
                    value: settings.crossfeedMode,
                    underline: const SizedBox(),
                    borderRadius: BorderRadius.circular(12),
                    isDense: true,
                    isExpanded: true,
                    items: [
                      DropdownMenuItem(
                        value: CrossfeedMode.off,
                        child: Text(
                          strings.sCrossfeedOff,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: CrossfeedMode.moffatBauer,
                        child: Text(
                          strings.sCrossfeedMoffat,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: CrossfeedMode.chuMoy,
                        child: Text(
                          strings.sCrossfeedChumoy,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        settings.setCrossfeed(val);
                      }
                    },
                  ),
                );

                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.sCrossfeed,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(width: double.infinity, child: dropdownWidget),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        strings.sCrossfeed,
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
                      constraints: const BoxConstraints(maxWidth: 190),
                      child: dropdownWidget,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
