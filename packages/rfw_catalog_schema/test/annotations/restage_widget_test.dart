import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

void main() {
  test('RestageWidget annotation captures its metadata', () {
    const annotation = RestageWidget(
      name: 'ElevatedButton',
      library: WidgetLibrary.material,
      category: WidgetCategory.action,
      description: 'A call-to-action button.',
    );
    expect(annotation.name, 'ElevatedButton');
    expect(annotation.library, WidgetLibrary.material);
    expect(annotation.category, WidgetCategory.action);
    expect(annotation.description, 'A call-to-action button.');
    expect(annotation.minSchemaVersion, 1);
  });

  test('RestageWidget defaults', () {
    const annotation = RestageWidget(description: 'Static text.');
    expect(annotation.name, isNull);
    expect(annotation.library, isNull);
    expect(annotation.category, isNull);
  });
}
