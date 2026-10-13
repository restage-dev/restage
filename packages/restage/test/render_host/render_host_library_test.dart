import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no app-facing library reaches the render host', () {
    for (final library in Directory('lib').listSync().whereType<File>()) {
      if (library.path.endsWith('render_host.dart')) continue;
      expect(
        library.readAsStringSync(),
        isNot(contains('render_host')),
        reason: library.path,
      );
    }
  });
}
