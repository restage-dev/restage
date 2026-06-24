import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

const _at = '2026-05-17T00:00:00Z';
const _by = 'rfw_catalog_compiler@0.1.0';

void main() {
  group('catalogDeprecationFor', () {
    final widgetId = WireId('w0001');

    final allocEvent = AllocWireIdEvent(
      type: WireIdKind.widget,
      id: widgetId,
      name: 'ExampleWidget',
      source: 'package:example/example.dart#ExampleWidget',
      at: _at,
      by: _by,
    );

    final deprecateEvent = DeprecateWireIdEvent(
      type: WireIdKind.widget,
      id: widgetId,
      reason: 'retired',
      at: _at,
      by: _by,
    );

    test('returns CatalogDeprecationInfo when a deprecate event targets the id',
        () {
      final events = <WireIdEvent>[allocEvent, deprecateEvent];

      final result = catalogDeprecationFor(widgetId, events);

      expect(
        result,
        equals(
          const CatalogDeprecationInfo(
            reason: 'retired',
            at: _at,
          ),
        ),
      );
    });

    test('returns null when no deprecate event targets the id', () {
      final otherId = WireId('w0002');
      final otherAlloc = AllocWireIdEvent(
        type: WireIdKind.widget,
        id: otherId,
        name: 'OtherWidget',
        source: 'package:example/example.dart#OtherWidget',
        at: _at,
        by: _by,
      );
      // Deprecate a different id — should not match widgetId.
      final otherDeprecate = DeprecateWireIdEvent(
        type: WireIdKind.widget,
        id: otherId,
        reason: 'retired',
        at: _at,
        by: _by,
      );

      final events = <WireIdEvent>[allocEvent, otherAlloc, otherDeprecate];

      expect(catalogDeprecationFor(widgetId, events), isNull);
    });

    test('returns null for an empty event list', () {
      expect(catalogDeprecationFor(widgetId, []), isNull);
    });

    test('last deprecate event wins when multiple target the same id', () {
      const firstAt = '2026-05-10T00:00:00Z';
      const lastAt = '2026-05-17T00:00:00Z';

      final firstDeprecate = DeprecateWireIdEvent(
        type: WireIdKind.widget,
        id: widgetId,
        reason: 'first-reason',
        at: firstAt,
        by: _by,
      );
      final secondDeprecate = DeprecateWireIdEvent(
        type: WireIdKind.widget,
        id: widgetId,
        reason: 'retired',
        at: lastAt,
        by: _by,
      );

      final events = <WireIdEvent>[allocEvent, firstDeprecate, secondDeprecate];

      expect(
        catalogDeprecationFor(widgetId, events),
        equals(
          const CatalogDeprecationInfo(
            reason: 'retired',
            at: lastAt,
          ),
        ),
      );
    });
  });
}
