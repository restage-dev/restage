import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/render_host/browser_render_message_transport.dart';

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
