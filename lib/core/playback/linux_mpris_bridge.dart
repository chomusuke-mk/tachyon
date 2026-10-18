import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart' as as_lib;
import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import 'package:tachyon/core/playback/playback_controller.dart';

import 'tachyon_audio_handler.dart';

/// Clean native MPRIS2 implementation for Linux (GNOME, KDE Plasma, Wayland, playerctl)
/// without third-party log noise or unimplemented stubs.
class LinuxMprisBridge {
  final TachyonAudioHandler handler;
  final PlaybackController playbackController;

  /// Debounce window for track metadata transitions so rapid consecutive
  /// skips (e.g., 50+ tracks) coalesce into a single D-Bus signal for the
  /// final destination track without flooding GNOME Shell or GSConnect.
  final Duration metadataDebounceDuration;

  /// Coalesce window for transport state changes within the same frame/tick.
  final Duration stateCoalesceDuration;

  DBusClient? _client;
  TachyonMprisObject? _mprisObject;
  StreamSubscription? _mediaItemSub;
  StreamSubscription? _playbackStateSub;
  Timer? _syncTimer;
  Future<void> _emitLane = Future<void>.value();
  bool _isDisposed = false;
  bool _pendingMetadataCheck = false;
  String? _registeredBusName;
  int _emittedSignalCount = 0;

  // Last emitted values on D-Bus to guarantee strict property diffing.
  String? _emittedMetadataSig;
  String? _emittedPlaybackStatus;
  String? _emittedLoopStatus;
  double? _emittedRate;
  bool? _emittedShuffle;
  double? _emittedVolume;

  LinuxMprisBridge({
    required this.handler,
    required this.playbackController,
    this.metadataDebounceDuration = const Duration(milliseconds: 60),
    this.stateCoalesceDuration = const Duration(milliseconds: 12),
  });

  @visibleForTesting
  int get emittedSignalCount => _emittedSignalCount;

  @visibleForTesting
  String? get registeredBusName => _registeredBusName;

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

  bool get shuffle => playbackController.state.shuffle;

  double get volume =>
      (playbackController.state.volume / 100.0).clamp(0.0, 1.0);

  double get rate => playbackController.state.rate;

  int get positionMicros => playbackController.position.inMicroseconds;

  String _computeMetadataSignature() {
    final track = playbackController.currentTrack;
    if (track != null) {
      final artistNames = track.artists.map((a) => a.name).join(', ');
      final albumName = track.album?.name ?? '';
      final hash =
          (track.thumbnailHash != null && track.thumbnailHash!.isNotEmpty)
              ? track.thumbnailHash!
              : (track.album?.thumbnailHash ?? '');
      return '${track.id ?? track.filePath}|${track.title}|$artistNames|$albumName|${track.durationMs}|$hash';
    }
    final item = handler.mediaItem.value;
    if (item == null) return '';
    return '${item.id}|${item.title}|${item.artist ?? ''}|${item.album ?? ''}|${item.duration?.inMicroseconds ?? 0}|${item.artUri ?? ''}';
  }

  DBusDict get metadata {
    final track = playbackController.currentTrack;
    if (track != null) {
      final trackObjId = track.id ?? track.filePath.hashCode.abs();
      final artistList = track.artists
          .map((a) => a.name)
          .where((n) => n.isNotEmpty)
          .toList(growable: false);
      final albumName = track.album?.name;
      final artUri = TachyonAudioHandler.resolveLowQualityArtUri(
        track.thumbnailHash,
        track.album?.thumbnailHash,
      )?.toString();

      return DBusDict.stringVariant({
        'mpris:trackid': DBusObjectPath.unchecked(
          '/org/mpris/MediaPlayer2/Track/t_$trackObjId',
        ),
        'xesam:title': DBusString(track.title),
        if (track.durationMs > 0)
          'mpris:length': DBusInt64(track.durationMs * 1000),
        'xesam:artist': DBusArray.string(artistList),
        if (albumName != null && albumName.isNotEmpty)
          'xesam:album': DBusString(albumName),
        if (artUri != null && artUri.isNotEmpty)
          'mpris:artUrl': DBusString(artUri),
      });
    }

    final item = handler.mediaItem.value;
    if (item == null) {
      return DBusDict.stringVariant({
        'mpris:trackid': const DBusObjectPath.unchecked(
          '/org/mpris/MediaPlayer2/TrackList/NoTrack',
        ),
        'xesam:title': const DBusString(''),
        'xesam:artist': DBusArray.string(const []),
      });
    }

    final duration = item.duration;
    final artUri = item.artUri?.toString();
    final artist = item.artist;
    final album = item.album;
    final itemObjId = item.id.hashCode.abs();

    return DBusDict.stringVariant({
      'mpris:trackid': DBusObjectPath.unchecked(
        '/org/mpris/MediaPlayer2/Track/i_$itemObjId',
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
    final currentVol = volume;
    if (_emittedVolume != currentVol) {
      _emittedVolume = currentVol;
      _enqueueEmit({'Volume': DBusDouble(currentVol)});
    }
  }

  Future<void> setLoopStatus(String loopStr) async {
    final targetLoop = switch (loopStr) {
      'Track' => Loop.one,
      'Playlist' => Loop.all,
      _ => Loop.off,
    };
    await playbackController.setLoopMode(targetLoop);
    _scheduleSync(isMetadataChange: false);
  }

  Future<void> setShuffle(bool enabled) async {
    if (playbackController.state.shuffle != enabled) {
      await playbackController.toggleShuffle();
    }
    _scheduleSync(isMetadataChange: false);
  }

  Future<void> setRate(double newRate) async {
    final clamped = newRate.clamp(0.25, 4.0);
    await playbackController.setRate(clamped);
    _scheduleSync(isMetadataChange: false);
  }

  void _scheduleSync({required bool isMetadataChange}) {
    if (_isDisposed || _mprisObject == null) return;
    if (isMetadataChange) {
      _pendingMetadataCheck = true;
      _syncTimer?.cancel();
      _syncTimer = Timer(metadataDebounceDuration, _flushPendingChanges);
    } else {
      // If a metadata debounce timer is already active, let this state update
      // coalesce into the pending metadata emission so track transitions emit
      // a single combined PropertiesChanged signal.
      if (_syncTimer != null && _syncTimer!.isActive) return;
      _syncTimer = Timer(stateCoalesceDuration, _flushPendingChanges);
    }
  }

  void _flushPendingChanges() {
    _syncTimer = null;
    if (_isDisposed || _mprisObject == null) return;

    final changed = <String, DBusValue>{};

    final currentMetaSig = _computeMetadataSignature();
    if (_pendingMetadataCheck || currentMetaSig != _emittedMetadataSig) {
      _pendingMetadataCheck = false;
      if (currentMetaSig != _emittedMetadataSig) {
        _emittedMetadataSig = currentMetaSig;
        changed['Metadata'] = metadata;
      }
    }

    final currentStatus = playbackStatus;
    if (currentStatus != _emittedPlaybackStatus) {
      _emittedPlaybackStatus = currentStatus;
      changed['PlaybackStatus'] = DBusString(currentStatus);
    }

    final currentLoop = loopStatus;
    if (currentLoop != _emittedLoopStatus) {
      _emittedLoopStatus = currentLoop;
      changed['LoopStatus'] = DBusString(currentLoop);
    }

    final currentRate = rate;
    if (currentRate != _emittedRate) {
      _emittedRate = currentRate;
      changed['Rate'] = DBusDouble(currentRate);
    }

    final currentShuffle = shuffle;
    if (currentShuffle != _emittedShuffle) {
      _emittedShuffle = currentShuffle;
      changed['Shuffle'] = DBusBoolean(currentShuffle);
    }

    final currentVol = volume;
    if (currentVol != _emittedVolume) {
      _emittedVolume = currentVol;
      changed['Volume'] = DBusDouble(currentVol);
    }

    if (changed.isEmpty) return;
    _enqueueEmit(changed);
  }

  void _enqueueEmit(Map<String, DBusValue> changedProperties) {
    final obj = _mprisObject;
    if (_isDisposed || obj == null || changedProperties.isEmpty) return;
    _emittedSignalCount++;
    _emitLane = _emitLane.then((_) {
      if (_isDisposed || _mprisObject == null) return;
      try {
        obj.emitPropertiesChanged(
          'org.mpris.MediaPlayer2.Player',
          changedProperties: changedProperties,
        );
      } catch (_) {}
    });
  }

  /// Flushes any pending coalesced/debounced D-Bus signals immediately and waits
  /// for the emission lane to drain.
  @visibleForTesting
  Future<void> flushPendingSignalsForTest() async {
    if (_syncTimer?.isActive ?? false) {
      _syncTimer?.cancel();
      _flushPendingChanges();
    }
    await _emitLane;
  }

  Future<void> initialize() async {
    if (kIsWeb || !Platform.isLinux) return;

    try {
      _isDisposed = false;
      _client = DBusClient.session();
      _mprisObject = TachyonMprisObject(this);

      await _client!.registerObject(_mprisObject!);

      const baseBusName = 'org.mpris.MediaPlayer2.dev.chomusuke.tachyon';
      final reply = await _client!.requestName(
        baseBusName,
        flags: {DBusRequestNameFlag.doNotQueue},
      );

      if (reply == DBusRequestNameReply.primaryOwner ||
          reply == DBusRequestNameReply.alreadyOwner) {
        _registeredBusName = baseBusName;
      } else {
        final instanceBusName = '$baseBusName.instance$pid';
        await _client!.requestName(
          instanceBusName,
          flags: {DBusRequestNameFlag.doNotQueue},
        );
        _registeredBusName = instanceBusName;
      }

      // Seed initial snapshot before attaching listeners so BehaviorSubject's
      // initial replay does not emit redundant startup PropertiesChanged signals.
      _emittedMetadataSig = _computeMetadataSignature();
      _emittedPlaybackStatus = playbackStatus;
      _emittedLoopStatus = loopStatus;
      _emittedRate = rate;
      _emittedShuffle = shuffle;
      _emittedVolume = volume;

      _mediaItemSub = handler.mediaItem.listen((_) {
        _scheduleSync(isMetadataChange: true);
      });

      _playbackStateSub = handler.playbackState.listen((_) {
        _scheduleSync(isMetadataChange: false);
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
    _isDisposed = true;
    _syncTimer?.cancel();
    _syncTimer = null;
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
            'Shuffle',
            DBusSignature('b'),
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
        'Rate' => DBusDouble(bridge.rate),
        'Shuffle' => DBusBoolean(bridge.shuffle),
        'Metadata' => bridge.metadata,
        'Volume' => DBusDouble(bridge.volume),
        'Position' => DBusInt64(bridge.positionMicros),
        'MinimumRate' => const DBusDouble(0.25),
        'MaximumRate' => const DBusDouble(4.0),
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
        'Rate': DBusDouble(bridge.rate),
        'Shuffle': DBusBoolean(bridge.shuffle),
        'Metadata': bridge.metadata,
        'Volume': DBusDouble(bridge.volume),
        'Position': DBusInt64(bridge.positionMicros),
        'MinimumRate': const DBusDouble(0.25),
        'MaximumRate': const DBusDouble(4.0),
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
      } else if (name == 'Shuffle' && value is DBusBoolean) {
        await bridge.setShuffle(value.value);
        return DBusMethodSuccessResponse([]);
      } else if (name == 'Rate' && value is DBusDouble) {
        await bridge.setRate(value.value);
        return DBusMethodSuccessResponse([]);
      }
      return DBusMethodErrorResponse.propertyReadOnly();
    }
    return DBusMethodErrorResponse.unknownProperty();
  }
}
