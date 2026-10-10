import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart' as as_lib;
import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';

import 'tachyon_audio_handler.dart';

/// Clean native MPRIS2 implementation for Linux (GNOME, KDE Plasma, Wayland, playerctl)
/// without third-party log noise or unimplemented stubs.
class LinuxMprisBridge {
  final TachyonAudioHandler handler;
  final PlaybackController playbackController;

  DBusClient? _client;
  TachyonMprisObject? _mprisObject;
  StreamSubscription? _mediaItemSub;
  StreamSubscription? _playbackStateSub;

  LinuxMprisBridge({required this.handler, required this.playbackController});

  String get playbackStatus {
    final state = handler.playbackState.value;
    if (state.playing) return 'Playing';
    if (state.processingState == as_lib.AudioProcessingState.idle) {
      return 'Stopped';
    }
    return 'Paused';
  }

  String get loopStatus {
    return switch (playbackController.state.loop) {
      Loop.off => 'None',
      Loop.one => 'Track',
      Loop.all => 'Playlist',
    };
  }

  double get volume =>
      (playbackController.state.volume / 100.0).clamp(0.0, 1.0);

  int get positionMicros => playbackController.position.inMicroseconds;

  DBusDict get metadata {
    final item = handler.mediaItem.value;
    if (item == null) {
      return DBusDict.stringVariant({
        'mpris:trackid': const DBusObjectPath.unchecked(
          '/org/mpris/MediaPlayer2/CurrentTrack',
        ),
        'xesam:title': const DBusString(''),
        'xesam:artist': DBusArray.string(const []),
      });
    }

    final duration = item.duration;
    final artUri = item.artUri?.toString();
    final artist = item.artist;
    final album = item.album;

    return DBusDict.stringVariant({
      'mpris:trackid': const DBusObjectPath.unchecked(
        '/org/mpris/MediaPlayer2/CurrentTrack',
      ),
      'xesam:title': DBusString(item.title),
      if (duration != null) 'mpris:length': DBusInt64(duration.inMicroseconds),
      'xesam:artist': DBusArray.string(
        artist != null && artist.isNotEmpty ? [artist] : const [],
      ),
      if (album != null && album.isNotEmpty) 'xesam:album': DBusString(album),
      if (artUri != null && artUri.isNotEmpty)
        'mpris:artUrl': DBusString(artUri),
    });
  }

  Future<void> play() => handler.play();
  Future<void> pause() => handler.pause();
  Future<void> stop() => handler.stop();
  Future<void> skipToNext() => handler.skipToNext();
  Future<void> skipToPrevious() => handler.skipToPrevious();

  Future<void> playPause() async {
    if (handler.playbackState.value.playing) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> seek(Duration position) => handler.seek(position);

  Future<void> seekOffset(Duration offset) {
    final current = playbackController.position;
    final target = current + offset;
    return handler.seek(target < Duration.zero ? Duration.zero : target);
  }

  Future<void> setVolume(double newVolume) async {
    final targetVol = (newVolume * 100.0).clamp(0.0, 100.0);
    await playbackController.setVolume(targetVol);
    _mprisObject?.emitPropertiesChanged(
      'org.mpris.MediaPlayer2.Player',
      changedProperties: {'Volume': DBusDouble(volume)},
    );
  }

  Future<void> setLoopStatus(String loopStr) async {
    final targetLoop = switch (loopStr) {
      'Track' => Loop.one,
      'Playlist' => Loop.all,
      _ => Loop.off,
    };
    await playbackController.setLoopMode(targetLoop);
    _mprisObject?.emitPropertiesChanged(
      'org.mpris.MediaPlayer2.Player',
      changedProperties: {'LoopStatus': DBusString(loopStatus)},
    );
  }

  Future<void> initialize() async {
    if (kIsWeb || !Platform.isLinux) return;

    try {
      _client = DBusClient.session();
      _mprisObject = TachyonMprisObject(this);

      await _client!.registerObject(_mprisObject!);

      const baseBusName = 'org.mpris.MediaPlayer2.dev.chomusuke.tachyon';
      final reply = await _client!.requestName(
        baseBusName,
        flags: {DBusRequestNameFlag.doNotQueue},
      );

      if (reply != DBusRequestNameReply.primaryOwner &&
          reply != DBusRequestNameReply.alreadyOwner) {
        final instanceBusName = '$baseBusName.instance$pid';
        await _client!.requestName(
          instanceBusName,
          flags: {DBusRequestNameFlag.doNotQueue},
        );
      }

      _mediaItemSub = handler.mediaItem.listen((item) {
        _mprisObject?.emitPropertiesChanged(
          'org.mpris.MediaPlayer2.Player',
          changedProperties: {'Metadata': metadata},
        );
      });

      _playbackStateSub = handler.playbackState.listen((state) {
        _mprisObject?.emitPropertiesChanged(
          'org.mpris.MediaPlayer2.Player',
          changedProperties: {
            'PlaybackStatus': DBusString(playbackStatus),
            'LoopStatus': DBusString(loopStatus),
          },
        );
      });

      debugPrint(
        '[LinuxMprisBridge] Initialization complete. Current status: $playbackStatus, volume: $volume',
      );
    } catch (e, stack) {
      debugPrint('[LinuxMprisBridge] Initialization error: $e\n$stack');
    }
  }

  void dispose() {
    debugPrint('[LinuxMprisBridge] Disposing MPRIS bridge...');
    _mediaItemSub?.cancel();
    _playbackStateSub?.cancel();

    if (_mprisObject != null && _client != null) {
      try {
        _client!.unregisterObject(_mprisObject!);
      } catch (_) {}
    }

    try {
      _client?.close();
    } catch (_) {}

    _mprisObject = null;
    _client = null;
  }
}

class TachyonMprisObject extends DBusObject {
  final LinuxMprisBridge bridge;

  TachyonMprisObject(this.bridge)
    : super(const DBusObjectPath.unchecked('/org/mpris/MediaPlayer2'));

  @override
  List<DBusIntrospectInterface> introspect() {
    return [
      DBusIntrospectInterface(
        'org.mpris.MediaPlayer2',
        methods: [DBusIntrospectMethod('Raise'), DBusIntrospectMethod('Quit')],
        properties: [
          DBusIntrospectProperty(
            'CanQuit',
            DBusSignature('b'),
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'CanRaise',
            DBusSignature('b'),
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'HasTrackList',
            DBusSignature('b'),
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'Identity',
            DBusSignature('s'),
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'DesktopEntry',
            DBusSignature('s'),
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'SupportedUriSchemes',
            DBusSignature('as'),
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'SupportedMimeTypes',
            DBusSignature('as'),
            access: DBusPropertyAccess.read,
          ),
        ],
      ),
      DBusIntrospectInterface(
        'org.mpris.MediaPlayer2.Player',
        methods: [
          DBusIntrospectMethod('Next'),
          DBusIntrospectMethod('Previous'),
          DBusIntrospectMethod('Pause'),
          DBusIntrospectMethod('PlayPause'),
          DBusIntrospectMethod('Stop'),
          DBusIntrospectMethod('Play'),
          DBusIntrospectMethod(
            'Seek',
            args: [
              DBusIntrospectArgument(
                DBusSignature('x'),
                DBusArgumentDirection.in_,
                name: 'Offset',
              ),
            ],
          ),
          DBusIntrospectMethod(
            'SetPosition',
            args: [
              DBusIntrospectArgument(
                DBusSignature('o'),
                DBusArgumentDirection.in_,
                name: 'TrackId',
              ),
              DBusIntrospectArgument(
                DBusSignature('x'),
                DBusArgumentDirection.in_,
                name: 'Position',
              ),
            ],
          ),
        ],
        signals: [
          DBusIntrospectSignal(
            'Seeked',
            args: [
              DBusIntrospectArgument(
                DBusSignature('x'),
                DBusArgumentDirection.out,
                name: 'Position',
              ),
            ],
          ),
        ],
        properties: [
          DBusIntrospectProperty(
            'PlaybackStatus',
            DBusSignature('s'),
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'LoopStatus',
            DBusSignature('s'),
            access: DBusPropertyAccess.readwrite,
          ),
          DBusIntrospectProperty(
            'Rate',
            DBusSignature('d'),
            access: DBusPropertyAccess.readwrite,
          ),
          DBusIntrospectProperty(
            'Metadata',
            DBusSignature('a{sv}'),
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'Volume',
            DBusSignature('d'),
            access: DBusPropertyAccess.readwrite,
          ),
          DBusIntrospectProperty(
            'Position',
            DBusSignature('x'),
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'MinimumRate',
            DBusSignature('d'),
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'MaximumRate',
            DBusSignature('d'),
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'CanGoNext',
            DBusSignature('b'),
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'CanGoPrevious',
            DBusSignature('b'),
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'CanPlay',
            DBusSignature('b'),
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'CanPause',
            DBusSignature('b'),
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'CanSeek',
            DBusSignature('b'),
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'CanControl',
            DBusSignature('b'),
            access: DBusPropertyAccess.read,
          ),
        ],
      ),
    ];
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface == 'org.mpris.MediaPlayer2') {
      if (methodCall.name == 'Raise' || methodCall.name == 'Quit') {
        return DBusMethodSuccessResponse([]);
      }
      return DBusMethodErrorResponse.unknownMethod();
    } else if (methodCall.interface == 'org.mpris.MediaPlayer2.Player') {
      switch (methodCall.name) {
        case 'Next':
          await bridge.skipToNext();
          return DBusMethodSuccessResponse([]);
        case 'Previous':
          await bridge.skipToPrevious();
          return DBusMethodSuccessResponse([]);
        case 'Pause':
          await bridge.pause();
          return DBusMethodSuccessResponse([]);
        case 'PlayPause':
          await bridge.playPause();
          return DBusMethodSuccessResponse([]);
        case 'Stop':
          await bridge.stop();
          return DBusMethodSuccessResponse([]);
        case 'Play':
          await bridge.play();
          return DBusMethodSuccessResponse([]);
        case 'Seek':
          if (methodCall.values.isNotEmpty &&
              methodCall.values[0] is DBusInt64) {
            final offset = (methodCall.values[0] as DBusInt64).value;
            await bridge.seekOffset(Duration(microseconds: offset));
            return DBusMethodSuccessResponse([]);
          }
          return DBusMethodErrorResponse.invalidArgs();
        case 'SetPosition':
          if (methodCall.values.length >= 2 &&
              methodCall.values[1] is DBusInt64) {
            final posMicros = (methodCall.values[1] as DBusInt64).value;
            await bridge.seek(Duration(microseconds: posMicros));
            return DBusMethodSuccessResponse([]);
          }
          return DBusMethodErrorResponse.invalidArgs();
        default:
          return DBusMethodErrorResponse.unknownMethod();
      }
    }
    return DBusMethodErrorResponse.unknownInterface();
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (interface == 'org.mpris.MediaPlayer2') {
      final DBusValue? value = switch (name) {
        'CanQuit' => const DBusBoolean(false),
        'CanRaise' => const DBusBoolean(false),
        'HasTrackList' => const DBusBoolean(false),
        'Identity' => const DBusString('Tachyon'),
        'DesktopEntry' => const DBusString(''),
        'SupportedUriSchemes' => DBusArray.string(const []),
        'SupportedMimeTypes' => DBusArray.string(const []),
        _ => null,
      };

      if (value != null) {
        return DBusMethodSuccessResponse([DBusVariant(value)]);
      }
      return DBusMethodErrorResponse.unknownProperty();
    } else if (interface == 'org.mpris.MediaPlayer2.Player') {
      final DBusValue? value = switch (name) {
        'PlaybackStatus' => DBusString(bridge.playbackStatus),
        'LoopStatus' => DBusString(bridge.loopStatus),
        'Rate' => const DBusDouble(1.0),
        'Metadata' => bridge.metadata,
        'Volume' => DBusDouble(bridge.volume),
        'Position' => DBusInt64(bridge.positionMicros),
        'MinimumRate' => const DBusDouble(1.0),
        'MaximumRate' => const DBusDouble(1.0),
        'CanGoNext' => const DBusBoolean(true),
        'CanGoPrevious' => const DBusBoolean(true),
        'CanPlay' => const DBusBoolean(true),
        'CanPause' => const DBusBoolean(true),
        'CanSeek' => const DBusBoolean(true),
        'CanControl' => const DBusBoolean(true),
        _ => null,
      };

      if (value != null) {
        return DBusMethodSuccessResponse([DBusVariant(value)]);
      }
      return DBusMethodErrorResponse.unknownProperty();
    }
    return DBusMethodErrorResponse.unknownInterface();
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    if (interface == 'org.mpris.MediaPlayer2') {
      return DBusGetAllPropertiesResponse({
        'CanQuit': const DBusBoolean(false),
        'CanRaise': const DBusBoolean(false),
        'HasTrackList': const DBusBoolean(false),
        'Identity': const DBusString('Tachyon'),
        'DesktopEntry': const DBusString(''),
        'SupportedUriSchemes': DBusArray.string(const []),
        'SupportedMimeTypes': DBusArray.string(const []),
      });
    } else if (interface == 'org.mpris.MediaPlayer2.Player') {
      return DBusGetAllPropertiesResponse({
        'PlaybackStatus': DBusString(bridge.playbackStatus),
        'LoopStatus': DBusString(bridge.loopStatus),
        'Rate': const DBusDouble(1.0),
        'Metadata': bridge.metadata,
        'Volume': DBusDouble(bridge.volume),
        'Position': DBusInt64(bridge.positionMicros),
        'MinimumRate': const DBusDouble(1.0),
        'MaximumRate': const DBusDouble(1.0),
        'CanGoNext': const DBusBoolean(true),
        'CanGoPrevious': const DBusBoolean(true),
        'CanPlay': const DBusBoolean(true),
        'CanPause': const DBusBoolean(true),
        'CanSeek': const DBusBoolean(true),
        'CanControl': const DBusBoolean(true),
      });
    }
    return DBusMethodErrorResponse.unknownInterface();
  }

  @override
  Future<DBusMethodResponse> setProperty(
    String interface,
    String name,
    DBusValue value,
  ) async {
    if (interface == 'org.mpris.MediaPlayer2.Player') {
      if (name == 'Volume' && value is DBusDouble) {
        await bridge.setVolume(value.value);
        return DBusMethodSuccessResponse([]);
      } else if (name == 'LoopStatus' && value is DBusString) {
        await bridge.setLoopStatus(value.value);
        return DBusMethodSuccessResponse([]);
      }
      return DBusMethodErrorResponse.propertyReadOnly();
    }
    return DBusMethodErrorResponse.unknownProperty();
  }
}
