import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/core/services/native_binary_locator.dart';
import 'package:tachyon/core/services/process_executor.dart';

class MockPlatformContext implements PlatformContext {
  @override
  final bool isLinux;
  @override
  final bool isWindows;
  @override
  final bool isAndroid;
  @override
  final bool isMacOS;
  @override
  final bool isIOS;
  @override
  final String resolvedExecutable;
  @override
  final Map<String, String> environment;
  @override
  final String currentDirectoryPath;
  @override
  final int numberOfProcessors;
  final String? androidNativeLibDir;
  final Set<String> existingFiles;

  MockPlatformContext({
    this.isLinux = true,
    this.isWindows = false,
    this.isAndroid = false,
    this.isMacOS = false,
    this.isIOS = false,
    this.resolvedExecutable = '/app/bin/tachyon',
    this.environment = const {},
    this.currentDirectoryPath = '/project',
    this.numberOfProcessors = 4,
    this.androidNativeLibDir,
    Set<String>? existingFiles,
  }) : existingFiles = existingFiles ?? {};

  @override
  Future<String?> getAndroidNativeLibDir() async => androidNativeLibDir;

  @override
  bool fileExists(String path) => existingFiles.contains(path);
}

class MockProcessExecutor implements ProcessExecutor {
  final Map<String, ProcessResult> responses;
  final List<(String, List<String>)> calls = [];

  MockProcessExecutor([Map<String, ProcessResult>? responses])
      : responses = responses ?? {};

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
  }) async {
    calls.add((executable, arguments));
    if (responses.containsKey(executable)) {
      return responses[executable]!;
    }
    // Default success for -version
    return ProcessResult(100, 0, 'ffprobe version 8.0 Copyright (c) FFmpeg', '');
  }
}

void main() {
  group('NativeBinaryLocator - Linux Discovery', () {
    test('resolves binary from APPDIR when AppImage is mounted', () async {
      final platform = MockPlatformContext(
        isLinux: true,
        environment: {'APPDIR': '/tmp/.mount_app'},
        existingFiles: {'/tmp/.mount_app/usr/bin/ffprobe'},
      );
      final executor = MockProcessExecutor();
      final locator = NativeBinaryLocatorImpl(platform: platform, executor: executor);

      final path = await locator.findFfprobe();
      expect(path, equals('/tmp/.mount_app/usr/bin/ffprobe'));
      expect(executor.calls.any((c) => c.$1 == '/tmp/.mount_app/usr/bin/ffprobe'), isTrue);
    });

    test('resolves binary from standard /usr/bin/ffprobe', () async {
      final platform = MockPlatformContext(
        isLinux: true,
        existingFiles: {'/usr/bin/ffprobe'},
      );
      final executor = MockProcessExecutor();
      final locator = NativeBinaryLocatorImpl(platform: platform, executor: executor);

      final path = await locator.findFfprobe();
      expect(path, equals('/usr/bin/ffprobe'));
    });

    test('resolves binary from PATH', () async {
      final platform = MockPlatformContext(
        isLinux: true,
        environment: {'PATH': '/custom/bin:/another/bin'},
        existingFiles: {'/another/bin/ffprobe'},
      );
      final executor = MockProcessExecutor();
      final locator = NativeBinaryLocatorImpl(platform: platform, executor: executor);

      final path = await locator.findFfprobe();
      expect(path, equals('/another/bin/ffprobe'));
    });

    test('falls back to dev repo linux/ffprobe', () async {
      final platform = MockPlatformContext(
        isLinux: true,
        currentDirectoryPath: '/home/user/tachyon',
        existingFiles: {'/home/user/tachyon/linux/ffprobe'},
      );
      final executor = MockProcessExecutor();
      final locator = NativeBinaryLocatorImpl(platform: platform, executor: executor);

      final path = await locator.findFfprobe();
      expect(path, equals('/home/user/tachyon/linux/ffprobe'));
    });
  });

  group('NativeBinaryLocator - Windows Discovery', () {
    test('resolves Windows executable from bundle directory', () async {
      final platform = MockPlatformContext(
        isLinux: false,
        isWindows: true,
        resolvedExecutable: r'C:\Program Files\Tachyon\tachyon.exe',
        existingFiles: {r'C:\Program Files\Tachyon\ffprobe.exe'},
      );
      final executor = MockProcessExecutor();
      final locator = NativeBinaryLocatorImpl(platform: platform, executor: executor);

      final path = await locator.findFfprobe();
      expect(path, equals(r'C:\Program Files\Tachyon\ffprobe.exe'));
    });

    test('resolves Windows executable from common chocolatey directory', () async {
      final platform = MockPlatformContext(
        isLinux: false,
        isWindows: true,
        resolvedExecutable: r'C:\Users\test\AppData\Local\tachyon.exe',
        existingFiles: {r'C:\ProgramData\chocolatey\bin\ffmpeg.exe'},
      );
      final executor = MockProcessExecutor();
      final locator = NativeBinaryLocatorImpl(platform: platform, executor: executor);

      final path = await locator.findFfmpeg();
      expect(path, equals(r'C:\ProgramData\chocolatey\bin\ffmpeg.exe'));
    });
  });

  group('NativeBinaryLocator - Android Discovery', () {
    test('resolves Android native library via MethodChannel getNativeLibDir', () async {
      final platform = MockPlatformContext(
        isLinux: false,
        isAndroid: true,
        androidNativeLibDir: '/data/app/~~package-hash==/lib/arm64',
        existingFiles: {'/data/app/~~package-hash==/lib/arm64/libffprobe.so'},
      );
      final executor = MockProcessExecutor();
      final locator = NativeBinaryLocatorImpl(platform: platform, executor: executor);

      final path = await locator.findFfprobe();
      expect(path, equals('/data/app/~~package-hash==/lib/arm64/libffprobe.so'));
    });

    test('falls back to known Android data/app paths', () async {
      final platform = MockPlatformContext(
        isLinux: false,
        isAndroid: true,
        androidNativeLibDir: null,
        existingFiles: {'/data/app/dev.chomusuke.tachyon/lib/arm64/libffmpeg.so'},
      );
      final executor = MockProcessExecutor();
      final locator = NativeBinaryLocatorImpl(platform: platform, executor: executor);

      final path = await locator.findFfmpeg();
      expect(path, equals('/data/app/dev.chomusuke.tachyon/lib/arm64/libffmpeg.so'));
    });
  });

  group('NativeBinaryLocator - macOS & iOS Discovery', () {
    test('resolves macOS executable from Homebrew path', () async {
      final platform = MockPlatformContext(
        isLinux: false,
        isMacOS: true,
        resolvedExecutable: '/Applications/Tachyon.app/Contents/MacOS/tachyon',
        existingFiles: {'/opt/homebrew/bin/ffprobe'},
      );
      final executor = MockProcessExecutor();
      final locator = NativeBinaryLocatorImpl(platform: platform, executor: executor);

      final path = await locator.findFfprobe();
      expect(path, equals('/opt/homebrew/bin/ffprobe'));
    });

    test('throws NativeBinaryNotFoundException on iOS citing sandbox restrictions', () async {
      final platform = MockPlatformContext(
        isLinux: false,
        isIOS: true,
      );
      final executor = MockProcessExecutor();
      final locator = NativeBinaryLocatorImpl(platform: platform, executor: executor);

      expect(
        () => locator.findFfprobe(),
        throwsA(isA<NativeBinaryNotFoundException>().having(
          (e) => e.message,
          'message',
          contains('iOS due to platform sandbox restrictions'),
        )),
      );
    });
  });

  group('NativeBinaryLocator - Overrides, Caching & Errors', () {
    test('TACHYON_FFPROBE_PATH environment variable overrides all other paths', () async {
      final platform = MockPlatformContext(
        isLinux: true,
        environment: {'TACHYON_FFPROBE_PATH': '/opt/custom/ffprobe'},
        existingFiles: {
          '/opt/custom/ffprobe',
          '/usr/bin/ffprobe',
        },
      );
      final executor = MockProcessExecutor();
      final locator = NativeBinaryLocatorImpl(platform: platform, executor: executor);

      final path = await locator.findFfprobe();
      expect(path, equals('/opt/custom/ffprobe'));
    });

    test('caches discovered path in memory and reuses on subsequent calls', () async {
      final platform = MockPlatformContext(
        isLinux: true,
        existingFiles: {'/usr/bin/ffprobe'},
      );
      final executor = MockProcessExecutor();
      final locator = NativeBinaryLocatorImpl(platform: platform, executor: executor);

      final p1 = await locator.findFfprobe();
      final initialCallCount = executor.calls.length;

      final p2 = await locator.findFfprobe();
      expect(p1, equals(p2));
      expect(executor.calls.length, equals(initialCallCount));

      // With forceRefresh, re-checks
      final p3 = await locator.findFfprobe(forceRefresh: true);
      expect(p3, equals(p1));
      expect(executor.calls.length, greaterThan(initialCallCount));
    });

    test('isFfprobeAvailable returns false without throwing on missing binary', () async {
      final platform = MockPlatformContext(
        isLinux: true,
        existingFiles: {}, // none exist
      );
      final executor = MockProcessExecutor();
      final locator = NativeBinaryLocatorImpl(platform: platform, executor: executor);

      expect(await locator.isFfprobeAvailable(), isFalse);
      expect(await locator.isFfmpegAvailable(), isFalse);
    });

    test('rejects binary that fails -version verification', () async {
      final platform = MockPlatformContext(
        isLinux: true,
        existingFiles: {
          '/bad/ffprobe',
          '/good/ffprobe',
        },
        environment: {'PATH': '/bad:/good'},
      );
      final executor = MockProcessExecutor({
        '/bad/ffprobe': ProcessResult(1, 1, '', 'Command failed'),
        '/good/ffprobe': ProcessResult(2, 0, 'ffprobe version 8.1', ''),
      });
      final locator = NativeBinaryLocatorImpl(platform: platform, executor: executor);

      final path = await locator.findFfprobe();
      expect(path, equals('/good/ffprobe'));
    });
  });
}
