import 'dart:async';

import 'package:miniaudio_player/miniaudio_player.dart';

import 'package:tachyon/core/backend/backend_client.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/network/lyrics_rate_limiter.dart';
import 'package:tachyon/core/backend/services/audio_engine_service.dart';
import 'package:tachyon/core/backend/services/lyrics_service.dart';
import 'package:tachyon/core/backend/services/metadata_service.dart';
import 'package:tachyon/features/library/domain/album.dart';
import 'package:tachyon/features/library/domain/artist.dart';
import 'package:tachyon/features/library/domain/catalog_snapshot.dart';
import 'package:tachyon/features/library/domain/genre.dart';
import 'package:tachyon/features/library/domain/playlist.dart';
import 'package:tachyon/features/library/domain/scan_progress.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/library/domain/track_sort_option.dart';
import 'package:tachyon/features/playback/domain/crossfade_config.dart';
import 'package:tachyon/features/playback/domain/lyric_source.dart';
import 'package:tachyon/features/playback/domain/playback_state.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart'
    show CrossfadeCurve;

/// In-process direct implementation of [TachyonBackendClient].
/// Useful for unit testing and test suites where spawning a background isolate
/// is not necessary.
class DirectTachyonBackendClient implements TachyonBackendClient {
  final AudioEngineService? audioEngine;
  final AppDatabase? database;
  final MetadataService? metadataService;
  final LyricsService? lyricsService;

  final StreamController<List<AudioDevice>> _devicesController =
      StreamController<List<AudioDevice>>.broadcast();
  final StreamController<ScanProgress> _scanProgressController =
      StreamController<ScanProgress>.broadcast(sync: true);
  final StreamController<void> _catalogUpdatedController =
      StreamController<void>.broadcast();
  StreamSubscription<ScanProgress>? _scanSubscription;

  DirectTachyonBackendClient({
    this.audioEngine,
    this.database,
    this.metadataService,
    this.lyricsService,
  }) {
    if (metadataService != null) {
      _scanSubscription = metadataService!.progressStream.listen((progress) {
        if (!_scanProgressController.isClosed) {
          _scanProgressController.add(progress);
        }
        if (progress.stage == ScanStage.completed) {
          if (!_catalogUpdatedController.isClosed) {
            _catalogUpdatedController.add(null);
          }
        }
      });
    }
  }

  @override
  Stream<PlaybackState> get playbackStateStream {
    try {
      return audioEngine?.stateStream ?? const Stream.empty();
    } catch (_) {
      return const Stream.empty();
    }
  }

  @override
  Stream<Duration> get positionStream {
    try {
      return audioEngine?.positionStream ?? const Stream.empty();
    } catch (_) {
      return const Stream.empty();
    }
  }

  @override
  Stream<List<AudioDevice>> get devicesStream => _devicesController.stream;

  @override
  Stream<ScanProgress> get scanProgressStream => _scanProgressController.stream;

  /// Test-only hook to emit synthetic scan progress events.
  void emitScanProgress(ScanProgress progress) {
    _scanProgressController.add(progress);
  }

  @override
  Stream<void> get catalogUpdatedStream => _catalogUpdatedController.stream;

  @override
  Future<void> play() async => await audioEngine?.play();

  @override
  Future<void> pause() async => await audioEngine?.pause();

  @override
  Future<void> stop() async => await audioEngine?.stop();

  @override
  Future<void> seek(Duration position) async =>
      await audioEngine?.seek(position);

  @override
  Future<void> next() async => await audioEngine?.next();

  @override
  Future<void> previous() async => await audioEngine?.previous();

  @override
  Future<void> setVolume(double volume) async =>
      await audioEngine?.setVolume(volume);

  @override
  Future<void> setRate(double rate) async => await audioEngine?.setRate(rate);

  @override
  Future<void> setPitch(double pitch) async =>
      await audioEngine?.setPitch(pitch);

  @override
  Future<void> setSkipSilence(bool enabled) async =>
      await audioEngine?.setSkipSilence(enabled);

  @override
  Future<void> setEqualizer(Equalizer equalizer) async =>
      await audioEngine?.setEqualizer(equalizer);

  @override
  Future<void> setOutputDevice(AudioDevice device) async =>
      await audioEngine?.setDevice(device);

  @override
  Future<List<AudioDevice>> getAudioDevices() async =>
      await audioEngine?.getAudioDevices() ?? const [];

  @override
  Future<void> playTrack(int trackId, {bool play = true}) async {
    final track = database?.getTrackById(trackId);
    if (track != null) {
      final entry = PlaylistEntry.forQueue(id: 0, position: 0, track: track);
      await audioEngine?.open([entry], play: play);
    }
  }

  @override
  Future<void> playQueue(
    List<int> trackIds, {
    int? startIndex,
    bool play = true,
    bool shuffle = false,
  }) async {
    final tracks = database?.getTracksByIds(trackIds) ?? const <Track>[];
    final entries = [
      for (int i = 0; i < tracks.length; i++)
        PlaylistEntry.forQueue(id: i, position: i, track: tracks[i]),
    ];
    await audioEngine?.open(
      entries,
      index: startIndex,
      play: play,
      shuffle: shuffle,
    );
  }

  @override
  Future<void> open(
    List<int> trackIds, {
    int? index,
    bool play = true,
    bool shuffle = false,
  }) async {
    final tracks = database?.getTracksByIds(trackIds) ?? const <Track>[];
    final entries = [
      for (int i = 0; i < tracks.length; i++)
        PlaylistEntry.forQueue(id: i, position: i, track: tracks[i]),
    ];
    await audioEngine?.open(
      entries,
      index: index,
      play: play,
      shuffle: shuffle,
    );
  }

  @override
  Future<void> insertNext(int trackId) async {
    final track = database?.getTrackById(trackId);
    if (track != null) {
      final entry = PlaylistEntry.forQueue(id: 0, position: 0, track: track);
      await audioEngine?.insertNext(entry);
    }
  }

  @override
  Future<void> append(List<int> trackIds) async {
    final tracks = database?.getTracksByIds(trackIds) ?? const <Track>[];
    final entries = [
      for (int i = 0; i < tracks.length; i++)
        PlaylistEntry.forQueue(id: i, position: i, track: tracks[i]),
    ];
    await audioEngine?.append(entries);
  }

  @override
  Future<void> skipToIndex(int index) async =>
      await audioEngine?.skipToIndex(index);

  @override
  Future<void> setShuffle(bool enabled) async =>
      await audioEngine?.setShuffle(enabled);

  @override
  Future<void> setLoopMode(Loop mode) async =>
      await audioEngine?.setLoopMode(mode);

  @override
  Future<void> removeQueueItem(int index) async =>
      await audioEngine?.remove(index);

  @override
  Future<void> reorderQueue(int oldIndex, int newIndex) async =>
      await audioEngine?.reorder(oldIndex, newIndex);

  @override
  Future<void> clearQueue() async => await audioEngine?.clearQueue();

  @override
  Future<PlaybackState> getPlaybackState() async =>
      audioEngine?.state ?? const PlaybackState.initial();

  @override
  Future<void> setCrossfadeDuration(Duration duration) async =>
      await audioEngine?.setCrossfadeDuration(duration);

  @override
  Future<void> setCrossfadeCurve(CrossfadeCurve curve) async =>
      await audioEngine?.setCrossfadeCurve(curve);

  @override
  Future<void> setCrossfadeConfig(CrossfadeConfig config) async =>
      await audioEngine?.setCrossfadeConfig(config);

  @override
  Future<void> setInfiniteMix(bool enabled) async =>
      await audioEngine?.setInfiniteMix(enabled);

  @override
  Future<CatalogSnapshot> getCatalogSnapshot() async {
    return database?.getCatalogSnapshot() ?? const CatalogSnapshot.empty();
  }

  @override
  Future<List<Track>> getTracks({
    TrackSortOption? sort,
    bool ascending = true,
  }) async => const [];

  @override
  Future<List<Album>> getAlbums() async => const [];

  @override
  Future<List<Artist>> getArtists() async => const [];

  @override
  Future<List<Genre>> getGenres() async => const [];

  @override
  Future<List<Track>> getAlbumTracks(int albumId) async => const [];

  @override
  Future<List<Track>> getArtistTracks(int artistId) async => const [];

  @override
  Future<void> startScan(String directoryPath) async {
    await startScanDirectories([directoryPath]);
  }

  @override
  Future<void> startScanDirectories(List<String> directories) async {
    final scanner = metadataService;
    if (scanner == null) {
      if (!_scanProgressController.isClosed) {
        _scanProgressController
            .add(const ScanProgress(stage: ScanStage.gettingDatabase));
      }
      return;
    }
    scanner.scanDirectories(directories);
  }

  @override
  Future<void> cancelScan() async {
    metadataService?.cancelScan();
    if (metadataService == null && !_scanProgressController.isClosed) {
      _scanProgressController
          .add(const ScanProgress(stage: ScanStage.cancelled));
    }
  }

  @override
  Future<void> deleteTrack(int trackId) async {
    database?.deleteTrack(trackId);
    _catalogUpdatedController.add(null);
  }

  @override
  Future<ExtractedTrackData?> getMetadata(String filePath) async {
    if (metadataService != null) {
      return await metadataService!.getMetadata(filePath);
    }
    return null;
  }

  @override
  Future<int> createPlaylist(String name) async {
    return database?.createPlaylist(name) ?? -1;
  }

  @override
  Future<void> deletePlaylist(int playlistId) async {
    database?.deletePlaylist(playlistId);
  }

  @override
  Future<void> renamePlaylist(int playlistId, String name) async {
    database?.renamePlaylist(playlistId, name);
  }

  @override
  Future<void> addTracksToPlaylist(int playlistId, List<int> trackIds) async {
    if (database == null) return;
    try {
      database!.addTracksToPlaylist(playlistId, trackIds);
    } catch (_) {
      for (final id in trackIds) {
        try {
          database!.addTrackToPlaylist(playlistId, id);
        } catch (_) {}
      }
    }
  }

  @override
  Future<void> removeTrackFromPlaylist(int playlistId, int trackId) async {
    database?.removeTrackFromPlaylist(playlistId, trackId);
  }

  @override
  Future<void> reorderPlaylistTracks(
    int playlistId,
    int oldIndex,
    int newIndex,
  ) async {
    database?.reorderPlaylistEntries(playlistId, oldIndex, newIndex);
  }

  @override
  Future<bool> toggleLikeTrack(int trackId, [String? filePath]) async {
    if (database == null) return false;
    database!.toggleLikeTrack(trackId, filePath);
    return database!.isTrackLiked(trackId);
  }

  @override
  Future<void> clearHistory() async {
    database?.clearHistory();
  }

  @override
  Future<LyricsResult?> resolveLyrics({
    required int trackId,
    required String filePath,
    String? title,
    String? artist,
    String? album,
    int? durationMs,
    bool allowRemote = true,
    bool bypassCache = false,
    Set<LyricsSource>? allowedSources,
    LyricsCancellationToken? cancellationToken,
    void Function(int seconds)? onThresholdCountdown,
  }) async {
    return await lyricsService?.resolveLyrics(
      trackId: trackId,
      filePath: filePath,
      title: title,
      artist: artist,
      album: album,
      durationMs: durationMs,
      allowRemote: allowRemote,
      bypassCache: bypassCache,
      allowedSources: allowedSources,
      cancellationToken: cancellationToken,
      onThresholdCountdown: onThresholdCountdown,
    );
  }

  @override
  Future<List<String>?> translateLyrics({
    required int lyricsId,
    required String targetLang,
    String? sourceLang,
    required List<String> rawLines,
  }) async {
    return await lyricsService?.translateLyrics(
      lyricsId: lyricsId,
      targetLang: targetLang,
      sourceLang: sourceLang,
      rawLines: rawLines,
    );
  }

  @override
  Future<void> dispose() async {
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    metadataService?.dispose();
    await _devicesController.close();
    await _scanProgressController.close();
    await _catalogUpdatedController.close();
  }
}
