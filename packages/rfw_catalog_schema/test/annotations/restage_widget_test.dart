import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

void main() {
  test('RestageWidget annotation captures all spec fields', () {
    const annotation = RestageWidget(
      name: 'ElevatedButton',
      library: WidgetLibrary.material,
      category: WidgetCategory.action,
      description: 'A call-to-action button.',
      fires: [WidgetEventName.onPressed],
      childrenSlot: ChildrenSlot.single,
    );
    expect(annotation.name, 'ElevatedButton');
    expect(annotation.library, WidgetLibrary.material);
    expect(annotation.category, WidgetCategory.action);
    expect(annotation.description, 'A call-to-action button.');
    expect(annotation.fires, [WidgetEventName.onPressed]);
    expect(annotation.childrenSlot, ChildrenSlot.single);
    // ignore: deprecated_member_use_from_same_package
    expect(annotation.deprecatedSince, isNull);
    expect(annotation.minSchemaVersion, 1);
  });

  test('RestageWidget defaults', () {
    const annotation = RestageWidget(
      name: 'Text',
      library: WidgetLibrary.core,
      category: WidgetCategory.decoration,
      description: 'Static text.',
    );
    expect(annotation.fires, isEmpty);
    expect(annotation.childrenSlot, ChildrenSlot.none);
  });

  test('RestageWidget carries an optional usage note (default null)', () {
    const withUsage = RestageWidget(
      name: 'Callout',
      library: WidgetLibrary.custom('acme.widgets'),
      category: WidgetCategory.decoration,
      description: 'A message callout.',
      usage: 'Use for a short inline notice around optional content.',
    );
    const withoutUsage = RestageWidget(
      name: 'Callout',
      library: WidgetLibrary.custom('acme.widgets'),
      category: WidgetCategory.decoration,
      description: 'A message callout.',
    );
    expect(
      withUsage.usage,
      'Use for a short inline notice around optional content.',
    );
    expect(withoutUsage.usage, isNull);
  });
}
