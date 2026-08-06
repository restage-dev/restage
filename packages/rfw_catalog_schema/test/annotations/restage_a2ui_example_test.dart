import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

@RestageA2uiExample(
  name: 'Default',
  asset: 'lib/a2ui_examples/product_card/default.json',
)
@RestageA2uiExample(
  name: 'Long title',
  asset: 'lib/a2ui_examples/product_card/long_title.json',
)
class _RepeatedExampleTarget {}

void main() {
  test('RestageA2uiExample is a narrow repeatable class annotation', () {
    const annotation = RestageA2uiExample(
      name: 'Default',
      asset: 'lib/a2ui_examples/product_card/default.json',
    );

    expect(annotation.name, 'Default');
    expect(
      annotation.asset,
      'lib/a2ui_examples/product_card/default.json',
    );
    expect(_RepeatedExampleTarget, isNotNull);
  });
}
