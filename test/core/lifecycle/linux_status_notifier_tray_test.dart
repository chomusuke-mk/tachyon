import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/core/lifecycle/linux_status_notifier_tray.dart';
import 'package:tachyon/core/lifecycle/window_control_bridge.dart';

void main() {
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
