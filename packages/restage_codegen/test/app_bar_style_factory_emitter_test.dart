import 'dart:io';

import 'package:restage_codegen/src/factory_emitter.dart';
import 'package:restage_codegen/src/native_catalog_index.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

void main() {
  for (final native in [true, false]) {
    test('AppBar styles use nullable decoders (native: $native)', () {
      final catalog = requireNativeCatalog(
        decodeCatalog(
          File('../restage_material/lib/src/widget_catalog/catalog.json')
              .readAsStringSync(),
        ),
      );
      final appBar =
          catalog.widgets.singleWhere((entry) => entry.name == 'AppBar');
      final entry = native
          ? appBar
          : WidgetEntry(
              wireId: appBar.wireId,
              name: appBar.name,
              library: appBar.library,
              category: appBar.category,
              description: appBar.description,
              flutterType: appBar.flutterType,
              childrenSlot: ChildrenSlot.none,
              properties: appBar.properties
                  .where(
                    (property) => const {
                      'systemOverlayStyle',
                      'iconTheme',
                      'actionsIconTheme',
                    }.contains(property.name),
                  )
                  .toList(),
            );
      final source = emitFactoryFunction(
        entry,
        nativeIndex: NativeCatalogIndex(catalog),
      );
      expect(source, isNotNull);
      for (final property in [
        'systemOverlayStyle',
        'iconTheme',
        'actionsIconTheme',
      ]) {
        final decoder = property == 'systemOverlayStyle'
            ? 'systemUiOverlayStyle'
            : 'iconThemeData';
        final call = 'RestageDecoders.$decoder';
        expect(
          source,
          contains("$property: $call(source, <Object>['$property']),"),
        );
      }
    });
  }
}
