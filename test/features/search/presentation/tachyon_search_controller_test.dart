import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/search/presentation/tachyon_search_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase db;
  late TachyonSearchController controller;

  const track1 = Track(
    uri: 'file:///music/rock/hotel_california.flac',
    title: 'Hotel California',
    artist: 'Eagles',
    album: 'Hotel California',
    durationMs: 390000,
    fileSize: 20000000,
    modifiedAt: 1600000000,
  );

  const track2 = Track(
    uri: 'file:///music/pop/billie_jean.mp3',
    title: 'Billie Jean',
    artist: 'Michael Jackson',
    album: 'Thriller',
    durationMs: 294000,
    fileSize: 10000000,
    modifiedAt: 1600000001,
  );

  setUp(() async {
    db = AppDatabaseImpl.inMemory();
    await db.init();
    await db.insertOrUpdateTrack(track1);
    await db.insertOrUpdateTrack(track2);
    controller = TachyonSearchController(database: db);
  });

  tearDown(() async {
    controller.dispose();
    await db.close();
  });

  group('TachyonSearchController Initial State', () {
    test('initializes with empty query, all categories, and no results', () {
      expect(controller.query, isEmpty);
      expect(controller.category, equals(SearchFilterCategory.all));
      expect(controller.matchedTracks, isEmpty);
      expect(controller.matchedAlbums, isEmpty);
      expect(controller.matchedArtists, isEmpty);
      expect(controller.isSearching, isFalse);
      expect(controller.isEmptyQuery, isTrue);
      expect(controller.hasResults, isFalse);
    });
  });

  group('TachyonSearchController Search & Debounce', () {
    test('onQueryChanged triggers debounced multi-domain search after 250ms', () async {
      controller.onQueryChanged('Hotel');
      expect(controller.isSearching, isTrue);
      expect(controller.isEmptyQuery, isFalse);

      // Before 250ms elapses
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(controller.matchedTracks, isEmpty);

      // After debounce completes
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(controller.isSearching, isFalse);
      expect(controller.hasResults, isTrue);
      expect(controller.matchedTracks.length, equals(1));
      expect(controller.matchedTracks.first.title, equals('Hotel California'));
      expect(controller.matchedAlbums.length, equals(1));
      expect(controller.matchedAlbums.first.name, equals('Hotel California'));
    });

    test('rapid queries reset debounce timer and execute only final query', () async {
      controller.onQueryChanged('Hot');
      await Future<void>.delayed(const Duration(milliseconds: 100));

      controller.onQueryChanged('Billie');
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(controller.matchedTracks.length, equals(1));
      expect(controller.matchedTracks.first.title, equals('Billie Jean'));
    });

    test('onQueryChanged with empty text immediately clears results', () async {
      controller.onQueryChanged('Michael');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(controller.hasResults, isTrue);

      controller.onQueryChanged('   ');
      expect(controller.isEmptyQuery, isTrue);
      expect(controller.hasResults, isFalse);
      expect(controller.matchedTracks, isEmpty);
      expect(controller.matchedAlbums, isEmpty);
      expect(controller.matchedArtists, isEmpty);
    });
  });

  group('TachyonSearchController Categories & Reset', () {
    test('setCategory updates current filter category', () {
      expect(controller.category, equals(SearchFilterCategory.all));

      controller.setCategory(SearchFilterCategory.albums);
      expect(controller.category, equals(SearchFilterCategory.albums));

      controller.setCategory(SearchFilterCategory.tracks);
      expect(controller.category, equals(SearchFilterCategory.tracks));
    });

    test('clear resets query, category results, and pending timers', () async {
      controller.onQueryChanged('Thriller');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(controller.hasResults, isTrue);

      controller.clear();
      expect(controller.query, isEmpty);
      expect(controller.hasResults, isFalse);
      expect(controller.matchedTracks, isEmpty);
    });
  });
}
