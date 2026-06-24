import 'package:restage_codegen/src/a2ui/a2ui_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('A2UI protocol pins', () {
    test('protocol version is pinned to 0.9.1', () {
      expect(kA2uiProtocolVersion, '0.9.1');
    });

    test('schema dialect is JSON-Schema draft 2020-12', () {
      expect(
        kA2uiSchemaDialect,
        'https://json-schema.org/draft/2020-12/schema',
      );
    });
  });
}
