import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tachyon/core/lifecycle/app_lifecycle_mode.dart';

/// Cross-platform low-level native memory optimizer.
///
/// Dispatches OS kernel and libc/CRT commands to flush unreferenced heap
/// arenas and working-set pages back to the operating system.
class MemoryOptimizer {
  static bool _initialized = false;
  static void Function(MemoryTrimLevel level)? _platformTrimmer;
  static Timer? _periodicTimer;

  // Android Bionic Scudo / Jemalloc mallopt constants (from <malloc.h>).
  static const int _mDecayTime = -100;
  static const int _mPurge = -101;
  static const int _mPurgeAll = -104;
  static const int _mCacheCountMax = -200;
  static const int _mCacheSizeMax = -201;

  // Linux / Android madvise constants (from <sys/mman.h>).
  static const int _madvDontNeed = 4;
  static const int _madvCold = 20;
  static const int _madvPageOut = 21;

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

        int Function(int)? emptyWorkingSet;
        try {
          emptyWorkingSet = kernel32
              .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
                'K32EmptyWorkingSet',
              );
        } catch (_) {}

        _platformTrimmer = (MemoryTrimLevel level) {
          final hProcess = getCurrentProcess();
          final hHeap = getProcessHeap();
          if (hHeap != 0) {
            heapCompact(hHeap, 0);
          }
          setProcessWorkingSetSize(hProcess, -1, -1);
          if (level == MemoryTrimLevel.aggressive && emptyWorkingSet != null) {
            emptyWorkingSet(hProcess);
          }
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

        _platformTrimmer = (MemoryTrimLevel level) {
          if (level == MemoryTrimLevel.aggressive && madvise != null) {
            _reclaimPosixMapsPages(madvise, aggressive: true);
          }
          if (mallopt != null) {
            mallopt(_mDecayTime, 0);
            mallopt(_mPurge, 0);
            if (level == MemoryTrimLevel.aggressive) {
              mallopt(_mPurgeAll, 0);
            }
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

        _platformTrimmer = (MemoryTrimLevel level) {
          mallocTrim(0);
          if (level == MemoryTrimLevel.aggressive && madvise != null) {
            _reclaimPosixMapsPages(madvise, aggressive: true);
          }
        };
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[MemoryOptimizer] Failed to bind Linux APIs: $e');
        }
      }
    } else if (Platform.isMacOS) {
      try {
        final libSystem = DynamicLibrary.process();
        final pressureRelief = libSystem
            .lookupFunction<
              UintPtr Function(Pointer<Void>, UintPtr),
              int Function(Pointer<Void>, int)
            >('malloc_zone_pressure_relief');

        _platformTrimmer = (MemoryTrimLevel level) {
          pressureRelief(nullptr, 0);
        };
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[MemoryOptimizer] Failed to bind macOS APIs: $e');
        }
      }
    }
  }

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
        if (perms.length < 4 || perms[3] != 'p') continue;

        final dashIdx = line.indexOf('-');
        if (dashIdx <= 0 || dashIdx >= spaceIdx) continue;

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

        final isExecCode = aggressive && isSystemOrAppFile && perms == 'r-xp';

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

        if (isPureReadOnlyAsset || isExecCode) {
          madvise(ptr, length, _madvDontNeed);
        }

        if (aggressive) {
          final res = madvise(ptr, length, _madvPageOut);
          if (res != 0) {
            madvise(ptr, length, _madvCold);
          }
        }
      }
    } catch (_) {}
  }

  /// Trims unused heap memory and flushes unreferenced pages according to [level].
  static void trim({MemoryTrimLevel level = MemoryTrimLevel.moderate}) {
    try {
      _ensureInitialized();
      _platformTrimmer?.call(level);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MemoryOptimizer] Trim warning: $e');
      }
    }
  }

  /// Starts a periodic background trimmer with [interval] to keep idle RSS low.
  ///
  /// Invokes [onTrim] before each trim pass when provided.
  static void startPeriodicTrimmer({
    Duration interval = const Duration(seconds: 10),
    void Function()? onTrim,
  }) {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(interval, (_) {
      onTrim?.call();
      trim(level: MemoryTrimLevel.light);
    });
  }

  /// Stops the periodic background trimmer if currently active.
  static void stopPeriodicTrimmer() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }
}
