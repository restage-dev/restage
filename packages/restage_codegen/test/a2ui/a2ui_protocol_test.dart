import 'package:a2ui_core/a2ui_core.dart' as core;
import 'package:restage_codegen/src/a2ui/a2ui_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('A2UI protocol pins', () {
    test('protocol version is pinned to 1.0', () {
      expect(kA2uiProtocolVersion, '1.0');
    });

    test(
      'property names preserve safe names and reserve the encoded namespace',
      () {
        const dollar = 'props_encoded_002400760061006c00750065';
        expect(a2uiPropertyName(r'$value'), dollar);
        expect(a2uiPropertyName('value'), 'props_value');
        expect(a2uiPropertyName('id'), 'props_id');
        expect(a2uiPropertyName('café'), 'props_café');
        expect(
          a2uiPropertyName('encoded_002400760061006c00750065'),
          isNot(dollar),
        );
        final outputs = [
          for (final name in [
            r'$value',
            'value',
            'id',
            'café',
            'encoded_002400760061006c00750065',
            'encoded_',
            r'value$',
          ])
            a2uiPropertyName(name),
        ];
        expect(outputs.toSet(), hasLength(outputs.length));
        expect(outputs.every(core.isValidUax31Identifier), isTrue);
      },
    );

    test(
      'encoding uses exactly four lowercase digits per UTF-16 code unit',
      () {
        expect(
          a2uiPropertyName('encoded_𐐀'),
          'props_encoded_0065006e0063006f006400650064005fd801dc00',
        );
        expect(a2uiPropertyName(r'$'), 'props_encoded_0024');
      },
    );

    test('schema dialect is JSON-Schema draft 2020-12', () {
      expect(
        kA2uiSchemaDialect,
        'https://json-schema.org/draft/2020-12/schema',
      );
    });
  });
}
