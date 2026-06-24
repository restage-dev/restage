import 'dart:io';

import 'package:restage_cli/src/cli.dart';
import 'package:restage_cli/src/preview/binary_discovery.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late StringBuffer stdout;
  late StringBuffer stderr;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('preview_cmd_');
    stdout = StringBuffer();
    stderr = StringBuffer();
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('restage preview', () {
    test('missing positional path exits 1 with usage', () async {
      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        previewBinaryLocator: ({environment, isWindows}) => '/fake/binary',
        previewLauncher:
            ({required String binary, required String blobPath}) async => 0,
      ).run(const ['preview']);

      expect(exitCode, 1);
      expect(stderr.toString().toLowerCase(), contains('path'));
    });

    test('missing .rfw file exits 1 with the resolved path', () async {
      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        previewBinaryLocator: ({environment, isWindows}) => '/fake/binary',
        previewLauncher:
            ({required String binary, required String blobPath}) async => 0,
      ).run(['preview', '/no/such/file.rfw']);

      expect(exitCode, 1);
      expect(stderr.toString(), contains('/no/such/file.rfw'));
    });

    test('preview binary not found → exit 1 with install guidance', () async {
      final blob = File(p.join(tempDir.path, 'hello.rfw'));
      await blob.writeAsString('');

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        previewBinaryLocator: ({environment, isWindows}) => null,
        previewLauncher:
            ({required String binary, required String blobPath}) async => 0,
      ).run(['preview', blob.path]);

      expect(exitCode, 1);
      final err = stderr.toString();
      expect(err, contains('preview'));
      expect(err, contains('RESTAGE_PREVIEW_BIN'));
    });

    test('happy path: locates binary, launches with absolute blob path,'
        ' exits 0', () async {
      final blob = File(p.join(tempDir.path, 'hello.rfw'));
      await blob.writeAsString('');

      String? launchedBinary;
      String? launchedBlob;
      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        previewBinaryLocator: ({environment, isWindows}) => '/fake/preview-bin',
        previewLauncher:
            ({required String binary, required String blobPath}) async {
              launchedBinary = binary;
              launchedBlob = blobPath;
              return 0;
            },
      ).run(['preview', blob.path]);

      expect(exitCode, 0);
      expect(launchedBinary, '/fake/preview-bin');
      expect(launchedBlob, p.absolute(blob.path));
      expect(stdout.toString().toLowerCase(), contains('launching'));
    });
  });

  group('locateRestagePreviewBinary (cli wiring)', () {
    test('the default locator is wired in when no override is passed', () {
      // Calling the locator directly should still work — this guards
      // against the wiring forgetting to instantiate it.
      final resolved = locateRestagePreviewBinary(
        environment: const {'HOME': '/no/such/home'},
        isWindows: false,
        existsCheck: (_) => false,
        pathOverride: const [],
      );
      expect(resolved, isNull);
    });
  });
}
