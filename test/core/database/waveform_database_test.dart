import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/store/library_store.dart';
import 'package:tachyon/shared/utils/waveform_codec.dart';

void main() {
  group('Waveform Database Persistence & Hydration Tests', () {
    late AppDatabase database;

    setUp(() {
      database = AppDatabase.inMemory();
    });

    tearDown(() async {
      await database.close();
    });

    test('upsertTracks persists waveform_data and getCatalogSnapshot returns it in RawTrackDto', () async {
      final sampleWaveform = List.generate(50, (i) => i / 49.0);
      final encodedWaveform = WaveformCodec.encode(sampleWaveform);

      final trackData = ExtractedTrackData(
        filePath: '/music/track_with_waveform.flac',
        title: 'Waveform Track',
        artistNames: ['Audio Analyst'],
        albumName: 'Acoustic Lab',
        genreNames: ['Acoustic'],
        durationMs: 240000,
        fileSize: 12000000,
        modifiedAt: 1234567,
        waveformData: encodedWaveform,
        replayGainTrackGain: -6.5,
        replayGainTrackPeak: 0.95,
      );

      await database.upsertTracks([trackData]);

      final snapshot = await database.getCatalogSnapshot();
      expect(snapshot.tracks.length, equals(1));

      final rawTrack = snapshot.tracks.first;
      expect(rawTrack.title, equals('Waveform Track'));
      expect(rawTrack.waveformData, equals(encodedWaveform));
      expect(rawTrack.replayGainTrackGain, equals(-6.5));
      expect(rawTrack.replayGainTrackPeak, equals(0.95));

      // Test LibraryStore hydration
      final store = LibraryStore();
      store.hydrateFromSnapshot(snapshot);

      expect(store.tracks.length, equals(1));
      final hydratedTrack = store.tracks.first;
      expect(hydratedTrack.waveform, isNotNull);
      expect(hydratedTrack.waveform!.length, equals(50));
      expect(hydratedTrack.waveform![0], closeTo(0.0, 1.0 / 255.0));
      expect(hydratedTrack.waveform![49], closeTo(1.0, 1.0 / 255.0));
      expect(hydratedTrack.replayGainTrackGain, equals(-6.5));
      expect(hydratedTrack.replayGainTrackPeak, equals(0.95));

      // Test LibraryStore.getRandomTracks preserves waveform
      final randomTracks = store.getRandomTracks(1);
      expect(randomTracks.length, equals(1));
      expect(randomTracks.first.waveform, isNotNull);
      expect(randomTracks.first.waveform!.length, equals(50));

      final byId = store.getTrackById(hydratedTrack.id!);
      expect(byId, isNotNull);
      expect(byId!.waveform, isNotNull);
      expect(byId.waveform!.length, equals(50));
    });

    test('upsertTracks handles null waveform_data gracefully', () async {
      final trackData = ExtractedTrackData(
        filePath: '/music/plain_track.mp3',
        title: 'Plain Track',
        artistNames: ['Singer'],
        albumName: 'Album',
        durationMs: 180000,
        fileSize: 4000000,
        modifiedAt: 1000,
        waveformData: null,
      );

      await database.upsertTracks([trackData]);

      final snapshot = await database.getCatalogSnapshot();
      expect(snapshot.tracks.first.waveformData, isNull);

      final store = LibraryStore();
      store.hydrateFromSnapshot(snapshot);

      expect(store.tracks.first.waveform, isNull);
    });
  });
}
