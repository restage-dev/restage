import 'dart:convert';

import 'package:restage_codegen/src/a2ui/a2ui_catalog_adapter.dart';
import 'package:restage_codegen/src/widget_visitor.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../helpers.dart';

Catalog _visitorCatalog(WidgetVisitorResult result) {
  final libraries = <WidgetLibrary>{
    for (final widget in result.widgets) widget.library,
  };
  return Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: '1970-01-01T00:00:00Z',
    libraries: {
      for (final library in libraries)
        library: const LibraryInfo(
          version: '0.0.0',
          capabilityVersion: 1,
        ),
    },
    widgets: result.widgets,
  );
}

List<int> _encodedA2uiCatalog(Catalog catalog) {
  final registration = emitA2uiCatalog(catalog);
  return utf8.encode(
    const JsonEncoder.withIndent('  ').convert(registration.toJson()),
  );
}

String _recordPackageSource({required bool includeRecord}) {
  final constructor = includeRecord
      ? 'const RecordCard({required this.heading});'
      : 'const RecordCard();';
  final property = includeRecord
      ? '''
    @RestageProperty(description: 'The heading.')
    final ({String title, int step}) heading;
  '''
      : '';
  return '''
    import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

    @RestageLibrary(
      library: WidgetLibrary.custom('acme.widgets'),
      capabilityVersion: 1,
    )
    const restageLibrary = 0;

    @RestageWidget(
      name: 'RecordCard',
      library: WidgetLibrary.custom('acme.widgets'),
      category: WidgetCategory.decoration,
      description: 'A card.',
    )
    class RecordCard {
      $constructor
      $property
    }
  ''';
}

void main() {
  test(
    'an RFW-admitted record property leaves A2UI catalog bytes unchanged',
    () async {
      final recordSource = _recordPackageSource(includeRecord: true);
      final removedSource = _recordPackageSource(includeRecord: false);

      final rfwRecord = await runWidgetVisitorOn(
        {'lib/record_card.dart': recordSource},
      );
      expect(
        rfwRecord.widgets.single.properties.map((property) => property.name),
        ['heading'],
        reason: 'the control package must carry an RFW-admitted record',
      );

      final a2uiRecord = await runWidgetVisitorOn(
        {'lib/record_card.dart': recordSource},
        target: WidgetVisitorTarget.a2ui,
      );
      final a2uiRemoved = await runWidgetVisitorOn(
        {'lib/record_card.dart': removedSource},
        target: WidgetVisitorTarget.a2ui,
      );

      // The current A2UI catalog property path rejects records before
      // projection, while a String control would intentionally add `heading`
      // and change the catalog. Removing the record is therefore the
      // byte-neutral comparison for this harness.
      expect(a2uiRecord.widgets.single.properties, isEmpty);
      expect(
        _encodedA2uiCatalog(_visitorCatalog(a2uiRecord)),
        orderedEquals(_encodedA2uiCatalog(_visitorCatalog(a2uiRemoved))),
        reason: 'omitting the record must be the only A2UI projection effect',
      );
    },
  );
}
