import 'package:flutter_test/flutter_test.dart';
import 'package:restage_preview_harness/restage_preview_harness.dart';

void main() {
  test('non-web browser transport fails closed', () {
    expect(
      () => createBrowserRenderMessageTransport(
        parentOrigin: 'https://shell.example',
      ),
      throwsA(isA<UnsupportedError>()),
    );
  });
}
