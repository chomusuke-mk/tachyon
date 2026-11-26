import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart' as as_lib;
import 'package:flutter/foundation.dart';
import 'package:smtc_windows/smtc_windows.dart';
// ignore: implementation_imports
import 'package:smtc_windows/src/rust/frb_generated.dart';
import 'package:tachyon/core/logging/app_logger.dart';
import 'package:tachyon/core/playback/tachyon_audio_handler.dart';

/// Bridges [TachyonAudioHandler] to Windows System Media Transport Controls (SMTC)
/// using [smtc_windows].
///
/// Features:
/// - Lightweight ephemeral loopback HTTP server (`http://127.0.0.1:<port>/cover`)
///   so WinRT's RandomAccessStreamReference can seamlessly fetch and render album art
///   in the Windows Media Manager / taskbar / lock screen without stalling.
/// - Sequential execution lane to prevent concurrent WinRT COM apartment contention.
/// - Change deduplication to eliminate redundant WinRT updates during rapid skips or pauses.
class WindowsSmtcBridge {
  static const _log = ScopedLogger('WindowsSmtc');

  final TachyonAudioHandler _handler;
  SMTCWindows? _smtc;
  HttpServer? _coverServer;

  StreamSubscription? _buttonSub;
  StreamSubscription? _mediaItemSub;
  StreamSubscription? _playbackStateSub;

  Future<void>? _commandLane;

  // Deduplication state
  PlaybackStatus? _lastStatus;
  String? _lastTrackId;
  String? _lastTitle;
  String? _lastArtist;
  String? _lastAlbum;
  String? _lastArtPath;
  int? _lastPositionMs;
  int? _lastDurationMs;

  /// Creates a Windows SMTC bridge bound to the given audio handler.
  WindowsSmtcBridge(this._handler);

  /// Whether the Windows SMTC session has been initialized.
  bool get isInitialized => _smtc != null;

  /// The ephemeral loopback HTTP port serving album artwork, or `null` if stopped.
  @visibleForTesting
  int? get coverServerPort => _coverServer?.port;

  void _enqueue(Future<void> Function() action) {
    final prev = _commandLane;
    Future<void> run() async {
      if (_smtc == null) return;
      try {
        await action();
      } catch (e) {
        _log.e('Action failed', error: e);
      }
    }

    final next = prev == null
        ? Future<void>.sync(run)
        : prev.then((_) => run());
    late final Future<void> tail;
    tail = next.whenComplete(() {
      if (identical(_commandLane, tail)) _commandLane = null;
    });
    _commandLane = tail;
  }

  /// Initializes the loopback artwork server and Windows SMTC integration.
  ///
  /// Optionally loads the native Rust library from [externalLibrary] and
  /// returns whether initialization succeeded.
  Future<bool> initialize() async {
    if (kIsWeb || !Platform.isWindows) return false;

    try {
      // 1. Initialize local loopback HTTP server to serve artwork to WinRT SMTC
      try {
        _coverServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        _coverServer!.listen(
          _handleCoverRequest,
          onError: (e) {
            _log.w('Cover server error: $e');
          },
        );
        _log.d('Loopback cover server started on port ${_coverServer!.port}');
      } catch (e) {
        _log.w('Failed to start loopback server: $e');
      }

      // ignore: invalid_use_of_internal_member
      if (!RustLib.instance.initialized) {
        await RustLib.init(forceSameCodegenVersion: false);
      }

      _smtc = SMTCWindows(
        config: const SMTCConfig(
          playEnabled: true,
          pauseEnabled: true,
          nextEnabled: true,
          prevEnabled: true,
          stopEnabled: true,
          fastForwardEnabled: false,
          rewindEnabled: false,
        ),
      );

      _buttonSub = _smtc?.buttonPressStream.listen((event) {
        switch (event) {
          case PressedButton.play:
            _handler.play();
            break;
          case PressedButton.pause:
            _handler.pause();
            break;
          case PressedButton.next:
            _handler.skipToNext();
            break;
          case PressedButton.previous:
            _handler.skipToPrevious();
            break;
          case PressedButton.stop:
            _handler.stop();
            break;
          default:
            break;
        }
      });

      _mediaItemSub = _handler.mediaItem.listen((item) {
        if (_smtc == null) return;

        if (item == null) {
          _lastTrackId = null;
          _lastTitle = null;
          _lastArtist = null;
          _lastAlbum = null;
          _lastArtPath = null;
          _enqueue(() async {
            if (_smtc == null) return;
            await _smtc!.updateMetadata(const MusicMetadata());
          });
          return;
        }

        String? localFilePath;
        if (item.artUri != null) {
          try {
            localFilePath = item.artUri!.toFilePath();
          } catch (_) {
            localFilePath = item.artUri.toString();
          }
        }

        // Deduplication: skip if metadata has not changed
        if (item.id == _lastTrackId &&
            item.title == _lastTitle &&
            item.artist == _lastArtist &&
            item.album == _lastAlbum &&
            localFilePath == _lastArtPath) {
          return;
        }

        _lastTrackId = item.id;
        _lastTitle = item.title;
        _lastArtist = item.artist;
        _lastAlbum = item.album;
        _lastArtPath = localFilePath;

        final String? thumbnailUri;
        if (_coverServer != null &&
            localFilePath != null &&
            localFilePath.isNotEmpty) {
          final encoded = Uri.encodeComponent(localFilePath);
          thumbnailUri =
              'http://127.0.0.1:${_coverServer!.port}/cover?path=$encoded';
        } else {
          thumbnailUri = null;
        }

        final title = item.title;
        final artist = item.artist;
        final album = item.album;

        _enqueue(() async {
          if (_smtc == null) return;
          await _smtc!.updateMetadata(
            MusicMetadata(
              title: title,
              artist: artist,
              album: album,
              thumbnail: thumbnailUri,
            ),
          );
        });
      });

      _playbackStateSub = _handler.playbackState.listen((state) {
        if (_smtc == null) return;

        final PlaybackStatus status;
        if (state.playing) {
          status = PlaybackStatus.playing;
        } else if (state.processingState == as_lib.AudioProcessingState.idle) {
          status = PlaybackStatus.stopped;
        } else {
          status = PlaybackStatus.paused;
        }

        final statusChanged = status != _lastStatus;
        _lastStatus = status;

        final durationMs =
            _handler.mediaItem.value?.duration?.inMilliseconds ?? 0;
        final posMs = state.updatePosition.inMilliseconds;
        final seekOccurred =
            _lastPositionMs == null || (posMs - _lastPositionMs!).abs() > 2000;
        final durationChanged = durationMs != _lastDurationMs;
        _lastPositionMs = posMs;
        _lastDurationMs = durationMs;

        if (!statusChanged && !seekOccurred && !durationChanged) {
          return;
        }

        _enqueue(() async {
          if (_smtc == null) return;
          if (statusChanged) {
            await _smtc!.setPlaybackStatus(status);
          }
          if (statusChanged || seekOccurred || durationChanged) {
            await _smtc!.updateTimeline(
              PlaybackTimeline(
                positionMs: posMs,
                startTimeMs: 0,
                endTimeMs: durationMs,
              ),
            );
          }
        });
      });

      return true;
    } catch (e) {
      _log.e('Initialization failed', error: e);
      return false;
    }
  }

  void _handleCoverRequest(HttpRequest request) async {
    try {
      final pathParam = request.uri.queryParameters['path'];
      if (pathParam != null && pathParam.isNotEmpty) {
        final file = File(pathParam);
        if (await file.exists() && await file.length() > 0) {
          request.response.headers.contentType = ContentType('image', 'jpeg');
          request.response.headers.add('Cache-Control', 'max-age=3600');
          await request.response.addStream(file.openRead());
          await request.response.close();
          return;
        }
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  /// Cancels media listeners and shuts down the loopback server and SMTC session.
  void dispose() {
    _buttonSub?.cancel();
    _mediaItemSub?.cancel();
    _playbackStateSub?.cancel();
    try {
      _coverServer?.close(force: true);
    } catch (_) {}
    _coverServer = null;
    try {
      _smtc?.dispose();
    } catch (_) {}
    _smtc = null;
  }
}
