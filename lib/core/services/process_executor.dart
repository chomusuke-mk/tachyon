import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Abstract interface for process execution, enabling mock-based unit testing.
abstract class ProcessExecutor {
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Encoding? stdoutEncoding = systemEncoding,
    Encoding? stderrEncoding = systemEncoding,
  });
}

/// Production implementation of [ProcessExecutor] delegating to [Process.run].
class NativeProcessExecutor implements ProcessExecutor {
  const NativeProcessExecutor();

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Encoding? stdoutEncoding = systemEncoding,
    Encoding? stderrEncoding = systemEncoding,
  }) {
    return Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      runInShell: runInShell,
      stdoutEncoding: stdoutEncoding,
      stderrEncoding: stderrEncoding,
    );
  }
}

/// Abstract interface for querying platform properties and capabilities.
abstract class PlatformContext {
  bool get isLinux;
  bool get isWindows;
  bool get isAndroid;
  bool get isMacOS;
  bool get isIOS;
  String get resolvedExecutable;
  Map<String, String> get environment;
  String get currentDirectoryPath;
  int get numberOfProcessors;
  Future<String?> getAndroidNativeLibDir();
  bool fileExists(String path);
}

/// Production implementation of [PlatformContext] querying [Platform] and [MethodChannel].
class NativePlatformContext implements PlatformContext {
  static const MethodChannel _channel = MethodChannel('tachyon_channel');

  const NativePlatformContext();

  @override
  bool get isLinux => !kIsWeb && Platform.isLinux;

  @override
  bool get isWindows => !kIsWeb && Platform.isWindows;

  @override
  bool get isAndroid => !kIsWeb && Platform.isAndroid;

  @override
  bool get isMacOS => !kIsWeb && Platform.isMacOS;

  @override
  bool get isIOS => !kIsWeb && Platform.isIOS;

  @override
  String get resolvedExecutable => Platform.resolvedExecutable;

  @override
  Map<String, String> get environment => Platform.environment;

  @override
  String get currentDirectoryPath => Directory.current.path;

  @override
  int get numberOfProcessors => Platform.numberOfProcessors;

  @override
  Future<String?> getAndroidNativeLibDir() async {
    if (!isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('getNativeLibDir');
    } catch (e) {
      debugPrint('Warning: Failed to obtain getNativeLibDir via tachyon_channel: $e');
      return null;
    }
  }

  @override
  bool fileExists(String path) {
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }
}

/// Alias for compatibility.
typedef DefaultPlatformContext = NativePlatformContext;
