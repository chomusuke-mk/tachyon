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
/// Reacts to [AppLifecycleController.modeListenable] to pause tickers during
/// [AppLifecycleMode.suspended] without tearing down [MaterialApp] or
/// [AppBackground], and completely unmounts the UI tree to [SizedBox.shrink]
/// during [AppLifecycleMode.background].
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
  ValueListenable<AppLifecycleMode>? _modeListenable;
  bool _isBackground = false;
  bool? _lastLoggedIsBackground;
  bool? _lastLoggedHasCustomBg;
  bool? _lastLoggedShowDesktopBar;
  bool? _lastLoggedTickerActive;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final lifecycle = Provider.of<AppLifecycleController?>(
      context,
      listen: false,
    );
    final ValueListenable<AppLifecycleMode> nextListenable =
        lifecycle?.modeListenable ??
        const _FixedValueListenable<AppLifecycleMode>(AppLifecycleMode.active);
    if (!identical(_modeListenable, nextListenable)) {
      _modeListenable?.removeListener(_onLifecycleModeChanged);
      _modeListenable = nextListenable;
      _modeListenable!.addListener(_onLifecycleModeChanged);
      _isBackground = _modeListenable!.value == AppLifecycleMode.background;
    }
  }

  void _onLifecycleModeChanged() {
    final nextIsBackground =
        _modeListenable?.value == AppLifecycleMode.background;
    if (nextIsBackground != _isBackground && mounted) {
      _log.d(
        'App.mode changed: isBackground=$_isBackground -> $nextIsBackground '
        '(mode=${_modeListenable?.value.name})',
      );
      setState(() => _isBackground = nextIsBackground);
    }
  }

  @override
  void didUpdateWidget(covariant App oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.permissionsGranted && !_permissionsGranted) {
      _log.d('Permissions updated via widget: false -> true');
      _permissionsGranted = true;
    }
  }

  @override
  void dispose() {
    _modeListenable?.removeListener(_onLifecycleModeChanged);
    _modeListenable = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.read<SettingsController>();
    final lifecycle = Provider.of<AppLifecycleController?>(
      context,
      listen: false,
    );
    final ValueListenable<AppLifecycleMode> modeListenable =
        _modeListenable ??
        const _FixedValueListenable<AppLifecycleMode>(AppLifecycleMode.active);

    if (_isBackground) {
      if (_lastLoggedIsBackground != true) {
        _log.d('build mode=background -> unmounted to SizedBox.shrink');
        _lastLoggedIsBackground = true;
        _lastLoggedHasCustomBg = null;
        _lastLoggedShowDesktopBar = null;
        _lastLoggedTickerActive = null;
      }
      _log.vLazy(() => 'App.build background -> SizedBox.shrink()');
      return const SizedBox.shrink();
    }
    _lastLoggedIsBackground = false;

    final showDesktopBar = lifecycle?.windowBridge.usesFlutterTitleBar ?? false;

    return ListenableBuilder(
      listenable: settings.themeListenable,
      builder: (context, _) {
        final hasCustomBg = AppBackground.fileExists(
          settings.customBackgroundPath,
        );
        if (_lastLoggedHasCustomBg != hasCustomBg ||
            _lastLoggedShowDesktopBar != showDesktopBar) {
          _log.d(
            'renderTree mode=${modeListenable.value.name} hasCustomBg=$hasCustomBg '
            'appBackgroundMounted=$hasCustomBg showDesktopBar=$showDesktopBar '
            'themeMode=${settings.themeMode.name} oled=${settings.isOledMode}',
          );
          _lastLoggedHasCustomBg = hasCustomBg;
          _lastLoggedShowDesktopBar = showDesktopBar;
        }
        _log.vLazy(
          () =>
              'App.build rebuild mode=${modeListenable.value.name} hasCustomBg=$hasCustomBg',
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
            final appContent = DesktopShortcutsHandler(
              navigatorKey: App.navigatorKey,
              child: Column(
                children: [
                  if (showDesktopBar) const DesktopWindowBar(),
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (hasCustomBg)
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
            );

            return ValueListenableBuilder<AppLifecycleMode>(
              valueListenable: modeListenable,
              child: appContent,
              builder: (context, mode, staticChild) {
                final isActive = mode == AppLifecycleMode.active;
                if (_lastLoggedTickerActive != isActive) {
                  _log.d(
                    'TickerMode updated: enabled=$isActive (mode=${mode.name})',
                  );
                  _lastLoggedTickerActive = isActive;
                }
                return TickerMode(
                  enabled: isActive,
                  child: staticChild!,
                );
              },
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
