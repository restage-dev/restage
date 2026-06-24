// This test deliberately exercises the deprecated `RestageProperty.defaultValue`
// shortcut, which remains supported (codegen folds it to a LiteralDefault).
// ignore_for_file: deprecated_member_use_from_same_package
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

void main() {
  test('RestageProperty captures description, required, defaults', () {
    const required = RestageProperty(description: 'The label.', required: true);
    expect(required.description, 'The label.');
    expect(required.required, isTrue);
    expect(required.defaultValue, isNull);
    expect(required.defaultBrandToken, isNull);

    const withBrandToken = RestageProperty(
      description: 'Background.',
      defaultBrandToken: 'primary',
    );
    expect(withBrandToken.required, isFalse);
    expect(withBrandToken.defaultBrandToken, 'primary');

    const withLiteral = RestageProperty(
      description: 'Padding.',
      defaultValue: [12.0, 24.0, 12.0, 24.0],
    );
    expect(withLiteral.defaultValue, isA<List<double>>());
  });
}
