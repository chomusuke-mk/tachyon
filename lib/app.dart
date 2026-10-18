import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/core/playback/system_media_service.dart';
import 'package:tachyon/features/permissions/presentation/permissions_gate.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';
import 'package:tachyon/features/shell/tachyon_shell.dart';
import 'package:tachyon/shared/theme/app_theme.dart';
import 'package:tachyon/shared/utils/toast_utils.dart';
import 'package:tachyon/shared/widgets/app_background.dart';
import 'package:tachyon/shared/widgets/desktop_shortcuts_handler.dart';

class App extends StatelessWidget {
  /// Whether all required runtime permissions were already granted at startup.
  final bool permissionsGranted;

  const App({super.key, this.permissionsGranted = true});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final hasCustomBg = AppBackground.fileExists(settings.customBackgroundPath);

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
      navigatorKey: ToastUtils.navigatorKey,
      title: 'Tachyon',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: lightTheme,
      darkTheme: darkTheme,
      builder: (context, child) {
        return ValueListenableBuilder<bool>(
          valueListenable: SystemMediaService.isMinimizedListenable,
          child: child,
          builder: (context, isMinimized, routeChild) {
            return DesktopShortcutsHandler(
              navigatorKey: ToastUtils.navigatorKey,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasCustomBg && !isMinimized)
                    AppBackground(
                      imagePath: settings.customBackgroundPath,
                      blurSigma: settings.backgroundBlurSigma,
                      dimOpacity: settings.backgroundDimOpacity,
                    ),
                  routeChild ?? const SizedBox.shrink(),
                ],
              ),
            );
          },
        );
      },
      home: PermissionsGate(
        initiallyGranted: permissionsGranted,
        child: const TachyonShell(),
      ),
    );
  }
}
