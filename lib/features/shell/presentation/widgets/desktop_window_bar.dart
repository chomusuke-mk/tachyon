import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/core/lifecycle/app_lifecycle_controller.dart';
import 'package:tachyon/core/lifecycle/app_lifecycle_mode.dart';
import 'package:tachyon/core/logging/app_logger.dart';
import 'package:tachyon/features/locales/presentation/controllers/locale_controller.dart';

/// Custom desktop window title bar rendered when the native platform runner
/// delegates window chrome to Flutter (Windows, macOS, and undecorated Linux).
///
/// Displays the application title, drag/double-click-maximize surface, and
/// window controls: Send to background, Minimize, Maximize / Restore, and Close.
class DesktopWindowBar extends StatelessWidget {
  static const _log = ScopedLogger('WindowBar');

  /// Standard height of the desktop window control strip.
  static const double barHeight = 36.0;

  /// Creates a [DesktopWindowBar].
  const DesktopWindowBar({super.key});

  @override
  Widget build(BuildContext context) {
    final lifecycle = Provider.of<AppLifecycleController?>(
      context,
      listen: false,
    );
    if (lifecycle == null) return const SizedBox.shrink();

    final strings = context.watch<LocaleController>().localeStrings;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isMacOS =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

    String labelOrFallback(String localized, String fallback) =>
        localized.isNotEmpty ? localized : fallback;

    return Material(
      color: colorScheme.surfaceContainerLow,
      child: SizedBox(
        height: barHeight,
        child: ValueListenableBuilder<DesktopWindowState>(
          valueListenable: lifecycle.windowBridge.windowStateListenable,
          builder: (context, windowState, _) {
            final isMaximized = windowState.isMaximized;
            _log.vLazy(
              () =>
                  'DesktopWindowBar.build maximized=$isMaximized minimized=${windowState.isMinimized} focused=${windowState.isFocused}',
            );
            return Row(
              children: [
                if (isMacOS) const SizedBox(width: 74),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (_) {
                      _log.d('Drag initiated on title bar');
                      lifecycle.windowBridge.startWindowDrag();
                    },
                    onDoubleTap: () {
                      _log.d('Title bar double-tapped -> toggleMaximize');
                      lifecycle.toggleMaximizeWindow();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          if (!isMacOS) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Image.asset(
                                'assets/icon/icon_small.webp',
                                width: 18,
                                height: 18,
                                cacheWidth: 48,
                                cacheHeight: 48,
                                errorBuilder: (_, _, _) => Icon(
                                  Icons.music_note_rounded,
                                  size: 16,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            'Tachyon',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                _WindowCaptionButton(
                  key: const Key('win_btn_background'),
                  icon: Icons.vertical_align_bottom_rounded,
                  tooltip: labelOrFallback(
                    strings.winSendToBackground,
                    'Send to background',
                  ),
                  iconColor: colorScheme.onSurfaceVariant,
                  hoverColor: colorScheme.primary.withValues(alpha: 0.14),
                  onPressed: () {
                    _log.d('Caption button pressed: sendToBackground');
                    lifecycle.enterBackground();
                  },
                ),
                if (!isMacOS) ...[
                  _WindowCaptionButton(
                    key: const Key('win_btn_minimize'),
                    icon: Icons.minimize_rounded,
                    tooltip: labelOrFallback(strings.winMinimize, 'Minimize'),
                    iconColor: colorScheme.onSurfaceVariant,
                    hoverColor: colorScheme.onSurface.withValues(alpha: 0.08),
                    onPressed: () {
                      _log.d('Caption button pressed: minimize');
                      lifecycle.minimizeWindow();
                    },
                  ),
                  _WindowCaptionButton(
                    key: const Key('win_btn_maximize'),
                    icon: isMaximized
                        ? Icons.filter_none_rounded
                        : Icons.crop_square_rounded,
                    iconSize: isMaximized ? 15 : 16,
                    tooltip: isMaximized
                        ? labelOrFallback(strings.winRestore, 'Restore')
                        : labelOrFallback(strings.winMaximize, 'Maximize'),
                    iconColor: colorScheme.onSurfaceVariant,
                    hoverColor: colorScheme.onSurface.withValues(alpha: 0.08),
                    onPressed: () {
                      _log.d('Caption button pressed: toggleMaximize');
                      lifecycle.toggleMaximizeWindow();
                    },
                  ),
                  _WindowCaptionButton(
                    key: const Key('win_btn_close'),
                    icon: Icons.close_rounded,
                    tooltip: labelOrFallback(strings.winClose, 'Close'),
                    iconColor: colorScheme.onSurfaceVariant,
                    hoverColor: colorScheme.error.withValues(alpha: 0.85),
                    hoverIconColor: colorScheme.onError,
                    onPressed: () {
                      _log.d('Caption button pressed: close');
                      lifecycle.closeApplication();
                    },
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _WindowCaptionButton extends StatefulWidget {
  final IconData icon;
  final double iconSize;
  final String tooltip;
  final Color iconColor;
  final Color hoverColor;
  final Color? hoverIconColor;
  final VoidCallback onPressed;

  const _WindowCaptionButton({
    super.key,
    required this.icon,
    this.iconSize = 18,
    required this.tooltip,
    required this.iconColor,
    required this.hoverColor,
    this.hoverIconColor,
    required this.onPressed,
  });

  @override
  State<_WindowCaptionButton> createState() => _WindowCaptionButtonState();
}

class _WindowCaptionButtonState extends State<_WindowCaptionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: InkWell(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 44,
            height: DesktopWindowBar.barHeight,
            color: _hovered ? widget.hoverColor : Colors.transparent,
            alignment: Alignment.center,
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: _hovered && widget.hoverIconColor != null
                  ? widget.hoverIconColor
                  : widget.iconColor,
            ),
          ),
        ),
      ),
    );
  }
}
