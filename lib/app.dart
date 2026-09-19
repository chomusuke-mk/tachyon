import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';
import 'package:tachyon/features/shell/tachyon_shell.dart';
import 'package:tachyon/shared/theme/app_theme.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();

    return MaterialApp(
      title: 'Tachyon',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: TachyonTheme.lightTheme,
      darkTheme: TachyonTheme.darkTheme,
      home: const TachyonShell(),
    );
  }
}
