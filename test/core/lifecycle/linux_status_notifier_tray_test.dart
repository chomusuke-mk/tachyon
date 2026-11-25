import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/core/lifecycle/linux_status_notifier_tray.dart';
import 'package:tachyon/core/lifecycle/window_control_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LinuxStatusNotifierTray D-Bus Objects Unit Tests', () {
    late List<DesktopTrayAction> dispatchedActions;
    late LinuxStatusNotifierTray tray;
    late TachyonStatusNotifierObject sniObject;
    late TachyonDBusMenuObject menuObject;

    setUp(() {
      dispatchedActions = <DesktopTrayAction>[];
      tray = LinuxStatusNotifierTray(
        onAction: dispatchedActions.add,
        processId: 4242,
      );
      sniObject = TachyonStatusNotifierObject(tray);
      menuObject = TachyonDBusMenuObject(tray);
    });

    tearDown(() async {
      await tray.dispose();
    });

    test('StatusNotifierObject exposes identity, Menu object path, ItemIsMenu=false, and dynamic ToolTip', () async {
      await tray.updateState(
        const TrayPresentationState(
          tooltipTitle: 'Stargazer',
          tooltipSubtitle: 'Rainbow',
          fullTooltip: 'Stargazer — Rainbow',
          hasTrack: true,
          isPlaying: true,
          isShuffled: true,
        ),
      );

      final response = await sniObject.getAllProperties(
        'org.kde.StatusNotifierItem',
      );
      expect(response, isA<DBusGetAllPropertiesResponse>());
      final props = (response as DBusGetAllPropertiesResponse)
          .values[0]
          .asStringVariantDict();

      expect(props['Category']?.asString(), equals('ApplicationStatus'));
      expect(props['Id']?.asString(), equals('dev.chomusuke.tachyon'));
      expect(props['Title']?.asString(), equals('Tachyon'));
      expect(props['Status']?.asString(), equals('Active'));
      expect(props['ItemIsMenu']?.asBoolean(), isFalse);
      expect(props['Menu']?.asObjectPath().value, equals('/MenuBar'));

      final tooltip = props['ToolTip']?.asStruct();
      expect(tooltip, isNotNull);
      expect(tooltip!.length, equals(4));
      expect(tooltip[2].asString(), equals('Stargazer'));
      expect(tooltip[3].asString(), equals('Rainbow'));
      expect(props['IconThemePath']?.asString(), equals(''));
      expect(props['IconName']?.asString(), equals('audio-x-generic'));
      expect(props['IconPixmap']?.asArray(), isEmpty);
    });

    test('StatusNotifierObject prefers IconPixmap and clears IconName when pixmaps are present', () async {
      final customTray = LinuxStatusNotifierTray(
        onAction: dispatchedActions.add,
        processId: 4243,
        initialPixmaps: [
          TrayPixmapData(
            width: 24,
            height: 24,
            argbBytes: Uint8List(24 * 24 * 4),
          ),
          TrayPixmapData(
            width: 48,
            height: 48,
            argbBytes: Uint8List(48 * 48 * 4),
          ),
        ],
      );
      addTearDown(customTray.dispose);
      final customSni = TachyonStatusNotifierObject(customTray);

      final response = await customSni.getAllProperties(
        'org.kde.StatusNotifierItem',
      );
      final props = (response as DBusGetAllPropertiesResponse)
          .values[0]
          .asStringVariantDict();

      expect(props['IconName']?.asString(), equals(''));
      expect(props['IconThemePath']?.asString(), equals(''));

      final pixmaps = props['IconPixmap']?.asArray().toList();
      expect(pixmaps, hasLength(2));
      expect(pixmaps![0].asStruct()[0].asInt32(), equals(24));
      expect(pixmaps[0].asStruct()[1].asInt32(), equals(24));
      expect(
        pixmaps[0].asStruct()[2].asByteArray().length,
        equals(24 * 24 * 4),
      );
      expect(pixmaps[1].asStruct()[0].asInt32(), equals(48));
      expect(pixmaps[1].asStruct()[1].asInt32(), equals(48));
      expect(
        pixmaps[1].asStruct()[2].asByteArray().length,
        equals(48 * 48 * 4),
      );
    });

    test('preloadIcon decodes bundled icon_small.webp into rounded 24x24 and 48x48 ARGB32 pixmaps', () async {
      await tray.preloadIcon();

      expect(tray.iconPixmaps, hasLength(2));
      expect(tray.iconPixmaps[0].width, equals(24));
      expect(tray.iconPixmaps[0].height, equals(24));
      expect(tray.iconPixmaps[1].width, equals(48));
      expect(tray.iconPixmaps[1].height, equals(48));

      for (final pixmap in tray.iconPixmaps) {
        final bytes = pixmap.argbBytes;
        expect(bytes.length, equals(pixmap.width * pixmap.height * 4));
        // Rounded mask leaves corner (0, 0) transparent.
        expect(bytes[0], equals(0));
        // Center pixel is opaque with visible Tachyon color payload.
        final centerIdx =
            ((pixmap.height ~/ 2) * pixmap.width + (pixmap.width ~/ 2)) * 4;
        expect(bytes[centerIdx], equals(255));
        expect(
          bytes[centerIdx + 1] + bytes[centerIdx + 2] + bytes[centerIdx + 3],
          greaterThan(0),
        );
      }

      final response = await sniObject.getAllProperties(
        'org.kde.StatusNotifierItem',
      );
      final props = (response as DBusGetAllPropertiesResponse)
          .values[0]
          .asStringVariantDict();
      expect(props['IconName']?.asString(), equals(''));
      expect(props['IconPixmap']?.asArray().toList(), hasLength(2));
    });

    test('StatusNotifierObject handles Activate and SecondaryActivate clicks', () async {
      await sniObject.handleMethodCall(
        DBusMethodCall(
          sender: ':1.99',
          interface: 'org.kde.StatusNotifierItem',
          name: 'Activate',
          values: const [DBusInt32(10), DBusInt32(20)],
        ),
      );
      await sniObject.handleMethodCall(
        DBusMethodCall(
          sender: ':1.99',
          interface: 'org.kde.StatusNotifierItem',
          name: 'SecondaryActivate',
          values: const [DBusInt32(10), DBusInt32(20)],
        ),
      );

      expect(
        dispatchedActions,
        equals([DesktopTrayAction.restore, DesktopTrayAction.playPause]),
      );
    });

    test('DBusMenuObject GetLayout switches Play/Pause label, updates Shuffle radio toggle-state, and includes separator, Show Tachyon, Quit', () async {
      await tray.updateState(
        const TrayPresentationState(
          isPlaying: false,
          isShuffled: false,
          hasTrack: true,
          playLabel: 'Reproducir',
          pauseLabel: 'Pausar',
          nextLabel: 'Siguiente',
          previousLabel: 'Anterior',
          shuffleLabel: 'Aleatorio',
          showAppLabel: 'Mostrar Tachyon',
          quitLabel: 'Salir',
        ),
      );

      Future<Map<int, Map<String, DBusValue>>> fetchMenuItems() async {
        final res = await menuObject.handleMethodCall(
          DBusMethodCall(
            sender: ':1.99',
            interface: 'com.canonical.dbusmenu',
            name: 'GetLayout',
            values: [
              const DBusInt32(0),
              const DBusInt32(-1),
              DBusArray.string(const []),
            ],
          ),
        );
        expect(res, isA<DBusMethodSuccessResponse>());
        final success = res as DBusMethodSuccessResponse;
        expect(success.values[0], equals(DBusUint32(tray.menuRevision)));

        final root = success.values[1].asStruct();
        final children = root[2].asVariantArray();
        final items = <int, Map<String, DBusValue>>{};
        for (final child in children) {
          final node = child.asStruct();
          final id = node[0].asInt32();
          final props = node[1].asStringVariantDict();
          items[id] = props;
        }
        return items;
      }

      final pausedItems = await fetchMenuItems();
      expect(pausedItems.keys, containsAll([
        TachyonDBusMenuObject.playPauseId,
        TachyonDBusMenuObject.nextId,
        TachyonDBusMenuObject.previousId,
        TachyonDBusMenuObject.shuffleId,
        TachyonDBusMenuObject.separatorId,
        TachyonDBusMenuObject.showAppId,
        TachyonDBusMenuObject.quitId,
      ]));
      expect(
        pausedItems[TachyonDBusMenuObject.playPauseId]?['label']?.asString(),
        equals('Reproducir'),
      );
      expect(
        pausedItems[TachyonDBusMenuObject.shuffleId]?['toggle-type']
            ?.asString(),
        equals('radio'),
      );
      expect(
        pausedItems[TachyonDBusMenuObject.shuffleId]?['toggle-state']
            ?.asInt32(),
        equals(0),
      );
      expect(
        pausedItems[TachyonDBusMenuObject.separatorId]?['type']?.asString(),
        equals('separator'),
      );
      expect(
        pausedItems[TachyonDBusMenuObject.showAppId]?['label']?.asString(),
        equals('Mostrar Tachyon'),
      );
      expect(
        pausedItems[TachyonDBusMenuObject.quitId]?['label']?.asString(),
        equals('Salir'),
      );

      // Flip isPlaying & isShuffled -> label changes to Pausar and toggle-state becomes 1 (dot active).
      await tray.updateState(
        const TrayPresentationState(
          isPlaying: true,
          isShuffled: true,
          hasTrack: true,
          playLabel: 'Reproducir',
          pauseLabel: 'Pausar',
          nextLabel: 'Siguiente',
          previousLabel: 'Anterior',
          shuffleLabel: 'Aleatorio',
          showAppLabel: 'Mostrar Tachyon',
          quitLabel: 'Salir',
        ),
      );

      final playingItems = await fetchMenuItems();
      expect(
        playingItems[TachyonDBusMenuObject.playPauseId]?['label']?.asString(),
        equals('Pausar'),
      );
      expect(
        playingItems[TachyonDBusMenuObject.shuffleId]?['toggle-state']
            ?.asInt32(),
        equals(1),
      );
    });

    test('DBusMenuObject Event and EventGroup dispatch exact tray actions for every menu item', () async {
      final menuIds = [
        TachyonDBusMenuObject.playPauseId,
        TachyonDBusMenuObject.nextId,
        TachyonDBusMenuObject.previousId,
        TachyonDBusMenuObject.shuffleId,
        TachyonDBusMenuObject.showAppId,
        TachyonDBusMenuObject.quitId,
      ];

      for (final id in menuIds) {
        await menuObject.handleMethodCall(
          DBusMethodCall(
            sender: ':1.99',
            interface: 'com.canonical.dbusmenu',
            name: 'Event',
            values: [
              DBusInt32(id),
              const DBusString('clicked'),
              const DBusVariant(DBusString('')),
              const DBusUint32(0),
            ],
          ),
        );
      }

      expect(
        dispatchedActions,
        equals([
          DesktopTrayAction.playPause,
          DesktopTrayAction.next,
          DesktopTrayAction.previous,
          DesktopTrayAction.toggleShuffle,
          DesktopTrayAction.restore,
          DesktopTrayAction.quit,
        ]),
      );

      dispatchedActions.clear();

      await menuObject.handleMethodCall(
        DBusMethodCall(
          sender: ':1.99',
          interface: 'com.canonical.dbusmenu',
          name: 'EventGroup',
          values: [
            DBusArray(
              DBusSignature('(isvu)'),
              [
                DBusStruct([
                  const DBusInt32(TachyonDBusMenuObject.nextId),
                  const DBusString('clicked'),
                  const DBusVariant(DBusString('')),
                  const DBusUint32(0),
                ]),
                DBusStruct([
                  const DBusInt32(TachyonDBusMenuObject.shuffleId),
                  const DBusString('clicked'),
                  const DBusVariant(DBusString('')),
                  const DBusUint32(0),
                ]),
              ],
            ),
          ],
        ),
      );

      expect(
        dispatchedActions,
        equals([DesktopTrayAction.next, DesktopTrayAction.toggleShuffle]),
      );
    });
  });
}
