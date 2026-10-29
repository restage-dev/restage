import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // The CLI's surface capture looks for this export by name.
  test('render_support exports paywallHostContext by name', () {
    expect(
      File('lib/render_support.dart').readAsStringSync(),
      matches(RegExp(r'\bexport\s[^;]*\bshow\b[^;]*\bpaywallHostContext\b')),
    );
  });
}
