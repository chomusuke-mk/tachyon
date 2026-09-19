import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/core/services/process_executor.dart';

class MockProcessExecutor implements ProcessExecutor {
  final Future<ProcessResult> Function(
    String executable,
    List<String> arguments,
    Map<String, String>? environment,
  )? onRun;

  final List<(String, List<String>)> executedCommands = [];

  MockProcessExecutor({this.onRun});

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
    executedCommands.add((executable, arguments));
    if (onRun != null) {
      return onRun!(executable, arguments, environment);
    }
    return ProcessResult(12345, 0, 'mock stdout', '');
  }
}

class FakePlatformContext implements PlatformContext {
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
  final bool Function(String path)? onFileExists;

  const FakePlatformContext({
    this.isLinux = true,
    this.isWindows = false,
    this.isAndroid = false,
    this.isMacOS = false,
    this.isIOS = false,
    this.resolvedExecutable = '/usr/bin/tachyon',
    this.environment = const {},
    this.currentDirectoryPath = '/project',
    this.numberOfProcessors = 4,
    this.androidNativeLibDir,
    this.onFileExists,
  });

  @override
  Future<String?> getAndroidNativeLibDir() async => androidNativeLibDir;

  @override
  bool fileExists(String path) {
    if (onFileExists != null) return onFileExists!(path);
    return false;
  }
}

void main() {
  group('ProcessExecutor & PlatformContext Abstractions', () {
    test('NativeProcessExecutor runs real system process', () async {
      const executor = NativeProcessExecutor();
      final result = await executor.run('echo', const ['tachyon_process_test']);

      expect(result.exitCode, equals(0));
      expect(result.stdout.toString().trim(), equals('tachyon_process_test'));
    });

    test('MockProcessExecutor intercepts command and records parameters', () async {
      final executor = MockProcessExecutor(
        onRun: (exe, args, env) async {
          return ProcessResult(1, 0, 'interception_success', '');
        },
      );

      final result = await executor.run('/usr/bin/custom_tool', const ['--flag', 'value']);

      expect(result.exitCode, equals(0));
      expect(result.stdout, equals('interception_success'));
      expect(executor.executedCommands.length, equals(1));
      expect(executor.executedCommands.first.$1, equals('/usr/bin/custom_tool'));
      expect(executor.executedCommands.first.$2, equals(['--flag', 'value']));
    });

    test('NativePlatformContext exposes host environment properties', () {
      const context = NativePlatformContext();

      expect(context.numberOfProcessors, greaterThan(0));
      expect(context.resolvedExecutable, isNotEmpty);
      expect(context.currentDirectoryPath, isNotEmpty);
      expect(context.environment, isA<Map<String, String>>());
      expect(context.fileExists(context.resolvedExecutable), isTrue);
      expect(context.fileExists('/non_existent_file_path_xyz_123'), isFalse);
    });

    test('FakePlatformContext can emulate any arbitrary OS environment', () async {
      const fake = FakePlatformContext(
        isLinux: false,
        isAndroid: true,
        resolvedExecutable: '/system/bin/app_process',
        androidNativeLibDir: '/data/app/lib',
        numberOfProcessors: 8,
      );

      expect(fake.isAndroid, isTrue);
      expect(fake.isLinux, isFalse);
      expect(fake.numberOfProcessors, equals(8));
      expect(await fake.getAndroidNativeLibDir(), equals('/data/app/lib'));
    });
  });
}
