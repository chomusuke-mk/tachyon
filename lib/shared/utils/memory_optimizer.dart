import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Cross-platform low-level memory optimizer.
///
/// Dispatches native OS kernel and CRT/libc commands to flush unreferenced
/// physical memory pages from the process working set (on Windows) or heap
/// arenas (on Linux) back to the operating system, minimizing RSS and RAM usage.
class MemoryOptimizer {
  static bool _initialized = false;
  static void Function({required bool aggressive})? _platformTrimmer;

  // Android Bionic Scudo / Jemalloc mallopt constants (from <malloc.h>)
  static const int _mDecayTime = -100;
  static const int _mPurge = -101;
  static const int _mPurgeAll = -104;
  static const int _mCacheCountMax = -200;
  static const int _mCacheSizeMax = -201;

  // Linux / Android madvise constants (from <sys/mman.h>)
  static const int _madvDontNeed = 4;
  static const int _madvCold = 20;
  static const int _madvPageOut = 21;

  /// Ensures native dynamic libraries and function bindings are loaded.
  static void _ensureInitialized() {
    if (_initialized) return;
    _initialized = true;

    if (Platform.isWindows) {
      try {
        final kernel32 = DynamicLibrary.open('kernel32.dll');
        final getCurrentProcess = kernel32
            .lookupFunction<IntPtr Function(), int Function()>(
              'GetCurrentProcess',
            );
        final setProcessWorkingSetSize = kernel32
            .lookupFunction<
              Int32 Function(IntPtr, IntPtr, IntPtr),
              int Function(int, int, int)
            >('SetProcessWorkingSetSize');
        final getProcessHeap = kernel32
            .lookupFunction<IntPtr Function(), int Function()>(
              'GetProcessHeap',
            );
        final heapCompact = kernel32
            .lookupFunction<
              IntPtr Function(IntPtr, Uint32),
              int Function(int, int)
            >('HeapCompact');

        _platformTrimmer = ({required bool aggressive}) {
          final hProcess = getCurrentProcess();
          final hHeap = getProcessHeap();
          if (hHeap != 0) {
            heapCompact(hHeap, 0);
          }
          // -1, -1 tells the Windows Memory Manager to trim the working set
          setProcessWorkingSetSize(hProcess, -1, -1);
        };
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[MemoryOptimizer] Failed to bind Windows APIs: $e');
        }
      }
    } else if (Platform.isAndroid) {
      try {
        final libc = DynamicLibrary.open('libc.so');
        int Function(int, int)? mallopt;
        try {
          mallopt = libc
              .lookupFunction<
                Int32 Function(Int32, Int32),
                int Function(int, int)
              >('mallopt');
          // Configure Scudo to immediately release freed pages and disable
          // secondary large-block caching.
          mallopt(_mDecayTime, 0);
          mallopt(_mCacheCountMax, 0);
          mallopt(_mCacheSizeMax, 0);
        } catch (_) {}

        int Function(Pointer<Void>, int, int)? madvise;
        try {
          madvise = libc
              .lookupFunction<
                Int32 Function(Pointer<Void>, IntPtr, Int32),
                int Function(Pointer<Void>, int, int)
              >('madvise');
        } catch (_) {}

        _platformTrimmer = ({required bool aggressive}) {
          if (aggressive && madvise != null) {
            _reclaimPosixMapsPages(madvise, aggressive: true);
          }
          if (mallopt != null) {
            mallopt(_mDecayTime, 0);
            mallopt(_mPurge, 0);
            mallopt(_mPurgeAll, 0);
          }
        };
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[MemoryOptimizer] Failed to bind Android APIs: $e');
        }
      }
    } else if (Platform.isLinux) {
      try {
        final libc = DynamicLibrary.process();
        final mallocTrim = libc
            .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
              'malloc_trim',
            );
        int Function(Pointer<Void>, int, int)? madvise;
        try {
          madvise = libc
              .lookupFunction<
                Int32 Function(Pointer<Void>, IntPtr, Int32),
                int Function(Pointer<Void>, int, int)
              >('madvise');
        } catch (_) {}

        _platformTrimmer = ({required bool aggressive}) {
          mallocTrim(0);
          if (aggressive && madvise != null) {
            _reclaimPosixMapsPages(madvise, aggressive: true);
          }
        };
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[MemoryOptimizer] Failed to bind Linux APIs: $e');
        }
      }
    }
  }

  /// Safely reclaims clean file-backed pages (`MADV_DONTNEED`) and optionally
  /// pages out cold/anonymous ranges (`MADV_PAGEOUT` / `MADV_COLD`) via `/proc/self/maps`.
  static void _reclaimPosixMapsPages(
    int Function(Pointer<Void>, int, int) madvise, {
    required bool aggressive,
  }) {
    try {
      final mapsFile = File('/proc/self/maps');
      if (!mapsFile.existsSync()) return;
      final lines = mapsFile.readAsLinesSync();

      for (final line in lines) {
        final spaceIdx = line.indexOf(' ');
        if (spaceIdx <= 0 || spaceIdx + 5 > line.length) continue;

        final perms = line.substring(spaceIdx + 1, spaceIdx + 5);
        // Only operate on private mappings ('p'); never touch shared ('s') device/ashmem mappings.
        if (perms.length < 4 || perms[3] != 'p') continue;

        final dashIdx = line.indexOf('-');
        if (dashIdx <= 0 || dashIdx >= spaceIdx) continue;

        // Extract optional mapping path after the 5th space-delimited column
        String path = '';
        int col = 0;
        for (int i = spaceIdx; i < line.length; i++) {
          if (line.codeUnitAt(i) == 32) {
            while (i + 1 < line.length && line.codeUnitAt(i + 1) == 32) {
              i++;
            }
            col++;
            if (col == 5) {
              path = line.substring(i + 1).trim();
              break;
            }
          }
        }

        if (path == '[stack]' ||
            path.startsWith('[stack:') ||
            path == '[vdso]' ||
            path == '[vvar]' ||
            path.startsWith('/dev/') ||
            path.startsWith('/memfd:')) {
          continue;
        }

        final isSystemOrAppFile =
            path.startsWith('/data/') ||
            path.startsWith('/system/') ||
            path.startsWith('/apex/') ||
            path.startsWith('/vendor/') ||
            path.startsWith('/product/') ||
            path.startsWith('/odm/') ||
            path.startsWith('/usr/') ||
            path.startsWith('/lib/');

        // Pure read-only non-ELF data mappings (never modified by linker64 GNU_RELRO)
        final isPureReadOnlyAsset =
            isSystemOrAppFile &&
            perms == 'r--p' &&
            (path.endsWith('.apk') ||
                path.endsWith('.dex') ||
                path.endsWith('.vdex') ||
                path.endsWith('.jar') ||
                path.endsWith('.ttf') ||
                path.endsWith('.otf') ||
                path.endsWith('.hyb') ||
                path.endsWith('.dat'));

        // W^X enforced executable code segments (never COW-modified on Android)
        final isExecCode =
            aggressive && isSystemOrAppFile && perms == 'r-xp';

        if (!aggressive && !isPureReadOnlyAsset) {
          continue;
        }

        final start = int.tryParse(line.substring(0, dashIdx), radix: 16);
        final end = int.tryParse(
          line.substring(dashIdx + 1, spaceIdx),
          radix: 16,
        );
        if (start == null || end == null || end <= start) continue;

        final length = end - start;
        final ptr = Pointer<Void>.fromAddress(start);

        // Safe non-destructive page cache drop ONLY on non-RELRO pure read-only assets or W^X r-xp code
        if (isPureReadOnlyAsset || isExecCode) {
          madvise(ptr, length, _madvDontNeed);
        }

        // Non-destructive LRU deactivation / zram swap-out when aggressive (preserves COW/RELRO & heap)
        if (aggressive) {
          final res = madvise(ptr, length, _madvPageOut);
          if (res != 0) {
            madvise(ptr, length, _madvCold);
          }
        }
      }
    } catch (_) {}
  }

  /// Trims unused heap memory and flushes unreferenced pages from the working set.
  static void trim({bool aggressive = false}) {
    try {
      _ensureInitialized();
      _platformTrimmer?.call(aggressive: aggressive);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MemoryOptimizer] Trim warning: $e');
      }
    }
  }

  static Timer? _periodicTimer;

  /// Starts a periodic background trimmer that ensures physical RAM remains
  /// at minimum levels during idle and after operations.
  static void startPeriodicTrimmer({
    Duration interval = const Duration(seconds: 10),
    void Function()? onTrim,
  }) {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(interval, (_) {
      onTrim?.call();
      trim();
    });
  }

  /// Cancels the periodic background trimmer if active.
  static void stopPeriodicTrimmer() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }
}
