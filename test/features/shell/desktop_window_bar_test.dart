import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jsonc/jsonc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tachyon/core/lifecycle/app_lifecycle_controller.dart';
import 'package:tachyon/core/lifecycle/app_lifecycle_mode.dart';
import 'package:tachyon/core/lifecycle/window_control_bridge.dart';
import 'package:tachyon/features/locales/data/locale_repository.dart';
import 'package:tachyon/features/locales/presentation/controllers/locale_controller.dart';
import 'package:tachyon/features/shell/presentation/widgets/desktop_window_bar.dart';

class _TestLocaleRepository extends LocaleRepository {
  @override
  Future<Map<String, String>> getLocaleStrings(String localeCode) async {
    final file = File('i18n/$localeCode.jsonc');
    if (!file.existsSync()) return const <String, String>{};
    final decoded = jsoncDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return decoded.map((k, v) => MapEntry(k, v.toString()));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DesktopWindowBar Widget Tests', () {
    late SharedPreferences prefs;
    late LocaleController localeController;
    late List<String> invokedMethods;
    late int closeCount;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      localeController = LocaleController(_TestLocaleRepository(), 'en');
      await localeController.whenReady;
      invokedMethods = <String>[];
      closeCount = 0;
    });

    tearDown(() {
      localeController.dispose();
    });

    Widget buildSubject(AppLifecycleController lifecycle) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<LocaleController>.value(
            value: localeController,
          ),
          ChangeNotifierProvider<AppLifecycleController>.value(
            value: lifecycle,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: Column(children: [DesktopWindowBar()])),
        ),
      );
    }

    testWidgets(
      'renders localized caption buttons and dispatches background, minimize, maximize/restore, and close',
      (tester) async {
        final bridge = WindowControlBridge(
          attachChannelHandler: false,
          isDesktopOverride: true,
          usesFlutterTitleBarOverride: true,
          invokeOverride: <T>(String method, [Object? args]) async {
            invokedMethods.add(method);
            return null;
          },
        );
        final lifecycle = AppLifecycleController(
          windowBridge: bridge,
          startTrimmerOnActive: false,
          observeFlutterLifecycle: false,
          onCloseRequested: () async {
            closeCount++;
          },
        );
        addTearDown(() {
          lifecycle.dispose();
          bridge.dispose();
        });

        // Exercise caption bar on non-macOS desktop so all four buttons render.
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        try {
          await tester.pumpWidget(buildSubject(lifecycle));
          await tester.pump();

          expect(find.text('Tachyon'), findsOneWidget);
          expect(find.byKey(const Key('win_btn_background')), findsOneWidget);
          expect(find.byKey(const Key('win_btn_minimize')), findsOneWidget);
          expect(find.byKey(const Key('win_btn_maximize')), findsOneWidget);
          expect(find.byKey(const Key('win_btn_close')), findsOneWidget);
          expect(find.byTooltip('Send to background'), findsOneWidget);
          expect(find.byTooltip('Minimize'), findsOneWidget);
          expect(find.byTooltip('Maximize'), findsOneWidget);
          expect(find.byTooltip('Close'), findsOneWidget);

          // Maximize state flip updates icon & tooltip to Restore.
          bridge.simulateWindowStateForTest(
            const DesktopWindowState(
              isMaximized: true,
              isFocused: true,
            ),
          );
          await tester.pump();
          expect(find.byTooltip('Restore'), findsOneWidget);
          expect(find.byIcon(Icons.filter_none_rounded), findsOneWidget);

          await tester.tap(find.byKey(const Key('win_btn_maximize')));
          await tester.pump();
          expect(invokedMethods, contains('toggleMaximize'));

          await tester.tap(find.byKey(const Key('win_btn_minimize')));
          await tester.pump();
          expect(invokedMethods, contains('minimize'));
          expect(lifecycle.mode, equals(AppLifecycleMode.suspended));

          await lifecycle.enterActive();
          await tester.tap(find.byKey(const Key('win_btn_background')));
          await tester.pump();
          expect(lifecycle.mode, equals(AppLifecycleMode.background));
          expect(invokedMethods, contains('enterBackgroundMode'));

          await tester.tap(find.byKey(const Key('win_btn_close')));
          await tester.pump();
          expect(closeCount, equals(1));
          expect(prefs, isNotNull);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  });
}
