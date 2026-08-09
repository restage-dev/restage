import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

void main() {
  test('RestageWidget annotation captures its metadata', () {
    const annotation = RestageWidget(
      name: 'ElevatedButton',
      library: WidgetLibrary.material,
      category: WidgetCategory.action,
      description: 'A call-to-action button.',
      childrenSlot: ChildrenSlot.single,
    );
    expect(annotation.name, 'ElevatedButton');
    expect(annotation.library, WidgetLibrary.material);
    expect(annotation.category, WidgetCategory.action);
    expect(annotation.description, 'A call-to-action button.');
    expect(annotation.childrenSlot, ChildrenSlot.single);
    expect(annotation.minSchemaVersion, 1);
  });

  test('RestageWidget defaults', () {
    const annotation = RestageWidget(
      name: 'Text',
      library: WidgetLibrary.core,
      category: WidgetCategory.decoration,
      description: 'Static text.',
    );
    expect(annotation.childrenSlot, ChildrenSlot.none);
  });
}
