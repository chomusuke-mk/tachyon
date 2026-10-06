import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';
import 'package:tachyon/features/shell/tachyon_shell.dart';
import 'package:tachyon/shared/theme/app_theme.dart';
import 'package:tachyon/shared/widgets/app_background.dart';
import 'package:tachyon/shared/widgets/desktop_shortcuts_handler.dart';

class App extends StatelessWidget {
  const App({super.key});

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final hasCustomBg = settings.customBackgroundPath != null &&
        File(settings.customBackgroundPath!).existsSync();

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
      navigatorKey: navigatorKey,
      title: 'Tachyon',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: lightTheme,
      darkTheme: darkTheme,
      builder: (context, child) {
        return DesktopShortcutsHandler(
          navigatorKey: navigatorKey,
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
        );
      },
      home: const TachyonShell(),
    );
  }
}
