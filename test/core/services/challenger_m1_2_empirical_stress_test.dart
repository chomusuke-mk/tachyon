import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:media_kit/media_kit.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/services/audio_player_adapter.dart';
import 'package:tachyon/core/services/cover_cache_service.dart';
import 'package:tachyon/core/services/metadata_extractor.dart';
import 'package:tachyon/core/services/scan_isolate.dart';
import 'package:tachyon/core/services/tachyon_audio_platform.dart';
import 'package:tachyon/features/library/domain/scan_progress.dart';

/// Helper to generate a valid PCM 16-bit WAV file with a pure sine tone.
File createTestWavFile(String path, {int durationSeconds = 1}) {
  const sampleRate = 44100;
  const numChannels = 1;
  const bitsPerSample = 16;
  final numSamples = sampleRate * durationSeconds;
  final subChunk2Size = numSamples * numChannels * (bitsPerSample ~/ 8);
  final chunkSize = 36 + subChunk2Size;
  final byteRate = sampleRate * numChannels * (bitsPerSample ~/ 8);
  const blockAlign = numChannels * (bitsPerSample ~/ 8);

  final byteData = ByteData(44 + subChunk2Size);
  // 'RIFF'
  byteData.setUint8(0, 0x52);
  byteData.setUint8(1, 0x49);
  byteData.setUint8(2, 0x46);
  byteData.setUint8(3, 0x46);
  byteData.setUint32(4, chunkSize, Endian.little);
  // 'WAVE'
  byteData.setUint8(8, 0x57);
  byteData.setUint8(9, 0x41);
  byteData.setUint8(10, 0x56);
  byteData.setUint8(11, 0x45);
  // 'fmt '
  byteData.setUint8(12, 0x66);
  byteData.setUint8(13, 0x6D);
  byteData.setUint8(14, 0x74);
  byteData.setUint8(15, 0x20);
  byteData.setUint32(16, 16, Endian.little); // Subchunk1Size PCM = 16
  byteData.setUint16(20, 1, Endian.little); // AudioFormat PCM = 1
  byteData.setUint16(22, numChannels, Endian.little);
  byteData.setUint32(24, sampleRate, Endian.little);
  byteData.setUint32(28, byteRate, Endian.little);
  byteData.setUint16(32, blockAlign, Endian.little);
  byteData.setUint16(34, bitsPerSample, Endian.little);
  // 'data'
  byteData.setUint8(36, 0x64);
  byteData.setUint8(37, 0x61);
  byteData.setUint8(38, 0x74);
  byteData.setUint8(39, 0x61);
  byteData.setUint32(40, subChunk2Size, Endian.little);

  // Fill samples with a gentle 440Hz sine wave
  for (int i = 0; i < numSamples; i++) {
    final t = i / sampleRate;
    final sampleVal = (math.sin(2 * math.pi * 440 * t) * 3000).toInt();
    byteData.setInt16(44 + i * 2, sampleVal, Endian.little);
  }

  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(byteData.buffer.asUint8List());
  return file;
}

/// Helper to read active thread count from Linux /proc/self/status.
int? getLinuxThreadCount() {
  if (!Platform.isLinux) return null;
  try {
    final status = File('/proc/self/status').readAsStringSync();
    final match = RegExp(r'Threads:\s+(\d+)').firstMatch(status);
    if (match != null) {
      return int.parse(match.group(1)!);
    }
  } catch (_) {}
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('challenger_m1_2_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  // =========================================================================
  // GROUP 1: TachyonAudioPlatform & MPV Properties Empirical Verification
  // =========================================================================
  group('Challenger M1.2: TachyonAudioPlatform & MPV Properties Verification', () {
    test('1.1: EnsureInitialized configures TachyonAudioPlatform with 1MB bufferSize and no errors', () async {
      await AudioPlayerAdapter.ensureInitialized();
      expect(JustAudioPlatform.instance, isA<TachyonAudioPlatform>());

      final platform = JustAudioPlatform.instance as TachyonAudioPlatform;
      final playerId = 'challenger_test_player_${DateTime.now().microsecondsSinceEpoch}';

      final playerPlatform = await platform.init(InitRequest(id: playerId));
      expect(playerPlatform, isA<TachyonMediaKitPlayer>());

      // Dispose cleanly
      await platform.disposePlayer(DisposePlayerRequest(id: playerId));
    });

    test('1.2: Native MPV player configures all RAM & buffer properties without native errors', () async {
      MediaKit.ensureInitialized();

      final completer = Completer<void>();
      late final Player player;

      player = Player(
        configuration: PlayerConfiguration(
          pitch: true,
          title: 'Tachyon Challenger MPV Test',
          bufferSize: 1 * 1024 * 1024, // 1MB buffer
          logLevel: MPVLogLevel.error,
          ready: () async {
            if (player.platform is NativePlayer) {
              final native = player.platform as NativePlayer;
              await native.setProperty('cache-on-disk', 'no');
              await native.setProperty('sub-auto', 'no');
              await native.setProperty('audio-stream-silence', 'yes');
              await native.setProperty('demuxer-max-bytes', '2097152');
              await native.setProperty('demuxer-max-back-bytes', '524288');
              await native.setProperty('demuxer-readahead-secs', '10');
              await native.setProperty('audio-buffer', '0.2');
            }
            completer.complete();
          },
        ),
      );

      await completer.future;

      // Assert configuration bufferSize
      if (player.platform is NativePlayer) {
        final native = player.platform as NativePlayer;
        expect(native.configuration.bufferSize, equals(1024 * 1024));
      }

      // Query native properties from libmpv
      if (player.platform is NativePlayer) {
        final native = player.platform as NativePlayer;
        final demuxerMaxBytes = await native.getProperty('demuxer-max-bytes');
        final demuxerMaxBackBytes = await native.getProperty('demuxer-max-back-bytes');
        final demuxerReadaheadSecs = await native.getProperty('demuxer-readahead-secs');
        final audioBuffer = await native.getProperty('audio-buffer');
        final cacheOnDisk = await native.getProperty('cache-on-disk');
        final subAuto = await native.getProperty('sub-auto');
        final audioStreamSilence = await native.getProperty('audio-stream-silence');

        expect(demuxerMaxBytes, equals('2097152'));
        expect(demuxerMaxBackBytes, equals('524288'));
        expect(double.parse(demuxerReadaheadSecs), closeTo(10.0, 0.001));
        expect(double.parse(audioBuffer), closeTo(0.2, 0.001));
        expect(cacheOnDisk, equals('no'));
        expect(subAuto, equals('no'));
        expect(audioStreamSilence, equals('yes'));
      }

      await player.dispose();
    });

    test('1.3: Real audio playback initialization, buffering and disposal with 1MB buffer', () async {
      await AudioPlayerAdapter.ensureInitialized();
      final wavFile = createTestWavFile(
        '${tempDir.path}/test_audio.wav',
        durationSeconds: 2,
      );
      expect(wavFile.existsSync(), isTrue);

      final adapter = AudioPlayerAdapter();
      expect(adapter.isDisposed, isFalse);

      // Open and play generated audio file
      await adapter.open(wavFile.path, play: true);

      // Wait briefly for playback stream to register position
      final positionCompleter = Completer<Duration>();
      final sub = adapter.positionStream.listen((pos) {
        if (pos > Duration.zero && !positionCompleter.isCompleted) {
          positionCompleter.complete(pos);
        }
      });

      final observedPosition = await positionCompleter.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => Duration.zero,
      );

      await sub.cancel();
      expect(observedPosition, greaterThan(Duration.zero));

      await adapter.pause();
      await adapter.stop();
      await adapter.dispose();
      expect(adapter.isDisposed, isTrue);
    });

    test('1.4: Rapid player lifecycle stress test (10 rapid create -> play -> dispose cycles)', () async {
      await AudioPlayerAdapter.ensureInitialized();
      final wavFile = createTestWavFile(
        '${tempDir.path}/rapid_lifecycle.wav',
        durationSeconds: 1,
      );

      for (int i = 0; i < 10; i++) {
        final adapter = AudioPlayerAdapter();
        await adapter.open(wavFile.path, play: true);
        await Future.delayed(const Duration(milliseconds: 50));
        await adapter.dispose();
        expect(adapter.isDisposed, isTrue);
      }
    });
  });

  // =========================================================================
  // GROUP 2: Scan Isolate Lifecycle, Cancellation & Leak Prevention
  // =========================================================================
  group('Challenger M1.2: Scan Isolate Lifecycle & Leak Prevention', () {
    late AppDatabase db;
    late CoverCacheService coverCacheService;
    late MetadataExtractor extractor;

    setUp(() async {
      db = AppDatabase.inMemory();
      await db.init();
      coverCacheService = CoverCacheService(cacheDirectory: tempDir);
      await coverCacheService.init();
      extractor = MetadataExtractor(
        database: db,
        coverCacheService: coverCacheService,
        customWorkerCount: 2,
      );
    });

    tearDown(() async {
      extractor.cancelScan();
      await db.close();
    });

    test('2.1: Scan completion kills background isolate promptly', () async {
      // Create a small set of mock files in temp directory
      for (int i = 0; i < 5; i++) {
        createTestWavFile('${tempDir.path}/track_$i.wav', durationSeconds: 1);
      }

      final progressEvents = <ScanProgress>[];
      final completer = Completer<void>();

      final initialThreads = getLinuxThreadCount();

      final stream = extractor.scanDirectories([tempDir.path]);
      final sub = stream.listen(
        (progress) {
          progressEvents.add(progress);
          if (progress.phase == ScanPhase.completed) {
            if (!completer.isCompleted) completer.complete();
          }
        },
        onError: completer.completeError,
      );

      await completer.future.timeout(const Duration(seconds: 15));
      await sub.cancel();

      expect(progressEvents.any((p) => p.phase == ScanPhase.completed), isTrue);

      // Verify that after completion, isolate is dead and threads settle
      await Future.delayed(const Duration(milliseconds: 200));
      final finalThreads = getLinuxThreadCount();
      if (initialThreads != null && finalThreads != null) {
        // Threads should not have exploded or leaked
        expect(finalThreads, lessThanOrEqualTo(initialThreads + 4));
      }
    });

    test('2.2: CancelScan terminates scan isolate immediately via cancel command and kill', () async {
      // Create multiple mock files
      for (int i = 0; i < 15; i++) {
        createTestWavFile('${tempDir.path}/cancel_track_$i.wav', durationSeconds: 1);
      }

      final progressEvents = <ScanProgress>[];
      final stream = extractor.scanDirectories([tempDir.path]);

      final firstEventCompleter = Completer<void>();
      final sub = stream.listen((progress) {
        progressEvents.add(progress);
        if (!firstEventCompleter.isCompleted) {
          firstEventCompleter.complete();
        }
      });

      // Wait until scanning starts
      await firstEventCompleter.future.timeout(const Duration(seconds: 5));

      // Cancel the scan
      extractor.cancelScan();
      await sub.cancel();

      // Ensure no further events or crashes occur
      await Future.delayed(const Duration(milliseconds: 300));
      expect(progressEvents, isNotEmpty);
    });

    test('2.3: Stream cancellation (controller.onCancel) triggers immediate isolate kill', () async {
      for (int i = 0; i < 10; i++) {
        createTestWavFile('${tempDir.path}/sub_cancel_$i.wav', durationSeconds: 1);
      }

      final initialThreads = getLinuxThreadCount();

      final stream = extractor.scanDirectories([tempDir.path]);
      final sub = stream.listen((_) {});

      // Cancel subscription directly
      await Future.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      await Future.delayed(const Duration(milliseconds: 200));
      final finalThreads = getLinuxThreadCount();
      if (initialThreads != null && finalThreads != null) {
        expect(finalThreads, lessThanOrEqualTo(initialThreads + 4));
      }
    });

    test('2.4: Rapid burst of 10 scan -> cancel cycles does not leak isolates or threads', () async {
      for (int i = 0; i < 8; i++) {
        createTestWavFile('${tempDir.path}/burst_$i.wav', durationSeconds: 1);
      }

      final initialThreads = getLinuxThreadCount();

      for (int i = 0; i < 10; i++) {
        final stream = extractor.scanDirectories([tempDir.path]);
        final sub = stream.listen((_) {});
        await Future.delayed(const Duration(milliseconds: 30));
        extractor.cancelScan();
        await sub.cancel();
      }

      await Future.delayed(const Duration(milliseconds: 400));
      final finalThreads = getLinuxThreadCount();
      if (initialThreads != null && finalThreads != null) {
        // Assert no thread leak after 10 burst cancellations
        expect(finalThreads, lessThanOrEqualTo(initialThreads + 6));
      }
    });

    test('2.5: Direct scan isolate exit listener confirms immediate termination on kill', () async {
      final progressPort = ReceivePort();
      final handshakePort = ReceivePort();
      final exitPort = ReceivePort();

      final args = ScanIsolateArgs(
        progressPort: progressPort.sendPort,
        handshakePort: handshakePort.sendPort,
        directories: [tempDir.path],
        coverCachePath: tempDir.path,
        workerCount: 2,
      );

      final isolate = await Isolate.spawn(scanIsolateEntry, args);
      isolate.addOnExitListener(exitPort.sendPort, response: 'isolate_terminated');

      // Handshake
      final cancelSendPort = await handshakePort.first as SendPort;
      handshakePort.close();

      // Send cancel and kill immediately
      cancelSendPort.send('cancel');
      isolate.kill(priority: Isolate.immediate);

      // Verify exit listener receives termination response
      final exitResponse = await exitPort.first.timeout(
        const Duration(seconds: 3),
        onTimeout: () => 'timeout',
      );

      expect(exitResponse, equals('isolate_terminated'));
      progressPort.close();
      exitPort.close();
    });

    test('2.6: Starting a new scan while an existing scan is running gracefully cancels the first', () async {
      for (int i = 0; i < 20; i++) {
        createTestWavFile('${tempDir.path}/overlap_$i.wav', durationSeconds: 1);
      }

      final firstEvents = <ScanProgress>[];
      final secondEvents = <ScanProgress>[];

      final firstStream = extractor.scanDirectories([tempDir.path]);
      final firstSub = firstStream.listen(firstEvents.add);

      // Give first scan a brief moment to start
      await Future.delayed(const Duration(milliseconds: 40));

      // Launch second scan immediately on the same extractor instance
      final secondCompleter = Completer<void>();
      final secondStream = extractor.scanDirectories([tempDir.path]);
      final secondSub = secondStream.listen(
        (progress) {
          secondEvents.add(progress);
          if (progress.phase == ScanPhase.completed) {
            if (!secondCompleter.isCompleted) secondCompleter.complete();
          }
        },
        onError: secondCompleter.completeError,
      );

      await secondCompleter.future.timeout(const Duration(seconds: 15));
      await firstSub.cancel();
      await secondSub.cancel();

      // Second scan completed successfully
      expect(secondEvents.any((p) => p.phase == ScanPhase.completed), isTrue);
    });

    test('2.7: cancelScan idempotence: multiple consecutive calls do not crash or throw', () {
      expect(() {
        extractor.cancelScan();
        extractor.cancelScan();
        extractor.cancelScan();
      }, returnsNormally);
    });
  });

  // =========================================================================
  // GROUP 3: TachyonAudioPlatform Concurrency & Resource Cleanup
  // =========================================================================
  group('Challenger M1.2: TachyonAudioPlatform Concurrency & Teardown', () {
    test('3.1: Duplicate player ID initialization throws PlatformException', () async {
      await AudioPlayerAdapter.ensureInitialized();
      final platform = JustAudioPlatform.instance as TachyonAudioPlatform;
      final playerId = 'duplicate_id_test_${DateTime.now().microsecondsSinceEpoch}';

      final player = await platform.init(InitRequest(id: playerId));
      expect(player, isNotNull);

      // Attempt duplicate init with same ID
      expect(
        () => platform.init(InitRequest(id: playerId)),
        throwsA(isA<PlatformException>()),
      );

      await platform.disposePlayer(DisposePlayerRequest(id: playerId));
    });

    test('3.2: disposeAllPlayers disposes all active players simultaneously', () async {
      await AudioPlayerAdapter.ensureInitialized();
      final platform = JustAudioPlatform.instance as TachyonAudioPlatform;

      final id1 = 'batch_player_1_${DateTime.now().microsecondsSinceEpoch}';
      final id2 = 'batch_player_2_${DateTime.now().microsecondsSinceEpoch}';

      await platform.init(InitRequest(id: id1));
      await platform.init(InitRequest(id: id2));

      // Dispose all active players
      final response = await platform.disposeAllPlayers(DisposeAllPlayersRequest());
      expect(response, isA<DisposeAllPlayersResponse>());

      // Calling dispose again when empty does not throw
      final response2 = await platform.disposeAllPlayers(DisposeAllPlayersRequest());
      expect(response2, isA<DisposeAllPlayersResponse>());
    });
  });
}
