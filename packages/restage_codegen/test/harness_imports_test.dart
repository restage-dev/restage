import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final _directImport = RegExp(
  r"^import 'package:build_test/build_test\.dart'",
  multiLine: true,
);

/// Tests reach `build_test` through `helpers.dart`, whose wrappers resolve
/// on the shared warm analyzer. A direct import silently opts out of that.
void main() {
  test('tests import build_test through helpers.dart', () {
    final offenders = <String>[];
    for (final entity in Directory('test').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = p.normalize(entity.path);
      if (path == p.join('test', 'helpers.dart')) continue;
      if (_directImport.hasMatch(entity.readAsStringSync())) {
        offenders.add(path);
      }
    }
    expect(offenders, isEmpty);
  });
}
