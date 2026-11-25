import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/core/lifecycle/app_lifecycle_controller.dart';
import 'package:tachyon/core/lifecycle/app_lifecycle_mode.dart';
import 'package:tachyon/core/logging/app_logger.dart';
import 'package:tachyon/features/permissions/presentation/permissions_gate.dart';
import 'package:tachyon/features/settings/presentation/controllers/settings_controller.dart';
import 'package:tachyon/features/shell/presentation/widgets/desktop_window_bar.dart';
import 'package:tachyon/features/shell/presentation/screens/tachyon_shell.dart';
import 'package:tachyon/shared/theme/app_theme.dart';
import 'package:tachyon/shared/widgets/app_background.dart';
import 'package:tachyon/shared/widgets/desktop_shortcuts_handler.dart';

/// Root Flutter widget of the Tachyon music player.
///
/// Reacts to [AppLifecycleController.modeListenable] to pause tickers and
/// heavy background visuals while [AppLifecycleMode.suspended], and completely
/// unmounts the UI tree to [SizedBox.shrink] during [AppLifecycleMode.background].
class App extends StatefulWidget {
  /// Global navigator key shared with overlay services such as toast notifications.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// Whether all required runtime permissions were already granted at startup.
  final bool permissionsGranted;

  /// Creates the root [App] widget.
  const App({super.key, this.permissionsGranted = true});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  static const _log = ScopedLogger('App');

  late bool _permissionsGranted = widget.permissionsGranted;
  AppLifecycleMode? _lastLoggedMode;
  bool? _lastLoggedHasCustomBg;
  bool? _lastLoggedShowDesktopBar;

  @override
  void didUpdateWidget(covariant App oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.permissionsGranted && !_permissionsGranted) {
      _log.d('Permissions updated via widget: false -> true');
      _permissionsGranted = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.read<SettingsController>();
    final lifecycle = Provider.of<AppLifecycleController?>(
      context,
      listen: false,
    );
    final ValueListenable<AppLifecycleMode> modeListenable =
        lifecycle?.modeListenable ??
        const _FixedValueListenable<AppLifecycleMode>(AppLifecycleMode.active);

    return ValueListenableBuilder<AppLifecycleMode>(
      valueListenable: modeListenable,
      builder: (context, mode, _) {
        if (mode == AppLifecycleMode.background) {
          if (_lastLoggedMode != mode) {
            _log.d(
              'build mode=${mode.name} (prev=${_lastLoggedMode?.name ?? '<init>'}) -> unmounted to SizedBox.shrink',
            );
            _lastLoggedMode = mode;
            _lastLoggedHasCustomBg = null;
            _lastLoggedShowDesktopBar = null;
          }
          _log.vLazy(() => 'App.build background -> SizedBox.shrink()');
          return const SizedBox.shrink();
        }

        final isActive = mode == AppLifecycleMode.active;
        final showDesktopBar =
            lifecycle?.windowBridge.usesFlutterTitleBar ?? false;

        return ListenableBuilder(
          listenable: settings.themeListenable,
          builder: (context, _) {
            final hasCustomBg = AppBackground.fileExists(
              settings.customBackgroundPath,
            );
            final mountAppBg = hasCustomBg && isActive;
            if (_lastLoggedMode != mode ||
                _lastLoggedHasCustomBg != hasCustomBg ||
                _lastLoggedShowDesktopBar != showDesktopBar) {
              _log.d(
                'renderTree prevMode=${_lastLoggedMode?.name ?? '<init>'} -> mode=${mode.name} '
                'isActive=$isActive tickerEnabled=$isActive hasCustomBg=$hasCustomBg '
                'appBackgroundMounted=$mountAppBg showDesktopBar=$showDesktopBar '
                'themeMode=${settings.themeMode.name} oled=${settings.isOledMode}',
              );
              _lastLoggedMode = mode;
              _lastLoggedHasCustomBg = hasCustomBg;
              _lastLoggedShowDesktopBar = showDesktopBar;
            }
            _log.vLazy(
              () =>
                  'App.build rebuild mode=${mode.name} isActive=$isActive hasCustomBg=$hasCustomBg appBgMounted=$mountAppBg',
            );

            final lightTheme = TachyonTheme.buildLightTheme(
              seedColor: settings.accentColor,
              hasCustomBackground: hasCustomBg,
            );
            final darkTheme = settings.isOledMode
                ? TachyonTheme.buildOledTheme(
                    seedColor: settings.accentColor,
                    hasCustomBackground: hasCustomBg,
                  )
                : TachyonTheme.buildDarkTheme(
                    seedColor: settings.accentColor,
                    hasCustomBackground: hasCustomBg,
                  );

            return MaterialApp(
              navigatorKey: App.navigatorKey,
              title: 'Tachyon',
              debugShowCheckedModeBanner: false,
              themeMode: settings.themeMode,
              theme: lightTheme,
              darkTheme: darkTheme,
              builder: (context, child) {
                return TickerMode(
                  enabled: isActive,
                  child: DesktopShortcutsHandler(
                    navigatorKey: App.navigatorKey,
                    child: Column(
                      children: [
                        if (showDesktopBar) const DesktopWindowBar(),
                        Expanded(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (hasCustomBg && isActive)
                                AppBackground(
                                  imagePath: settings.customBackgroundPath,
                                  blurSigma: settings.backgroundBlurSigma,
                                  dimOpacity: settings.backgroundDimOpacity,
                                ),
                              child ?? const SizedBox.shrink(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              home: PermissionsGate(
                initiallyGranted: _permissionsGranted,
                onGranted: () {
                  _log.d('PermissionsGate granted callback (mounted=$mounted)');
                  if (mounted) {
                    setState(() => _permissionsGranted = true);
                  } else {
                    _permissionsGranted = true;
                  }
                },
                child: const TachyonShell(),
              ),
            );
          },
        );
      },
    );
  }
}

class _FixedValueListenable<T> extends ValueListenable<T> {
  @override
  final T value;

  const _FixedValueListenable(this.value);

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
