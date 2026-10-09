import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:miniaudio_player/miniaudio_player.dart';

import 'package:tachyon/core/backend/backend_protocol.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/backend/services/audio_engine_service.dart';
import 'package:tachyon/core/backend/services/audio_player_adapter.dart';
import 'package:tachyon/shared/utils/cover_utils.dart';
import 'package:tachyon/core/backend/services/lyrics_service.dart';
import 'package:tachyon/core/backend/services/metadata_service.dart';
import 'package:tachyon/core/backend/services/queue_manager.dart';
import 'package:tachyon/core/network/lyrics_translation_client.dart';
import 'package:tachyon/features/library/domain/album.dart';
import 'package:tachyon/features/library/domain/artist.dart';
import 'package:tachyon/features/library/domain/genre.dart';
import 'package:tachyon/features/library/domain/playlist.dart';
import 'package:tachyon/features/library/domain/scan_progress.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/playback/domain/crossfade_config.dart';
import 'package:tachyon/features/playback/domain/loop_mode.dart';
import 'package:tachyon/features/playback/domain/lyric_source.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart'
    show CrossfadeCurve;

/// Configuration passed from the UI Isolate when spawning the Core Service Isolate.
class CoreInitConfig {
  final SendPort uiSendPort;
  final String dbPath;
  final String cacheDirPath;

  CoreInitConfig({
    required this.uiSendPort,
    required this.dbPath,
    required this.cacheDirPath,
  });
}

/// Entry point function for [Isolate.spawn] to start the Core Service Isolate.
Future<void> coreBackendEntryPoint(CoreInitConfig config) async {
  final host = TachyonBackendHost(config);
  await host.start();
}

/// The Core Service Isolate backend host.
/// Runs in a background isolate and orchestrates SQLite, audio playback,
/// lyrics resolution, and metadata coordination.
class TachyonBackendHost {
  final CoreInitConfig config;

  late final ReceivePort _hostReceivePort;
  late final AppDatabase _database;
  late final MetadataService _metadataService;
  late final QueueManager _queueManager;
  late final AudioEngineService _audioEngine;
  late final LyricsService _lyricsService;

  final List<StreamSubscription> _subscriptions = [];
  int _lastEmittedPositionMs = -1;
  int _lastPositionEmitTimestamp = 0;

  TachyonBackendHost(this.config);

  Future<void> start() async {
    _hostReceivePort = ReceivePort();

    // 1. Initialize audio adapter bindings in the isolate
    await AudioPlayerAdapter.ensureInitialized();

    // 2. Initialize database
    _database = AppDatabase();
    await _database.init(config.dbPath);

    // 3. Initialize cover cache and metadata service
    CoverUtils.init(Directory(config.cacheDirPath));

    _metadataService = MetadataService(
      database: _database,
      cacheDirPath: config.cacheDirPath,
    );

    // 4. Initialize playback engine
    _queueManager = QueueManager(
      libraryTrackProvider: (count) async => _database.getRandomTracks(count),
    );
    _audioEngine = AudioEngineService(queueManager: _queueManager);

    // 5. Initialize lyrics service
    _lyricsService = LyricsService(database: _database);

    // 6. Set up event forwarding to the UI isolate
    _subscriptions.add(
      _audioEngine.stateStream.listen((state) {
        config.uiSendPort.send(
          BackendEvent(topic: BackendTopics.playbackState, payload: state),
        );
      }),
    );

    _subscriptions.add(
      _audioEngine.devicesStream.listen((devices) {
        config.uiSendPort.send(
          BackendEvent(
            topic: BackendTopics.playbackDevices,
            payload: devices,
          ),
        );
      }),
    );

    try {
      final initialDevices = _audioEngine.getAudioDevicesSync();
      if (initialDevices.isNotEmpty) {
        config.uiSendPort.send(
          BackendEvent(
            topic: BackendTopics.playbackDevices,
            payload: initialDevices,
          ),
        );
      }
    } catch (_) {}

    // Throttled position updates (max ~25Hz) to keep UI isolate completely smooth
    _subscriptions.add(
      _audioEngine.positionStream.listen((pos) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final deltaMs = now - _lastPositionEmitTimestamp;
        if (deltaMs >= 40 ||
            (pos.inMilliseconds - _lastEmittedPositionMs).abs() > 1000) {
          _lastPositionEmitTimestamp = now;
          _lastEmittedPositionMs = pos.inMilliseconds;
          config.uiSendPort.send(
            BackendEvent(
              topic: BackendTopics.playbackPosition,
              payload: pos.inMilliseconds,
            ),
          );
        }
      }),
    );

    _subscriptions.add(
      _audioEngine.visualizerStream.listen((vis) {
        config.uiSendPort.send(
          BackendEvent(
            topic: BackendTopics.playbackVisualizer,
            payload: <double>[
              vis.rms,
              vis.peak,
              vis.left,
              vis.right,
              ...vis.bands,
            ],
          ),
        );
      }),
    );

    _subscriptions.add(
      _metadataService.progressStream.listen((progress) {
        config.uiSendPort.send(
          BackendEvent(
            topic: BackendTopics.libraryScanProgress,
            payload: progress,
          ),
        );
        if (progress.stage == ScanStage.completed) {
          config.uiSendPort.send(
            const BackendEvent(topic: BackendTopics.catalogUpdated),
          );
        }
      }),
    );

    // 7. Send the host SendPort to the UI isolate so it can start sending requests
    config.uiSendPort.send(_hostReceivePort.sendPort);

    // 8. Listen for incoming requests from the UI isolate
    _hostReceivePort.listen(_onRequestReceived);
  }

  Future<void> _onRequestReceived(dynamic message) async {
    if (message is! BackendRequest) return;

    try {
      final result = await _dispatch(message.method, message.params);
      config.uiSendPort.send(
        BackendResponse(requestId: message.requestId, data: result),
      );
    } catch (e, stack) {
      debugPrint(
        '[CoreBackendHost] Error handling request ${message.method}: $e\n$stack',
      );
      config.uiSendPort.send(
        BackendResponse(requestId: message.requestId, error: e.toString()),
      );
    }
  }

  Future<dynamic> _dispatch(String method, Map<String, dynamic> params) async {
    switch (method) {
      // =======================================================================
      // PLAYBACK COMMANDS
      // =======================================================================
      case BackendMethods.playbackPlay:
        await _audioEngine.play();
        return null;

      case BackendMethods.playbackPause:
        await _audioEngine.pause();
        return null;

      case BackendMethods.playbackStop:
        await _audioEngine.stop();
        return null;

      case BackendMethods.playbackSeek:
        final ms = params['positionMs'] as int;
        await _audioEngine.seek(Duration(milliseconds: ms));
        return null;

      case BackendMethods.playbackNext:
        await _audioEngine.next();
        return null;

      case BackendMethods.playbackPrevious:
        await _audioEngine.previous();
        return null;

      case BackendMethods.playbackSetVolume:
        final volume = (params['volume'] as num).toDouble();
        await _audioEngine.setVolume(volume);
        return null;

      case BackendMethods.playbackSetEqualizer:
        final gains = (params['gains'] as List).cast<double>();
        await _audioEngine.setEqualizer(Equalizer.fromList(gains));
        return null;

      case BackendMethods.playbackSetOutputDevice:
        final device = params['device'] as AudioDevice;
        await _audioEngine.setDevice(device);
        return null;

      case BackendMethods.playbackGetAudioDevices:
        return await _audioEngine.getAudioDevices();

      case BackendMethods.playbackPlayTrack:
        final trackId = params['trackId'] as int;
        final autoPlay = params['play'] as bool? ?? true;
        final track = _database.getTrackById(trackId);
        if (track != null) {
          final entry = PlaylistEntry.forQueue(
            id: 0,
            position: 0,
            track: track,
          );
          await _audioEngine.open([entry], play: autoPlay);
        }
        return null;

      case BackendMethods.playbackPlayQueue:
        final trackIds = (params['trackIds'] as List).cast<int>();
        final startIndex = params['startIndex'] as int?;
        final autoPlay = params['play'] as bool? ?? true;
        final shuffle = params['shuffle'] as bool? ?? false;
        final tracks = _database.getTracksByIds(trackIds);
        final entries = [
          for (int i = 0; i < tracks.length; i++)
            PlaylistEntry.forQueue(id: i, position: i, track: tracks[i]),
        ];
        await _audioEngine.open(
          entries,
          index: startIndex,
          play: autoPlay,
          shuffle: shuffle,
        );
        return null;

      case BackendMethods.playbackSetShuffle:
        final enabled = params['enabled'] as bool;
        await _audioEngine.setShuffle(enabled);
        return null;

      case BackendMethods.playbackSetLoopMode:
        final modeIndex = params['loopMode'] as int;
        await _audioEngine.setLoopMode(Loop.values[modeIndex]);
        return null;

      case BackendMethods.playbackRemoveQueueItem:
        final index = params['index'] as int;
        await _audioEngine.remove(index);
        return null;

      case BackendMethods.playbackReorderQueue:
        final oldIndex = params['oldIndex'] as int;
        final newIndex = params['newIndex'] as int;
        await _audioEngine.reorder(oldIndex, newIndex);
        return null;

      case BackendMethods.playbackClearQueue:
        await _audioEngine.clearQueue();
        return null;

      case BackendMethods.playbackGetState:
        return _audioEngine.state;

      case BackendMethods.playbackSetCrossfadeDuration:
        final durationMs = params['durationMs'] as int;
        await _audioEngine.setCrossfadeDuration(
          Duration(milliseconds: durationMs),
        );
        return null;

      case BackendMethods.playbackSetCrossfadeCurve:
        final curveIndex = params['curve'] as int;
        await _audioEngine.setCrossfadeCurve(CrossfadeCurve.values[curveIndex]);
        return null;

      case BackendMethods.playbackOpen:
        final rawTrackIds = (params['trackIds'] ?? params['items']) as List;
        final trackIds = rawTrackIds.cast<int>();
        final index = params['index'] as int?;
        final autoPlay = params['play'] as bool? ?? true;
        final shuffle = params['shuffle'] as bool? ?? false;
        final tracks = _database.getTracksByIds(trackIds);
        final entries = [
          for (int i = 0; i < tracks.length; i++)
            PlaylistEntry.forQueue(id: i, position: i, track: tracks[i]),
        ];
        await _audioEngine.open(
          entries,
          index: index,
          play: autoPlay,
          shuffle: shuffle,
        );
        return null;

      case BackendMethods.playbackInsertNext:
        final trackId = (params['trackId'] ?? params['item']) as int;
        final track = _database.getTrackById(trackId);
        if (track != null) {
          final entry = PlaylistEntry.forQueue(
            id: 0,
            position: 0,
            track: track,
          );
          await _audioEngine.insertNext(entry);
        }
        return null;

      case BackendMethods.playbackAppend:
        final rawTrackIds = (params['trackIds'] ?? params['items']) as List;
        final trackIds = rawTrackIds.cast<int>();
        final tracks = _database.getTracksByIds(trackIds);
        final entries = [
          for (int i = 0; i < tracks.length; i++)
            PlaylistEntry.forQueue(id: i, position: i, track: tracks[i]),
        ];
        await _audioEngine.append(entries);
        return null;

      case BackendMethods.playbackSkipToIndex:
        final index = params['index'] as int;
        await _audioEngine.skipToIndex(index);
        return null;

      case BackendMethods.playbackSetRate:
        final rate = (params['rate'] as num).toDouble();
        await _audioEngine.setRate(rate);
        return null;

      case BackendMethods.playbackSetPitch:
        final pitch = (params['pitch'] as num).toDouble();
        await _audioEngine.setPitch(pitch);
        return null;

      case BackendMethods.playbackSetSkipSilence:
        final enabled = params['enabled'] as bool;
        await _audioEngine.setSkipSilence(enabled);
        return null;

      case BackendMethods.playbackSetVolumeNormalization:
        final enabled = params['enabled'] as bool;
        await _audioEngine.setVolumeNormalization(enabled);
        return null;

      case BackendMethods.playbackSetPreamp:
        final preampDb = (params['preampDb'] as num).toDouble();
        await _audioEngine.setPreamp(preampDb);
        return null;

      case BackendMethods.playbackSetBalance:
        final balance = (params['balance'] as num).toDouble();
        await _audioEngine.setBalance(balance);
        return null;

      case BackendMethods.playbackSetMono:
        final enabled = params['enabled'] as bool;
        await _audioEngine.setMono(enabled);
        return null;

      case BackendMethods.playbackSetCrossfeed:
        final modeIndex = params['mode'] as int;
        await _audioEngine.setCrossfeed(CrossfeedMode.values[modeIndex]);
        return null;

      case BackendMethods.playbackSetSpatializer:
        final width = (params['width'] as num).toDouble();
        await _audioEngine.setSpatializer(width);
        return null;

      case BackendMethods.playbackSetLimiter:
        final enabled = params['enabled'] as bool;
        await _audioEngine.setLimiter(enabled);
        return null;

      case BackendMethods.playbackSetCrossfadeConfig:
        final config = params['config'] as CrossfadeConfig;
        await _audioEngine.setCrossfadeConfig(config);
        return null;

      case BackendMethods.playbackSetVisualizerEnabled:
        final enabled = params['enabled'] as bool;
        _audioEngine.setVisualizerEnabled(enabled);
        return null;

      case BackendMethods.playbackSetInfiniteMix:
        final enabled = params['enabled'] as bool;
        await _audioEngine.setInfiniteMix(enabled);
        return null;

      // =======================================================================
      // LIBRARY & CATALOG
      // =======================================================================
      case BackendMethods.libraryGetCatalogSnapshot:
        return _database.getCatalogSnapshot();

      case BackendMethods.libraryGetTracks:
        return const <Track>[];

      case BackendMethods.libraryGetAlbums:
        return const <Album>[];

      case BackendMethods.libraryGetArtists:
        return const <Artist>[];

      case BackendMethods.libraryGetGenres:
        return const <Genre>[];

      case BackendMethods.libraryGetAlbumTracks:
        return const <Track>[];

      case BackendMethods.libraryGetArtistTracks:
        return const <Track>[];

      case BackendMethods.libraryStartScan:
        final directories = params['directories'] != null
            ? (params['directories'] as List).cast<String>()
            : [params['directoryPath'] as String];
        _metadataService.scanDirectories(directories);
        return null;

      case BackendMethods.libraryCancelScan:
        _metadataService.cancelScan();
        return null;

      case BackendMethods.libraryDeleteTrack:
        final trackId = params['trackId'] as int;
        _database.deleteTrack(trackId);
        config.uiSendPort.send(
          const BackendEvent(topic: BackendTopics.catalogUpdated),
        );
        return null;

      // =======================================================================
      // METADATA (WORKER ISOLATES)
      // =======================================================================
      case BackendMethods.metadataGetMetadata:
        final filePath = params['filePath'] as String;
        return await _metadataService.getMetadata(filePath);

      // =======================================================================
      // PLAYLISTS
      // =======================================================================
      case BackendMethods.playlistsCreate:
        final name = params['name'] as String;
        final id = _database.createPlaylist(name);
        return id;

      case BackendMethods.playlistsDelete:
        final playlistId = params['playlistId'] as int;
        _database.deletePlaylist(playlistId);
        return null;

      case BackendMethods.playlistsRename:
        final playlistId = params['playlistId'] as int;
        final name = params['name'] as String;
        _database.renamePlaylist(playlistId, name);
        return null;

      case BackendMethods.playlistsAddTracks:
        final playlistId = params['playlistId'] as int;
        final trackIds = (params['trackIds'] as List).cast<int>();
        try {
          _database.addTracksToPlaylist(playlistId, trackIds);
        } catch (e) {
          debugPrint('[CoreBackendHost] Error adding tracks to playlist $playlistId: $e');
        }
        return null;

      case BackendMethods.playlistsRemoveTrack:
        final playlistId = params['playlistId'] as int;
        final trackId = params['trackId'] as int;
        try {
          _database.removeTrackFromPlaylist(playlistId, trackId);
        } catch (e) {
          debugPrint('[CoreBackendHost] Error removing track from playlist $playlistId: $e');
        }
        return null;

      case BackendMethods.playlistsReorderTracks:
        final playlistId = params['playlistId'] as int;
        final oldIndex = params['oldIndex'] as int;
        final newIndex = params['newIndex'] as int;
        try {
          _database.reorderPlaylistEntries(playlistId, oldIndex, newIndex);
        } catch (e) {
          debugPrint('[CoreBackendHost] Error reordering playlist entries: $e');
        }
        return null;

      case BackendMethods.playlistsToggleLike:
        final trackId = params['trackId'] as int;
        final filePath = params['filePath'] as String?;
        try {
          _database.toggleLikeTrack(trackId, filePath);
        } catch (e) {
          debugPrint('[CoreBackendHost] Error toggling like for track $trackId: $e');
        }
        return _database.isTrackLiked(trackId);

      case BackendMethods.playlistsClearHistory:
        try {
          _database.clearHistory();
        } catch (e) {
          debugPrint('[CoreBackendHost] Error clearing history: $e');
        }
        return null;

      // =======================================================================
      // LYRICS
      // =======================================================================
      case BackendMethods.lyricsResolve:
        final allowedSourcesList = params['allowedSources'] as List?;
        int? retryAfterSeconds;
        final result = await _lyricsService.resolveLyrics(
          trackId: params['trackId'] as int,
          filePath: params['filePath'] as String,
          title: params['title'] as String?,
          artist: params['artist'] as String?,
          album: params['album'] as String?,
          durationMs: params['durationMs'] as int?,
          allowRemote: params['allowRemote'] as bool? ?? true,
          bypassCache: params['bypassCache'] as bool? ?? false,
          allowedSources: allowedSourcesList
              ?.map((s) => LyricsSource.fromDbString(s as String))
              .toSet(),
          onThresholdCountdown: (seconds) => retryAfterSeconds = seconds,
        );
        if (result == null && retryAfterSeconds != null) {
          return {'retryAfterSeconds': retryAfterSeconds};
        }
        return result?.toMap();

      case BackendMethods.lyricsTranslate:
        try {
          return await _lyricsService.translateLyrics(
            lyricsId: params['lyricsId'] as int,
            targetLang: params['lang'] as String,
            sourceLang: params['sourceLang'] as String?,
            rawLines: (params['rawLines'] as List).cast<String>(),
          );
        } on LyricsTranslationException catch (e) {
          return {
            'error': e.isRateLimited ? 'rate_limit' : 'translation_error',
            'message': e.message,
            'statusCode': e.statusCode,
          };
        }

      default:
        throw UnimplementedError('Backend method not recognized: $method');
    }
  }

  Future<void> dispose() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    _metadataService.dispose();
    _hostReceivePort.close();
    await _audioEngine.dispose();
    _queueManager.dispose();
    await _database.close();
  }
}
