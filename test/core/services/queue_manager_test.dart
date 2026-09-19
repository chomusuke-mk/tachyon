import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/core/services/queue_manager.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  QueueItem createItem(String id, String uri, String title) {
    return QueueItem(
      id: id,
      uri: uri,
      title: title,
      artist: 'Test Artist',
      album: 'Test Album',
      duration: const Duration(seconds: 180),
    );
  }

  Track createTrack(int id, String uri, String title) {
    return Track(
      id: id,
      uri: uri,
      title: title,
      artist: 'Mix Artist',
      album: 'Mix Album',
      durationMs: 180000,
      fileSize: 1024,
      modifiedAt: 1000,
    );
  }

  group('QueueManager Unit Tests', () {
    late List<QueueItem> sampleTracks;

    setUp(() {
      sampleTracks = List.generate(
        5,
        (i) => createItem('id_$i', 'file:///music/song_$i.mp3', 'Song $i'),
      );
    });

    test('initial queue setup retains original and active sequence', () {
      final manager = QueueManager();
      manager.setQueue(sampleTracks, startIndex: 2);

      expect(manager.currentIndex, equals(2));
      expect(manager.currentTrack?.id, equals('id_2'));
      expect(manager.activeQueue.length, equals(5));
      expect(manager.originalQueue.length, equals(5));
      expect(manager.isShuffled, isFalse);
      expect(manager.hasNext, isTrue);
      expect(manager.hasPrevious, isTrue);
    });

    test('empty queue handles operations gracefully without throwing', () async {
      final manager = QueueManager();
      manager.setQueue([]);

      expect(manager.currentIndex, equals(-1));
      expect(manager.currentTrack, isNull);
      expect(manager.hasNext, isFalse);
      expect(manager.hasPrevious, isFalse);

      expect(await manager.next(), isNull);
      expect(manager.previous(), isNull);
      expect(manager.remove(0), isNull);
    });

    test('Fisher-Yates shuffle pins current track at index 0 and avoids immediate duplicate', () {
      final deterministicRandom = math.Random(12345);
      final manager = QueueManager(random: deterministicRandom);
      manager.setQueue(sampleTracks, startIndex: 3, shuffle: true);

      expect(manager.isShuffled, isTrue);
      expect(manager.currentIndex, equals(0));
      // Track at startIndex (id_3) MUST be pinned at index 0
      expect(manager.currentTrack?.id, equals('id_3'));
      expect(manager.activeQueue.first.id, equals('id_3'));

      // All 5 original items must exist in activeQueue
      final activeIds = manager.activeQueue.map((it) => it.id).toSet();
      expect(activeIds, equals(sampleTracks.map((it) => it.id).toSet()));
    });

    test('toggleShuffle / setShuffle preserves track and restores exact original sequence (Un-shuffle)', () {
      final deterministicRandom = math.Random(42);
      final manager = QueueManager(random: deterministicRandom);
      manager.setQueue(sampleTracks, startIndex: 2); // id_2

      // Enable shuffle
      manager.setShuffle(true);
      expect(manager.isShuffled, isTrue);
      expect(manager.currentIndex, equals(0));
      expect(manager.currentTrack?.id, equals('id_2'));

      // Move to next shuffled track
      manager.jumpTo(1);
      final activeTrackBeforeUnshuffle = manager.currentTrack!;

      // Disable shuffle (un-shuffle)
      manager.setShuffle(false);
      expect(manager.isShuffled, isFalse);

      // Active queue must match original sequence exactly
      for (int i = 0; i < sampleTracks.length; i++) {
        expect(manager.activeQueue[i].id, equals(sampleTracks[i].id));
      }

      // Current track pointer must point to the track that was playing
      expect(manager.currentTrack?.id, equals(activeTrackBeforeUnshuffle.id));
      expect(manager.activeQueue[manager.currentIndex].id, equals(activeTrackBeforeUnshuffle.id));
    });

    test('Repeat modes: Loop.off, Loop.one, Loop.all transitions', () async {
      final manager = QueueManager();
      manager.setQueue(sampleTracks, startIndex: 4); // Last track

      // 1. Loop.off at end of queue
      manager.setLoopMode(Loop.off);
      expect(await manager.next(isManual: true), isNull);

      // 2. Loop.all at end of queue wraps around to index 0
      manager.setLoopMode(Loop.all);
      final wrappedTrack = await manager.next(isManual: true);
      expect(wrappedTrack?.id, equals('id_0'));
      expect(manager.currentIndex, equals(0));

      // 3. Loop.one auto-completion (natural progression) stays on current track
      manager.setLoopMode(Loop.one);
      final sameTrack = await manager.next(isManual: false);
      expect(sameTrack?.id, equals('id_0'));
      expect(manager.currentIndex, equals(0));

      // 4. Loop cycle
      expect(manager.cycleLoopMode(), equals(Loop.off));
    });

    test('previous restarts track if position > 3 seconds, else moves to prior track', () {
      final manager = QueueManager();
      manager.setQueue(sampleTracks, startIndex: 2);

      // Position > 3s -> restarts current track
      final restarted = manager.previous(position: const Duration(seconds: 15));
      expect(restarted?.id, equals('id_2'));
      expect(manager.currentIndex, equals(2));

      // Position <= 3s -> moves to prior track
      final prior = manager.previous(position: const Duration(seconds: 1));
      expect(prior?.id, equals('id_1'));
      expect(manager.currentIndex, equals(1));

      // At index 0 with Loop.all wraps to last
      manager.setLoopMode(Loop.all);
      manager.jumpTo(0);
      final wrappedPrev = manager.previous(position: Duration.zero);
      expect(wrappedPrev?.id, equals('id_4'));
      expect(manager.currentIndex, equals(4));
    });

    test('insertNext inserts track immediately following the active track in both queues', () {
      final manager = QueueManager();
      manager.setQueue(sampleTracks, startIndex: 1); // Current is id_1

      final newItem = createItem('id_new', 'file:///music/new.mp3', 'New Song');
      manager.insertNext(newItem);

      expect(manager.currentIndex, equals(1));
      expect(manager.activeQueue[2].id, equals('id_new'));
      expect(manager.originalQueue[2].id, equals('id_new'));
    });

    test('append adds items to end of queues', () {
      final manager = QueueManager();
      manager.setQueue(sampleTracks, startIndex: 0);

      final addedItems = [
        createItem('id_extra_1', 'uri_1', 'Extra 1'),
        createItem('id_extra_2', 'uri_2', 'Extra 2'),
      ];

      manager.append(addedItems);
      expect(manager.activeQueue.length, equals(7));
      expect(manager.activeQueue.last.id, equals('id_extra_2'));
      expect(manager.originalQueue.last.id, equals('id_extra_2'));
    });

    test('remove deletes item and accurately adjusts currentIndex pointer', () {
      final manager = QueueManager();
      manager.setQueue(sampleTracks, startIndex: 2); // Current is id_2

      // Remove an item BEFORE current (id_0)
      final removed = manager.remove(0);
      expect(removed?.id, equals('id_0'));
      expect(manager.activeQueue.length, equals(4));
      // currentIndex must decrement from 2 to 1 to stay on id_2
      expect(manager.currentIndex, equals(1));
      expect(manager.currentTrack?.id, equals('id_2'));

      // Remove the currently playing track (id_2 at index 1)
      final removedCurrent = manager.remove(1);
      expect(removedCurrent?.id, equals('id_2'));
      expect(manager.currentIndex, equals(1));
      expect(manager.currentTrack?.id, equals('id_3'));
    });

    test('reorder shifts track and adjusts currentIndex properly', () {
      final manager = QueueManager();
      manager.setQueue(sampleTracks, startIndex: 2); // Current is id_2

      // Move current track from 2 to 0
      manager.reorder(2, 0);
      expect(manager.currentIndex, equals(0));
      expect(manager.currentTrack?.id, equals('id_2'));

      // Move an item behind current across it (e.g. from 3 to 0)
      manager.reorder(3, 0);
      // id_2 was at 0, now shifts to 1
      expect(manager.currentIndex, equals(1));
      expect(manager.currentTrack?.id, equals('id_2'));
    });

    test('Infinite Library Mix fetches, deduplicates, and appends tracks at queue completion', () async {
      int fetchCalls = 0;
      final manager = QueueManager(
        libraryTrackProvider: (count) async {
          fetchCalls++;
          return [
            createTrack(101, 'file:///music/song_0.mp3', 'Song 0 duplicate'), // Duplicate of sampleTracks[0]
            createTrack(102, 'file:///music/mix_1.mp3', 'Mix Song 1'),
            createTrack(103, 'file:///music/mix_2.mp3', 'Mix Song 2'),
          ];
        },
      );

      manager.setQueue(sampleTracks, startIndex: 4); // At end
      manager.setInfiniteMix(true);
      manager.setLoopMode(Loop.off);

      // Calling next at end of queue triggers Infinite Mix
      final mixTrack = await manager.next(isManual: true);

      expect(fetchCalls, equals(1));
      expect(mixTrack, isNotNull);
      expect(mixTrack?.uri, equals('file:///music/mix_1.mp3'));
      expect(manager.mixOffset, equals(5));
      expect(manager.activeQueue.length, equals(7)); // 5 initial + 2 deduplicated mix tracks
      expect(manager.currentIndex, equals(5));
    });

    test('remove maintains exact length and sequence synchronization with duplicate tracks', () {
      final manager = QueueManager();
      final itemA1 = createItem('id_a1', 'file:///music/song_a.mp3', 'Song A');
      final itemB = createItem('id_b', 'file:///music/song_b.mp3', 'Song B');
      final itemA2 = createItem('id_a2', 'file:///music/song_a.mp3', 'Song A'); // duplicate URI
      final itemC = createItem('id_c', 'file:///music/song_c.mp3', 'Song C');
      final itemA3 = createItem('id_a3', 'file:///music/song_a.mp3', 'Song A'); // duplicate URI

      manager.setQueue([itemA1, itemB, itemA2, itemC, itemA3], startIndex: 0);
      expect(manager.activeQueue.length, equals(5));
      expect(manager.originalQueue.length, equals(5));

      // Remove the middle instance of Song A (index 2)
      final removed = manager.remove(2);
      expect(removed?.id, equals('id_a2'));
      expect(manager.activeQueue.length, equals(4));
      expect(manager.originalQueue.length, equals(4));

      // Active queue should be [itemA1, itemB, itemC, itemA3]
      expect(manager.activeQueue.map((it) => it.id), equals(['id_a1', 'id_b', 'id_c', 'id_a3']));
      expect(manager.originalQueue.map((it) => it.id), equals(['id_a1', 'id_b', 'id_c', 'id_a3']));

      // Toggle shuffle on and off
      manager.setShuffle(true);
      expect(manager.activeQueue.length, equals(4));
      expect(manager.originalQueue.length, equals(4));

      manager.setShuffle(false);
      expect(manager.activeQueue.length, equals(4));
      expect(manager.originalQueue.length, equals(4));
      expect(manager.activeQueue.map((it) => it.id), equals(['id_a1', 'id_b', 'id_c', 'id_a3']));
    });

    test('Infinite Library Mix is strictly bypassed under Loop.all, wrapping to start', () async {
      int fetchCalls = 0;
      final manager = QueueManager(
        libraryTrackProvider: (count) async {
          fetchCalls++;
          return [createTrack(999, 'file:///music/mix.mp3', 'Mix Track')];
        },
      );

      manager.setQueue(sampleTracks, startIndex: 4); // End of queue
      manager.setInfiniteMix(true);
      manager.setLoopMode(Loop.all);

      final nextTrack = await manager.next(isManual: false);
      expect(fetchCalls, equals(0), reason: 'Provider must not be queried when Loop.all is enabled');
      expect(nextTrack?.id, equals('id_0'));
      expect(manager.currentIndex, equals(0));
    });

    test('Fisher-Yates duplicate avoidance searches for first non-duplicate when last item is duplicate', () {
      final itemA0 = createItem('id_a0', 'file:///music/song_a.mp3', 'Song A');
      final itemA1 = createItem('id_a1', 'file:///music/song_a.mp3', 'Song A');
      final itemB = createItem('id_b', 'file:///music/song_b.mp3', 'Song B');
      final itemA2 = createItem('id_a2', 'file:///music/song_a.mp3', 'Song A');

      // Setup a queue where id_a0 is current, and remaining has [itemA1, itemB, itemA2]
      // Notice remaining[0] and remaining.last both have URI matching itemA0.
      final deterministicRandom = math.Random(10);
      final manager = QueueManager(random: deterministicRandom);
      manager.setQueue([itemA0, itemA1, itemB, itemA2], startIndex: 0, shuffle: true);

      expect(manager.activeQueue.first.id, equals('id_a0'));
      // The track immediately following activeQueue[0] must NOT have URI matching itemA0
      expect(manager.activeQueue[1].uri, isNot(equals('file:///music/song_a.mp3')));
      expect(manager.activeQueue[1].id, equals('id_b'));
    });
  });
}
