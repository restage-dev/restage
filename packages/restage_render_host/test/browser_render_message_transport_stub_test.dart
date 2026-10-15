import 'package:flutter_test/flutter_test.dart';
import 'package:restage_render_host/src/browser_render_message_transport.dart';

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
