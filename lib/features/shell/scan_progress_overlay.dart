import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/features/library/domain/scan_progress.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';

/// Floating rounded-rectangle overlay showing real-time library scan progress
/// with Gaussian blur, stage label, circular progress, and a square cancel/stop button.
class ScanProgressOverlay extends StatelessWidget {
  const ScanProgressOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryController>();

    return ValueListenableBuilder<ScanProgress>(
      valueListenable: library.scanProgressListenable,
      builder: (context, progress, _) {
        if (!progress.isRunning) {
          return const SizedBox.shrink();
        }

        final strings = context.watch<LocaleController>().localeStrings;
        final colorScheme = Theme.of(context).colorScheme;

        final stageText = strings.scanStageText(progress.stage);
        final label = progress.progressLabel;
        final displayText = (label != null && label.isNotEmpty)
            ? '$stageText $label'
            : stageText;

        return RepaintBoundary(
          child: Material(
            type: MaterialType.transparency,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        displayText,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          value: progress.progressValue,
                          strokeWidth: 2.2,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: strings.scanCancelTooltip,
                        child: Material(
                          color: colorScheme.surfaceContainerHighest.withValues(
                            alpha: 0.6,
                          ),
                          borderRadius: BorderRadius.circular(6),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(6),
                            onTap: () => library.cancelScan(),
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: Icon(
                                Icons.stop_rounded,
                                size: 16,
                                color: colorScheme.error,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
