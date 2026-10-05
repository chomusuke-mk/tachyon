import 'dart:async';

import 'package:miniaudio_player/miniaudio_player.dart';

import 'package:tachyon/core/backend/backend_client.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/network/lyrics_rate_limiter.dart';
import 'package:tachyon/core/backend/services/audio_engine_service.dart';
import 'package:tachyon/core/backend/services/cover_cache_service.dart';
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
import 'package:tachyon/features/playback/domain/queue_item.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart'
    show CrossfadeCurve;

/// In-process direct implementation of [TachyonBackendClient].
/// Useful for unit testing and test suites where spawning a background isolate
/// is not necessary.
class DirectTachyonBackendClient implements TachyonBackendClient {
  final AudioEngineService? audioEngine;
  final AppDatabase? database;
  final MetadataService? metadataService;
  final CoverCacheService? coverCacheService;
  final LyricsService? lyricsService;

  final StreamController<List<AudioDevice>> _devicesController =
      StreamController<List<AudioDevice>>.broadcast();
  final StreamController<ScanProgress> _scanProgressController =
      StreamController<ScanProgress>.broadcast();
  final StreamController<void> _catalogUpdatedController =
      StreamController<void>.broadcast();
  StreamSubscription<ScanProgress>? _scanSubscription;

  DirectTachyonBackendClient({
    this.audioEngine,
    this.database,
    this.metadataService,
    this.coverCacheService,
    this.lyricsService,
  });

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
  Future<void> playTrack(Track track, {bool play = true}) async {
    await audioEngine?.open([QueueItem.fromTrack(track)], play: play);
  }

  @override
  Future<void> playQueue(
    List<Track> tracks, {
    int startIndex = 0,
    bool play = true,
  }) async {
    final queueItems = tracks.map((t) => QueueItem.fromTrack(t)).toList();
    await audioEngine?.open(queueItems, index: startIndex, play: play);
  }

  @override
  Future<void> open(
    List<QueueItem> items, {
    int index = 0,
    bool play = true,
    bool shuffle = false,
  }) async {
    await audioEngine?.open(items, index: index, play: play, shuffle: shuffle);
  }

  @override
  Future<void> insertNext(QueueItem item) async =>
      await audioEngine?.insertNext(item);

  @override
  Future<void> append(List<QueueItem> items) async =>
      await audioEngine?.append(items);

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
  }) async =>
      const [];

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
    if (scanner == null) return;
    await _scanSubscription?.cancel();
    _scanSubscription = scanner.scanDirectories(directories).listen((progress) {
      _scanProgressController.add(progress);
      if (progress.phase == ScanPhase.completed) {
        _catalogUpdatedController.add(null);
      }
    });
  }

  @override
  Future<void> cancelScan() async {
    await _scanSubscription?.cancel();
    metadataService?.cancelScan();
  }

  @override
  Future<void> deleteTrack(int trackId) async {
    database?.deleteTrack(trackId);
    _catalogUpdatedController.add(null);
  }

  @override
  Future<void> deleteTracksInFolder(String folderPath) async {
    database?.deleteTracksInFolder(folderPath);
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
  Future<String?> getThumbnail(
    String filePath, {
    ThumbnailQuality quality = ThumbnailQuality.low,
  }) async {
    if (metadataService != null) {
      return await metadataService!.getThumbnail(
        filePath,
        quality: quality,
      );
    }
    if (coverCacheService != null) {
      if (coverCacheService!.hasCachedCover(filePath, quality: quality)) {
        return coverCacheService!.getCoverFile(filePath, quality: quality).path;
      }
    }
    return null;
  }

  @override
  Future<String?> getArtistCover(
    String artistName, {
    ThumbnailQuality quality = ThumbnailQuality.low,
  }) async {
    if (metadataService != null) {
      return await metadataService!.getArtistCover(
        artistName,
        quality: quality,
      );
    }
    if (coverCacheService != null) {
      if (coverCacheService!.hasCachedArtistCover(artistName, quality: quality)) {
        return coverCacheService!
            .getArtistCoverFile(artistName, quality: quality)
            .path;
      }
    }
    return null;
  }

  @override
  Future<void> clearCoverCache() async {
    if (metadataService != null) {
      await metadataService!.clearCoverCache();
    } else if (coverCacheService != null) {
      await coverCacheService!.clearCache();
    }
  }

  @override
  Future<List<Playlist>> getPlaylists() async => const [];

  @override
  Future<int> createPlaylist(String name) async {
    final id = database?.createPlaylist(name) ?? -1;
    _catalogUpdatedController.add(null);
    return id;
  }

  @override
  Future<void> deletePlaylist(int playlistId) async {
    database?.deletePlaylist(playlistId);
    _catalogUpdatedController.add(null);
  }

  @override
  Future<void> renamePlaylist(int playlistId, String name) async {
    database?.renamePlaylist(playlistId, name);
    _catalogUpdatedController.add(null);
  }

  @override
  Future<List<Track>> getPlaylistTracks(int playlistId) async => const [];

  @override
  Future<List<int>> getPlaylistTrackIds(int playlistId) async {
    final ids = database?.getTrackIdsForPlaylist(playlistId);
    return ids?.toList() ?? const [];
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
    _catalogUpdatedController.add(null);
  }

  @override
  Future<void> removeTrackFromPlaylist(int playlistId, int trackId) async {
    database?.removeTrackFromPlaylist(playlistId, trackId);
    _catalogUpdatedController.add(null);
  }

  @override
  Future<void> reorderPlaylistTracks(
    int playlistId,
    int oldIndex,
    int newIndex,
  ) async {
    database?.reorderPlaylistEntries(playlistId, oldIndex, newIndex);
    _catalogUpdatedController.add(null);
  }

  @override
  Future<bool> toggleLikeTrack(int trackId, [String? filePath]) async {
    if (database == null) return false;
    database!.toggleLikeTrack(trackId, filePath);
    _catalogUpdatedController.add(null);
    return database!.isTrackLiked(trackId);
  }

  @override
  Future<bool> isTrackLiked(int trackId) async {
    return database?.isTrackLiked(trackId) ?? false;
  }

  @override
  Future<void> clearHistory() async {
    database?.clearHistory();
    _catalogUpdatedController.add(null);
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
    await _devicesController.close();
    await _scanProgressController.close();
    await _catalogUpdatedController.close();
  }
}
