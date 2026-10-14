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
  static void Function()? _platformTrimmer;

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

        _platformTrimmer = () {
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
    } else if (Platform.isLinux) {
      try {
        final libc = DynamicLibrary.process();
        final mallocTrim = libc
            .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
              'malloc_trim',
            );
        _platformTrimmer = () {
          mallocTrim(0);
        };
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[MemoryOptimizer] Failed to bind Linux APIs: $e');
        }
      }
    }
  }

  /// Trims unused heap memory and flushes unreferenced pages from the working set.
  static void trim() {
    try {
      _ensureInitialized();
      _platformTrimmer?.call();
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
    Duration interval = const Duration(seconds: 5),
  }) {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(interval, (_) {
      trim();
    });
  }

  /// Cancels the periodic background trimmer if active.
  static void stopPeriodicTrimmer() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }
}
