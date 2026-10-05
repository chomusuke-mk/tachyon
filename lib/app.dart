import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';
import 'package:tachyon/features/shell/tachyon_shell.dart';
import 'package:tachyon/shared/theme/app_theme.dart';
import 'package:tachyon/shared/widgets/desktop_back_navigation_handler.dart';

class App extends StatelessWidget {
  const App({super.key});

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Tachyon',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: TachyonTheme.lightTheme,
      darkTheme: TachyonTheme.darkTheme,
      builder: (context, child) {
        return DesktopBackNavigationHandler(
          navigatorKey: navigatorKey,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const TachyonShell(),
    );
  }
}
