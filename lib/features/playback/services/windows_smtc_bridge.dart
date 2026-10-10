import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart' as as_lib;
import 'package:flutter/foundation.dart';
import 'package:smtc_windows/smtc_windows.dart';

import 'tachyon_audio_handler.dart';

/// Bridges [TachyonAudioHandler] to Windows System Media Transport Controls (SMTC)
/// using [smtc_windows].
class WindowsSmtcBridge {
  final TachyonAudioHandler _handler;
  SMTCWindows? _smtc;
  StreamSubscription? _buttonSub;
  StreamSubscription? _mediaItemSub;
  StreamSubscription? _playbackStateSub;

  WindowsSmtcBridge(this._handler);

  Future<void> initialize() async {
    if (kIsWeb || !Platform.isWindows) return;

    try {
      await SMTCWindows.initialize();

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
          _smtc!.updateMetadata(const MusicMetadata());
          return;
        }

        String? localThumbnailPath;
        if (item.artUri != null) {
          try {
            localThumbnailPath = item.artUri!.toFilePath();
          } catch (_) {
            localThumbnailPath = item.artUri.toString();
          }
        }

        _smtc!.updateMetadata(
          MusicMetadata(
            title: item.title,
            artist: item.artist,
            album: item.album,
            thumbnail: localThumbnailPath,
          ),
        );
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

        _smtc!.setPlaybackStatus(status);

        final durationMs =
            _handler.mediaItem.value?.duration?.inMilliseconds ?? 0;
        _smtc!.updateTimeline(
          PlaybackTimeline(
            positionMs: state.updatePosition.inMilliseconds,
            startTimeMs: 0,
            endTimeMs: durationMs,
          ),
        );
      });
    } catch (e) {
      debugPrint('[WindowsSmtcBridge] Initialization failed: $e');
    }
  }

  void dispose() {
    _buttonSub?.cancel();
    _mediaItemSub?.cancel();
    _playbackStateSub?.cancel();
    try {
      _smtc?.dispose();
    } catch (_) {}
    _smtc = null;
  }
}
