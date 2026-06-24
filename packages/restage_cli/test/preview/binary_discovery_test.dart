import 'dart:io';

import 'package:restage_cli/src/preview/binary_discovery.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('preview_disc_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('locateRestagePreviewBinary', () {
    test(
      'honours the RESTAGE_PREVIEW_BIN override when the path exists',
      () async {
        final binary = File(p.join(tempDir.path, 'my-preview'));
        await binary.writeAsString('');

        final resolved = locateRestagePreviewBinary(
          environment: {'RESTAGE_PREVIEW_BIN': binary.path},
          isWindows: false,
          existsCheck: (path) => path == binary.path,
          pathOverride: const [],
        );

        expect(resolved, binary.path);
      },
    );

    test('ignores the override when the named path is missing', () async {
      final resolved = locateRestagePreviewBinary(
        environment: {'RESTAGE_PREVIEW_BIN': '/no/such/binary'},
        isWindows: false,
        existsCheck: (_) => false,
        pathOverride: const [],
      );
      expect(resolved, isNull);
    });

    test('falls back to ~/.restage/bin/restage-preview on POSIX', () async {
      final home = p.join(tempDir.path, 'home');
      final installed = File(
        p.join(home, '.restage', 'bin', 'restage-preview'),
      );
      await installed.parent.create(recursive: true);
      await installed.writeAsString('');

      final resolved = locateRestagePreviewBinary(
        environment: {'HOME': home},
        isWindows: false,
        existsCheck: (path) => File(path).existsSync(),
        pathOverride: const [],
      );

      expect(resolved, installed.path);
    });

    test('falls back to %USERPROFILE%/.restage/bin/restage-preview.exe '
        'on Windows', () async {
      final home = p.join(tempDir.path, 'Users', 'jane');
      final installed = File(
        p.join(home, '.restage', 'bin', 'restage-preview.exe'),
      );
      await installed.parent.create(recursive: true);
      await installed.writeAsString('');

      final resolved = locateRestagePreviewBinary(
        environment: {'USERPROFILE': home},
        isWindows: true,
        existsCheck: (path) => File(path).existsSync(),
        pathOverride: const [],
      );

      expect(resolved, installed.path);
    });

    test('walks the PATH override and returns the first match', () async {
      final binDir = Directory(p.join(tempDir.path, 'bin'));
      await binDir.create();
      final binary = File(p.join(binDir.path, 'restage-preview'));
      await binary.writeAsString('');

      final resolved = locateRestagePreviewBinary(
        environment: const {'HOME': '/no-such-home'},
        isWindows: false,
        existsCheck: (path) => File(path).existsSync(),
        pathOverride: [binDir.path, '/no-such/extra'],
      );

      expect(resolved, binary.path);
    });

    test('returns null when neither the env var, ~/.restage, nor PATH '
        'yield a match', () async {
      final resolved = locateRestagePreviewBinary(
        environment: const {'HOME': '/no-such-home'},
        isWindows: false,
        existsCheck: (_) => false,
        pathOverride: const ['/no-such-bin'],
      );

      expect(resolved, isNull);
    });
  });
}
