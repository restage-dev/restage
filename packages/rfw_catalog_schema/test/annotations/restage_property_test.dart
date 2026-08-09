import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

void main() {
  test('RestageProperty captures description, required, and defaults', () {
    const required = RestageProperty(description: 'The label.', required: true);
    expect(required.description, 'The label.');
    expect(required.required, isTrue);
    expect(required.defaultBrandToken, isNull);
    expect(required.defaultSource, isNull);

    const withBrandToken = RestageProperty(
      description: 'Background.',
      defaultBrandToken: 'primary',
    );
    expect(withBrandToken.required, isFalse);
    expect(withBrandToken.defaultBrandToken, 'primary');

    const withLiteral = RestageProperty(
      description: 'Padding.',
      defaultSource: LiteralDefault([12.0, 24.0, 12.0, 24.0]),
    );
    expect(withLiteral.defaultSource, isA<LiteralDefault>());
  });
}
