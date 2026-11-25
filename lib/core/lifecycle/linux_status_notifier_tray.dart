import 'dart:async';
import 'dart:ui' as ui;

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:tachyon/core/lifecycle/window_control_bridge.dart';

/// Snapshot of localized labels and playback status displayed in the desktop tray.
@immutable
class TrayPresentationState {
  /// Tooltip header line (currently playing track title or `'Tachyon'`).
  final String tooltipTitle;

  /// Optional tooltip subtitle line (artist names when available).
  final String tooltipSubtitle;

  /// Combined single-line tooltip string used by Win32, AppKit, and SNI.
  final String fullTooltip;

  /// Whether playback is currently active.
  final bool isPlaying;

  /// Whether shuffle mode is currently active.
  final bool isShuffled;

  /// Whether a playable track or stream is currently loaded.
  final bool hasTrack;

  /// Localized label for the Play action.
  final String playLabel;

  /// Localized label for the Pause action.
  final String pauseLabel;

  /// Localized label for skipping to the next track.
  final String nextLabel;

  /// Localized label for skipping to the previous track.
  final String previousLabel;

  /// Localized label for toggling shuffle mode.
  final String shuffleLabel;

  /// Localized label for restoring the main window.
  final String showAppLabel;

  /// Localized label for exiting the application.
  final String quitLabel;

  /// Creates a [TrayPresentationState].
  const TrayPresentationState({
    this.tooltipTitle = 'Tachyon',
    this.tooltipSubtitle = '',
    this.fullTooltip = 'Tachyon',
    this.isPlaying = false,
    this.isShuffled = false,
    this.hasTrack = false,
    this.playLabel = 'Play',
    this.pauseLabel = 'Pause',
    this.nextLabel = 'Next track',
    this.previousLabel = 'Previous track',
    this.shuffleLabel = 'Shuffle',
    this.showAppLabel = 'Show Tachyon',
    this.quitLabel = 'Quit',
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrayPresentationState &&
          runtimeType == other.runtimeType &&
          tooltipTitle == other.tooltipTitle &&
          tooltipSubtitle == other.tooltipSubtitle &&
          fullTooltip == other.fullTooltip &&
          isPlaying == other.isPlaying &&
          isShuffled == other.isShuffled &&
          hasTrack == other.hasTrack &&
          playLabel == other.playLabel &&
          pauseLabel == other.pauseLabel &&
          nextLabel == other.nextLabel &&
          previousLabel == other.previousLabel &&
          shuffleLabel == other.shuffleLabel &&
          showAppLabel == other.showAppLabel &&
          quitLabel == other.quitLabel;

  @override
  int get hashCode => Object.hash(
    tooltipTitle,
    tooltipSubtitle,
    fullTooltip,
    isPlaying,
    isShuffled,
    hasTrack,
    playLabel,
    pauseLabel,
    nextLabel,
    previousLabel,
    shuffleLabel,
    showAppLabel,
    quitLabel,
  );
}

/// Decoded ARGB32 icon pixmap payload formatted for KDE `StatusNotifierItem`.
@immutable
class TrayPixmapData {
  /// Width of the decoded pixmap in pixels.
  final int width;

  /// Height of the decoded pixmap in pixels.
  final int height;

  /// Network-byte-order ARGB32 pixel data (`width * height * 4` bytes).
  final Uint8List argbBytes;

  /// Creates a [TrayPixmapData].
  const TrayPixmapData({
    required this.width,
    required this.height,
    required this.argbBytes,
  });
}

/// Pure-Dart Linux D-Bus system tray service implementing the Freedesktop / KDE
/// `org.kde.StatusNotifierItem` and `com.canonical.dbusmenu` protocols.
///
/// Works seamlessly across GNOME (AppIndicator), KDE Plasma, XFCE, and Wayland
/// panels without requiring external `libayatana-appindicator3` native C libraries.
class LinuxStatusNotifierTray {
  /// Callback invoked when the user activates the tray icon or picks a menu item.
  final NativeTrayActionCallback onAction;

  /// Host OS process identifier used to construct unique D-Bus bus names.
  final int processId;

  DBusClient? _client;
  TachyonStatusNotifierObject? _sniObject;
  TachyonDBusMenuObject? _menuObject;
  StreamSubscription<DBusSignal>? _watcherSub;
  String? _busName;
  bool _visible = false;
  bool _disposed = false;
  TrayPixmapData? _cachedPixmap;
  TrayPresentationState _state = const TrayPresentationState();
  int _menuRevision = 1;

  /// Creates a [LinuxStatusNotifierTray] dispatching user interactions to [onAction].
  LinuxStatusNotifierTray({required this.onAction, this.processId = 0});

  /// Latest presentation snapshot exposed by the tray objects.
  TrayPresentationState get state => _state;

  /// Current menu revision counter incremented whenever menu items change.
  int get menuRevision => _menuRevision;

  /// Pre-decoded ARGB32 pixmap bytes, if loaded from bundle assets.
  TrayPixmapData? get iconPixmap => _cachedPixmap;

  /// Whether the tray icon is currently registered and visible.
  bool get isVisible => _visible;

  /// Shows or hides the Linux StatusNotifierItem on the session D-Bus.
  Future<void> setVisible(bool visible) async {
    if (_disposed || _visible == visible) return;
    _visible = visible;
    if (visible) {
      await _show();
    } else {
      await _hide();
    }
  }

  /// Updates the tray tooltip and context menu state.
  Future<void> updateState(TrayPresentationState nextState) async {
    if (_disposed || _state == nextState) return;
    final tooltipChanged =
        _state.tooltipTitle != nextState.tooltipTitle ||
        _state.tooltipSubtitle != nextState.tooltipSubtitle ||
        _state.fullTooltip != nextState.fullTooltip;
    final menuChanged =
        _state.isPlaying != nextState.isPlaying ||
        _state.isShuffled != nextState.isShuffled ||
        _state.hasTrack != nextState.hasTrack ||
        _state.playLabel != nextState.playLabel ||
        _state.pauseLabel != nextState.pauseLabel ||
        _state.nextLabel != nextState.nextLabel ||
        _state.previousLabel != nextState.previousLabel ||
        _state.shuffleLabel != nextState.shuffleLabel ||
        _state.showAppLabel != nextState.showAppLabel ||
        _state.quitLabel != nextState.quitLabel;

    _state = nextState;
    if (!_visible) return;

    if (tooltipChanged) {
      try {
        await _sniObject?.emitNewToolTip();
      } catch (_) {}
    }
    if (menuChanged) {
      _menuRevision++;
      try {
        await _menuObject?.emitLayoutUpdated(_menuRevision);
      } catch (_) {}
    }
  }

  Future<void> _show() async {
    try {
      _cachedPixmap ??= await _loadTrayPixmap();
      final client = DBusClient.session();
      _client = client;

      final sni = TachyonStatusNotifierObject(this);
      final menu = TachyonDBusMenuObject(this);
      _sniObject = sni;
      _menuObject = menu;

      await client.registerObject(sni);
      await client.registerObject(menu);

      final baseBusName = 'org.kde.StatusNotifierItem-$processId-1';
      final reply = await client.requestName(
        baseBusName,
        flags: {DBusRequestNameFlag.doNotQueue},
      );
      if (reply == DBusRequestNameReply.primaryOwner ||
          reply == DBusRequestNameReply.alreadyOwner) {
        _busName = baseBusName;
      } else {
        final fallbackName =
            'org.kde.StatusNotifierItem-$processId-${DateTime.now().microsecondsSinceEpoch}';
        await client.requestName(fallbackName);
        _busName = fallbackName;
      }

      await _registerWithWatcher();

      _watcherSub = DBusSignalStream(
        client,
        sender: 'org.freedesktop.DBus',
        interface: 'org.freedesktop.DBus',
        name: 'NameOwnerChanged',
        path: DBusObjectPath('/org/freedesktop/DBus'),
      ).listen((signal) {
        if (_disposed || !_visible || signal.values.length < 3) return;
        final ownedName = signal.values[0].asString();
        final newOwner = signal.values[2].asString();
        if (ownedName == 'org.kde.StatusNotifierWatcher' &&
            newOwner.isNotEmpty) {
          unawaited(_registerWithWatcher());
        }
      });
    } catch (e) {
      debugPrint('[LinuxStatusNotifierTray] Failed to show tray icon: $e');
    }
  }

  Future<void> _registerWithWatcher() async {
    final client = _client;
    final busName = _busName;
    if (client == null || busName == null || _disposed || !_visible) return;
    try {
      final watcher = DBusRemoteObject(
        client,
        name: 'org.kde.StatusNotifierWatcher',
        path: DBusObjectPath('/StatusNotifierWatcher'),
      );
      await watcher.callMethod(
        'org.kde.StatusNotifierWatcher',
        'RegisterStatusNotifierItem',
        [DBusString(busName)],
        replySignature: DBusSignature.empty,
      );
    } catch (e) {
      debugPrint(
        '[LinuxStatusNotifierTray] StatusNotifierWatcher unavailable: $e',
      );
    }
  }

  Future<void> _hide() async {
    await _watcherSub?.cancel();
    _watcherSub = null;

    final client = _client;
    final sni = _sniObject;
    final menu = _menuObject;
    final busName = _busName;

    _client = null;
    _sniObject = null;
    _menuObject = null;
    _busName = null;

    if (client != null) {
      if (sni != null) {
        try {
          await client.unregisterObject(sni);
        } catch (_) {}
      }
      if (menu != null) {
        try {
          await client.unregisterObject(menu);
        } catch (_) {}
      }
      if (busName != null) {
        try {
          await client.releaseName(busName);
        } catch (_) {}
      }
      try {
        await client.close();
      } catch (_) {}
    }
  }

  Future<TrayPixmapData?> _loadTrayPixmap() async {
    ui.Codec? codec;
    ui.Image? image;
    try {
      final data = await rootBundle.load('assets/icon/icon_small.webp');
      codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: 48,
        targetHeight: 48,
      );
      final frame = await codec.getNextFrame();
      image = frame.image;
      final rgbaBytes = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (rgbaBytes == null) return null;

      final rgba = rgbaBytes.buffer.asUint8List();
      final argb = Uint8List(rgba.length);
      for (int i = 0; i + 3 < rgba.length; i += 4) {
        argb[i] = rgba[i + 3]; // A
        argb[i + 1] = rgba[i]; // R
        argb[i + 2] = rgba[i + 1]; // G
        argb[i + 3] = rgba[i + 2]; // B
      }
      return TrayPixmapData(
        width: image.width,
        height: image.height,
        argbBytes: argb,
      );
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  /// Releases D-Bus connections and marks the tray disposed.
  Future<void> dispose() async {
    _disposed = true;
    _visible = false;
    await _hide();
  }
}

/// D-Bus object exporting the `org.kde.StatusNotifierItem` interface.
class TachyonStatusNotifierObject extends DBusObject {
  /// Parent tray coordinator providing state and action callbacks.
  final LinuxStatusNotifierTray tray;

  /// Creates a [TachyonStatusNotifierObject] bound to `/StatusNotifierItem`.
  TachyonStatusNotifierObject(this.tray)
    : super(const DBusObjectPath.unchecked('/StatusNotifierItem'));

  static const String _iface = 'org.kde.StatusNotifierItem';

  /// Emits `NewToolTip` when the current track changes.
  Future<void> emitNewToolTip() => emitSignal(_iface, 'NewToolTip');

  DBusValue _buildToolTipValue() {
    final s = tray.state;
    return DBusStruct([
      const DBusString(''),
      DBusArray(DBusSignature('(iiay)')),
      DBusString(s.tooltipTitle),
      DBusString(s.tooltipSubtitle),
    ]);
  }

  DBusValue _buildIconPixmapValue() {
    final pixmap = tray.iconPixmap;
    if (pixmap == null) {
      return DBusArray(DBusSignature('(iiay)'));
    }
    return DBusArray(DBusSignature('(iiay)'), [
      DBusStruct([
        DBusInt32(pixmap.width),
        DBusInt32(pixmap.height),
        DBusArray.byte(pixmap.argbBytes),
      ]),
    ]);
  }

  @override
  List<DBusIntrospectInterface> introspect() {
    return [
      DBusIntrospectInterface(
        _iface,
        methods: [
          DBusIntrospectMethod(
            'Activate',
            args: [
              DBusIntrospectArgument(
                DBusSignature.int32,
                DBusArgumentDirection.in_,
                name: 'x',
              ),
              DBusIntrospectArgument(
                DBusSignature.int32,
                DBusArgumentDirection.in_,
                name: 'y',
              ),
            ],
          ),
          DBusIntrospectMethod(
            'SecondaryActivate',
            args: [
              DBusIntrospectArgument(
                DBusSignature.int32,
                DBusArgumentDirection.in_,
                name: 'x',
              ),
              DBusIntrospectArgument(
                DBusSignature.int32,
                DBusArgumentDirection.in_,
                name: 'y',
              ),
            ],
          ),
          DBusIntrospectMethod(
            'ContextMenu',
            args: [
              DBusIntrospectArgument(
                DBusSignature.int32,
                DBusArgumentDirection.in_,
                name: 'x',
              ),
              DBusIntrospectArgument(
                DBusSignature.int32,
                DBusArgumentDirection.in_,
                name: 'y',
              ),
            ],
          ),
          DBusIntrospectMethod(
            'Scroll',
            args: [
              DBusIntrospectArgument(
                DBusSignature.int32,
                DBusArgumentDirection.in_,
                name: 'delta',
              ),
              DBusIntrospectArgument(
                DBusSignature.string,
                DBusArgumentDirection.in_,
                name: 'orientation',
              ),
            ],
          ),
        ],
        signals: [
          DBusIntrospectSignal('NewTitle'),
          DBusIntrospectSignal('NewIcon'),
          DBusIntrospectSignal('NewToolTip'),
          DBusIntrospectSignal(
            'NewStatus',
            args: [
              DBusIntrospectArgument(
                DBusSignature.string,
                DBusArgumentDirection.out,
                name: 'status',
              ),
            ],
          ),
        ],
        properties: [
          DBusIntrospectProperty(
            'Category',
            DBusSignature.string,
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'Id',
            DBusSignature.string,
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'Title',
            DBusSignature.string,
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'Status',
            DBusSignature.string,
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'WindowId',
            DBusSignature.uint32,
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'IconName',
            DBusSignature.string,
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'IconPixmap',
            DBusSignature('a(iiay)'),
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'OverlayIconName',
            DBusSignature.string,
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'OverlayIconPixmap',
            DBusSignature('a(iiay)'),
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'AttentionIconName',
            DBusSignature.string,
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'AttentionIconPixmap',
            DBusSignature('a(iiay)'),
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'AttentionMovieName',
            DBusSignature.string,
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'ToolTip',
            DBusSignature('(sa(iiay)ss)'),
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'ItemIsMenu',
            DBusSignature.boolean,
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'Menu',
            DBusSignature.objectPath,
            access: DBusPropertyAccess.read,
          ),
        ],
      ),
    ];
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != _iface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    switch (methodCall.name) {
      case 'Activate':
        tray.onAction(DesktopTrayAction.restore);
        return DBusMethodSuccessResponse([]);
      case 'SecondaryActivate':
        tray.onAction(DesktopTrayAction.playPause);
        return DBusMethodSuccessResponse([]);
      case 'ContextMenu':
      case 'Scroll':
        return DBusMethodSuccessResponse([]);
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }

  Map<String, DBusValue> _allPropertiesMap() {
    return <String, DBusValue>{
      'Category': const DBusString('ApplicationStatus'),
      'Id': const DBusString('dev.chomusuke.tachyon'),
      'Title': const DBusString('Tachyon'),
      'Status': const DBusString('Active'),
      'WindowId': const DBusUint32(0),
      'IconName': const DBusString('tachyon'),
      'IconPixmap': _buildIconPixmapValue(),
      'OverlayIconName': const DBusString(''),
      'OverlayIconPixmap': DBusArray(DBusSignature('(iiay)')),
      'AttentionIconName': const DBusString(''),
      'AttentionIconPixmap': DBusArray(DBusSignature('(iiay)')),
      'AttentionMovieName': const DBusString(''),
      'ToolTip': _buildToolTipValue(),
      'ItemIsMenu': const DBusBoolean(false),
      'Menu': const DBusObjectPath.unchecked('/MenuBar'),
    };
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (interface != _iface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    final value = _allPropertiesMap()[name];
    if (value == null) {
      return DBusMethodErrorResponse.unknownProperty();
    }
    return DBusMethodSuccessResponse([DBusVariant(value)]);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    if (interface != _iface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    return DBusGetAllPropertiesResponse(_allPropertiesMap());
  }
}

/// D-Bus object exporting the `com.canonical.dbusmenu` interface for tray menus.
class TachyonDBusMenuObject extends DBusObject {
  /// Parent tray coordinator providing localized menu items and callbacks.
  final LinuxStatusNotifierTray tray;

  /// Menu item ID for Play / Pause.
  static const int playPauseId = 1;

  /// Menu item ID for Next Track.
  static const int nextId = 2;

  /// Menu item ID for Previous Track.
  static const int previousId = 3;

  /// Menu item ID for Shuffle (radio toggle with dot indicator).
  static const int shuffleId = 4;

  /// Menu item ID for visual separator.
  static const int separatorId = 5;

  /// Menu item ID for Show Tachyon.
  static const int showAppId = 6;

  /// Menu item ID for Quit.
  static const int quitId = 7;

  static const String _iface = 'com.canonical.dbusmenu';

  /// Creates a [TachyonDBusMenuObject] bound to `/MenuBar`.
  TachyonDBusMenuObject(this.tray)
    : super(const DBusObjectPath.unchecked('/MenuBar'));

  /// Emits `LayoutUpdated` so desktop panels refresh menu labels and states.
  Future<void> emitLayoutUpdated(int revision) => emitSignal(
    _iface,
    'LayoutUpdated',
    [DBusUint32(revision), const DBusInt32(0)],
  );

  Map<String, DBusValue> _itemProperties(int id) {
    final s = tray.state;
    switch (id) {
      case 0:
        return <String, DBusValue>{
          'children-display': const DBusString('submenu'),
        };
      case playPauseId:
        return <String, DBusValue>{
          'label': DBusString(s.isPlaying ? s.pauseLabel : s.playLabel),
          'enabled': DBusBoolean(s.hasTrack),
          'visible': const DBusBoolean(true),
        };
      case nextId:
        return <String, DBusValue>{
          'label': DBusString(s.nextLabel),
          'enabled': DBusBoolean(s.hasTrack),
          'visible': const DBusBoolean(true),
        };
      case previousId:
        return <String, DBusValue>{
          'label': DBusString(s.previousLabel),
          'enabled': DBusBoolean(s.hasTrack),
          'visible': const DBusBoolean(true),
        };
      case shuffleId:
        return <String, DBusValue>{
          'label': DBusString(s.shuffleLabel),
          'enabled': const DBusBoolean(true),
          'visible': const DBusBoolean(true),
          'toggle-type': const DBusString('radio'),
          'toggle-state': DBusInt32(s.isShuffled ? 1 : 0),
        };
      case separatorId:
        return <String, DBusValue>{
          'type': const DBusString('separator'),
          'visible': const DBusBoolean(true),
        };
      case showAppId:
        return <String, DBusValue>{
          'label': DBusString(s.showAppLabel),
          'enabled': const DBusBoolean(true),
          'visible': const DBusBoolean(true),
        };
      case quitId:
        return <String, DBusValue>{
          'label': DBusString(s.quitLabel),
          'enabled': const DBusBoolean(true),
          'visible': const DBusBoolean(true),
        };
      default:
        return const <String, DBusValue>{};
    }
  }

  DBusStruct _buildMenuNode(int id, int recursionDepth) {
    final props = _itemProperties(id);
    final List<DBusValue> children;
    if (id == 0 && recursionDepth != 0) {
      final nextDepth = recursionDepth > 0 ? recursionDepth - 1 : -1;
      children = [
        _buildMenuNode(playPauseId, nextDepth),
        _buildMenuNode(nextId, nextDepth),
        _buildMenuNode(previousId, nextDepth),
        _buildMenuNode(shuffleId, nextDepth),
        _buildMenuNode(separatorId, nextDepth),
        _buildMenuNode(showAppId, nextDepth),
        _buildMenuNode(quitId, nextDepth),
      ];
    } else {
      children = const <DBusValue>[];
    }

    return DBusStruct([
      DBusInt32(id),
      DBusDict.stringVariant(props),
      DBusArray.variant(children),
    ]);
  }

  void _dispatchMenuEvent(int id) {
    switch (id) {
      case playPauseId:
        tray.onAction(DesktopTrayAction.playPause);
        break;
      case nextId:
        tray.onAction(DesktopTrayAction.next);
        break;
      case previousId:
        tray.onAction(DesktopTrayAction.previous);
        break;
      case shuffleId:
        tray.onAction(DesktopTrayAction.toggleShuffle);
        break;
      case showAppId:
        tray.onAction(DesktopTrayAction.restore);
        break;
      case quitId:
        tray.onAction(DesktopTrayAction.quit);
        break;
    }
  }

  @override
  List<DBusIntrospectInterface> introspect() {
    return [
      DBusIntrospectInterface(
        _iface,
        methods: [
          DBusIntrospectMethod(
            'GetLayout',
            args: [
              DBusIntrospectArgument(
                DBusSignature.int32,
                DBusArgumentDirection.in_,
                name: 'parentId',
              ),
              DBusIntrospectArgument(
                DBusSignature.int32,
                DBusArgumentDirection.in_,
                name: 'recursionDepth',
              ),
              DBusIntrospectArgument(
                DBusSignature('as'),
                DBusArgumentDirection.in_,
                name: 'propertyNames',
              ),
              DBusIntrospectArgument(
                DBusSignature.uint32,
                DBusArgumentDirection.out,
                name: 'revision',
              ),
              DBusIntrospectArgument(
                DBusSignature('(ia{sv}av)'),
                DBusArgumentDirection.out,
                name: 'layout',
              ),
            ],
          ),
          DBusIntrospectMethod(
            'GetGroupProperties',
            args: [
              DBusIntrospectArgument(
                DBusSignature('ai'),
                DBusArgumentDirection.in_,
                name: 'ids',
              ),
              DBusIntrospectArgument(
                DBusSignature('as'),
                DBusArgumentDirection.in_,
                name: 'propertyNames',
              ),
              DBusIntrospectArgument(
                DBusSignature('a(ia{sv})'),
                DBusArgumentDirection.out,
                name: 'properties',
              ),
            ],
          ),
          DBusIntrospectMethod(
            'GetProperty',
            args: [
              DBusIntrospectArgument(
                DBusSignature.int32,
                DBusArgumentDirection.in_,
                name: 'id',
              ),
              DBusIntrospectArgument(
                DBusSignature.string,
                DBusArgumentDirection.in_,
                name: 'name',
              ),
              DBusIntrospectArgument(
                DBusSignature.variant,
                DBusArgumentDirection.out,
                name: 'value',
              ),
            ],
          ),
          DBusIntrospectMethod(
            'Event',
            args: [
              DBusIntrospectArgument(
                DBusSignature.int32,
                DBusArgumentDirection.in_,
                name: 'id',
              ),
              DBusIntrospectArgument(
                DBusSignature.string,
                DBusArgumentDirection.in_,
                name: 'eventId',
              ),
              DBusIntrospectArgument(
                DBusSignature.variant,
                DBusArgumentDirection.in_,
                name: 'data',
              ),
              DBusIntrospectArgument(
                DBusSignature.uint32,
                DBusArgumentDirection.in_,
                name: 'timestamp',
              ),
            ],
          ),
          DBusIntrospectMethod(
            'EventGroup',
            args: [
              DBusIntrospectArgument(
                DBusSignature('a(isvu)'),
                DBusArgumentDirection.in_,
                name: 'events',
              ),
              DBusIntrospectArgument(
                DBusSignature('ai'),
                DBusArgumentDirection.out,
                name: 'idErrors',
              ),
            ],
          ),
          DBusIntrospectMethod(
            'AboutToShow',
            args: [
              DBusIntrospectArgument(
                DBusSignature.int32,
                DBusArgumentDirection.in_,
                name: 'id',
              ),
              DBusIntrospectArgument(
                DBusSignature.boolean,
                DBusArgumentDirection.out,
                name: 'needUpdate',
              ),
            ],
          ),
          DBusIntrospectMethod(
            'AboutToShowGroup',
            args: [
              DBusIntrospectArgument(
                DBusSignature('ai'),
                DBusArgumentDirection.in_,
                name: 'ids',
              ),
              DBusIntrospectArgument(
                DBusSignature('ai'),
                DBusArgumentDirection.out,
                name: 'updatesNeeded',
              ),
              DBusIntrospectArgument(
                DBusSignature('ai'),
                DBusArgumentDirection.out,
                name: 'idErrors',
              ),
            ],
          ),
        ],
        signals: [
          DBusIntrospectSignal(
            'LayoutUpdated',
            args: [
              DBusIntrospectArgument(
                DBusSignature.uint32,
                DBusArgumentDirection.out,
                name: 'revision',
              ),
              DBusIntrospectArgument(
                DBusSignature.int32,
                DBusArgumentDirection.out,
                name: 'parent',
              ),
            ],
          ),
        ],
        properties: [
          DBusIntrospectProperty(
            'Version',
            DBusSignature.uint32,
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'TextDirection',
            DBusSignature.string,
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'Status',
            DBusSignature.string,
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'IconThemePath',
            DBusSignature('as'),
            access: DBusPropertyAccess.read,
          ),
        ],
      ),
    ];
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != _iface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    switch (methodCall.name) {
      case 'GetLayout':
        if (methodCall.values.length < 2) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        final parentId = methodCall.values[0].asInt32();
        final recursionDepth = methodCall.values[1].asInt32();
        return DBusMethodSuccessResponse([
          DBusUint32(tray.menuRevision),
          _buildMenuNode(parentId, recursionDepth),
        ]);

      case 'GetGroupProperties':
        if (methodCall.values.isEmpty) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        final ids = methodCall.values[0].asInt32Array();
        final items = [
          for (final id in ids)
            DBusStruct([
              DBusInt32(id),
              DBusDict.stringVariant(_itemProperties(id)),
            ]),
        ];
        return DBusMethodSuccessResponse([
          DBusArray(DBusSignature('(ia{sv})'), items),
        ]);

      case 'GetProperty':
        if (methodCall.values.length < 2) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        final id = methodCall.values[0].asInt32();
        final name = methodCall.values[1].asString();
        final val = _itemProperties(id)[name];
        if (val == null) {
          return DBusMethodErrorResponse.unknownProperty();
        }
        return DBusMethodSuccessResponse([DBusVariant(val)]);

      case 'Event':
        if (methodCall.values.length < 2) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        final id = methodCall.values[0].asInt32();
        final eventId = methodCall.values[1].asString();
        if (eventId == 'clicked') {
          _dispatchMenuEvent(id);
        }
        return DBusMethodSuccessResponse([]);

      case 'EventGroup':
        if (methodCall.values.isNotEmpty) {
          for (final raw in methodCall.values[0].asArray()) {
            final children = raw.asStruct();
            if (children.length >= 2) {
              final id = children[0].asInt32();
              final eventId = children[1].asString();
              if (eventId == 'clicked') {
                _dispatchMenuEvent(id);
              }
            }
          }
        }
        return DBusMethodSuccessResponse([DBusArray.int32(const [])]);

      case 'AboutToShow':
        return DBusMethodSuccessResponse([const DBusBoolean(false)]);

      case 'AboutToShowGroup':
        return DBusMethodSuccessResponse([
          DBusArray.int32(const []),
          DBusArray.int32(const []),
        ]);

      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }

  Map<String, DBusValue> _allProps() => <String, DBusValue>{
    'Version': const DBusUint32(3),
    'TextDirection': const DBusString('ltr'),
    'Status': const DBusString('normal'),
    'IconThemePath': DBusArray.string(const []),
  };

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (interface != _iface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    final val = _allProps()[name];
    if (val == null) return DBusMethodErrorResponse.unknownProperty();
    return DBusMethodSuccessResponse([DBusVariant(val)]);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    if (interface != _iface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    return DBusGetAllPropertiesResponse(_allProps());
  }
}
