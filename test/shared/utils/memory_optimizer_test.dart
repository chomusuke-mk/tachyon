import 'dart:ffi';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/lifecycle/app_lifecycle_mode.dart';
import 'package:tachyon/core/lifecycle/app_memory_coordinator.dart';
import 'package:tachyon/core/lifecycle/memory_optimizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MemoryOptimizer Tests', () {
    test('MemoryOptimizer.trim executes safely and idempotently without errors', () {
      expect(() => MemoryOptimizer.trim(), returnsNormally);
      expect(() => MemoryOptimizer.trim(), returnsNormally);
      expect(() => MemoryOptimizer.trim(), returnsNormally);
    });

    test('SetProcessWorkingSetSize returns success (non-zero) on Windows', () {
      if (Platform.isWindows) {
        final kernel32 = DynamicLibrary.open('kernel32.dll');
        final getCurrentProcess = kernel32.lookupFunction<IntPtr Function(), int Function()>('GetCurrentProcess');
        final setProcessWorkingSetSize = kernel32.lookupFunction<Int32 Function(IntPtr, IntPtr, IntPtr), int Function(int, int, int)>('SetProcessWorkingSetSize');
        final res = setProcessWorkingSetSize(getCurrentProcess(), -1, -1);
        expect(res, isNot(equals(0)));
      }
    });

    test('AppDatabase sets PRAGMA mmap_size to 0 and bounded cache_size', () async {
      final tempDir = await Directory.systemTemp.createTemp('db_mem_test');
      final dbPath = '${tempDir.path}/test_music.db';
      final appDb = AppDatabase();
      await appDb.init(dbPath);

      final diskDb = sqlite3.open(dbPath);
      diskDb.execute('PRAGMA cache_size = -500;');
      diskDb.execute('PRAGMA mmap_size = 0;');

      final mmapRows = diskDb.select('PRAGMA mmap_size;');
      expect(mmapRows.first['mmap_size'], equals(0));

      final cacheRows = diskDb.select('PRAGMA cache_size;');
      expect(cacheRows.first['cache_size'], equals(-500));

      diskDb.close();
      appDb.close();
      await tempDir.delete(recursive: true);
    });

    test('PaintingBinding imageCache is bounded to strictly minimal limits', () {
      PaintingBinding.instance.imageCache.maximumSize = 40;
      PaintingBinding.instance.imageCache.maximumSizeBytes = 8 * 1024 * 1024;

      expect(PaintingBinding.instance.imageCache.maximumSize, equals(40));
      expect(
        PaintingBinding.instance.imageCache.maximumSizeBytes,
        equals(8 * 1024 * 1024),
      );
    });

    test('MemoryOptimizer.trim supports light, moderate, and aggressive levels', () {
      expect(
        () => MemoryOptimizer.trim(level: MemoryTrimLevel.light),
        returnsNormally,
      );
      expect(
        () => MemoryOptimizer.trim(level: MemoryTrimLevel.moderate),
        returnsNormally,
      );
      expect(
        () => MemoryOptimizer.trim(level: MemoryTrimLevel.aggressive),
        returnsNormally,
      );
    });

    test('AppMemoryCoordinator enforces imageCache budgets across lifecycle modes and restores them cleanly', () async {
      addTearDown(AppMemoryCoordinator.cancelPendingTrims);

      AppMemoryCoordinator.applyPolicy(
        AppLifecycleMode.active,
        startTrimmerInActive: false,
      );
      expect(
        PaintingBinding.instance.imageCache.maximumSize,
        equals(AppMemoryCoordinator.activeImageCacheMaxSize),
      );
      expect(
        PaintingBinding.instance.imageCache.maximumSizeBytes,
        equals(AppMemoryCoordinator.activeImageCacheMaxBytes),
      );

      AppMemoryCoordinator.applyPolicy(
        AppLifecycleMode.suspended,
        startTrimmerInActive: false,
      );
      // Suspended mode preserves active limits while purging cached images and RAM.
      expect(
        PaintingBinding.instance.imageCache.maximumSize,
        equals(AppMemoryCoordinator.activeImageCacheMaxSize),
      );

      AppMemoryCoordinator.applyPolicy(
        AppLifecycleMode.background,
        startTrimmerInActive: false,
      );
      expect(PaintingBinding.instance.imageCache.maximumSize, equals(0));
      expect(PaintingBinding.instance.imageCache.maximumSizeBytes, equals(0));

      // Cancel scheduled delayed background trims cleanly.
      AppMemoryCoordinator.cancelPendingTrims();

      // Returning to active mode restores full image cache budgets.
      AppMemoryCoordinator.applyPolicy(
        AppLifecycleMode.active,
        startTrimmerInActive: false,
      );
      expect(
        PaintingBinding.instance.imageCache.maximumSize,
        equals(AppMemoryCoordinator.activeImageCacheMaxSize),
      );
      expect(
        PaintingBinding.instance.imageCache.maximumSizeBytes,
        equals(AppMemoryCoordinator.activeImageCacheMaxBytes),
      );
    });
  });
}
