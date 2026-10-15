import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the SDK does not depend on the render host', () {
    expect(
      File('pubspec.yaml').readAsStringSync(),
      isNot(contains('restage_render_host')),
    );
    for (final library in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))) {
      expect(
        library.readAsStringSync(),
        isNot(contains('restage_render_host')),
        reason: library.path,
      );
    }
  });
}
