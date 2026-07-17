import 'dart:convert';

import 'package:restage_cli/src/api/catalog_api.dart';
import 'package:test/test.dart';

void main() {
  group('decodeCatalogTypedException', () {
    test('decodes CatalogInvalidException', () {
      final body = jsonEncode({
        'className': 'CatalogInvalidException',
        'data': {
          '__className__': 'CatalogInvalidException',
          'message': 'missing widgets',
        },
      });

      final decoded = decodeCatalogTypedException(body);

      expect(decoded, isA<CatalogInvalid>());
      expect((decoded! as CatalogInvalid).message, 'missing widgets');
    });

    test('decodes CatalogTooLargeException', () {
      final body = jsonEncode({
        'className': 'CatalogTooLargeException',
        'data': {
          '__className__': 'CatalogTooLargeException',
          'maxBytes': 524288,
          'actualBytes': 524289,
        },
      });

      final decoded = decodeCatalogTypedException(body);

      expect(decoded, isA<CatalogTooLarge>());
      final tooLarge = decoded! as CatalogTooLarge;
      expect(tooLarge.maxBytes, 524288);
      expect(tooLarge.actualBytes, 524289);
    });

    test('returns null for unknown or malformed bodies', () {
      expect(decodeCatalogTypedException(''), isNull);
      expect(decodeCatalogTypedException('not json'), isNull);
      expect(decodeCatalogTypedException('{"foo":"bar"}'), isNull);
    });
  });

  group('renderCatalogException', () {
    test('renders invalid catalog with the server message', () {
      expect(
        renderCatalogException(const CatalogInvalid(message: 'bad JSON')),
        contains('bad JSON'),
      );
    });

    test('renders oversized catalog with byte counts', () {
      final message = renderCatalogException(
        const CatalogTooLarge(maxBytes: 524288, actualBytes: 524289),
      );

      expect(message, contains('too large'));
      expect(message, contains('524288'));
      expect(message, contains('524289'));
    });
  });
}
