import 'package:flutter_test/flutter_test.dart';
import 'package:restage_cupertino/registry.dart';
import 'package:restage_shared/restage_shared.dart';

void main() {
  group('restage_cupertino registry', () {
    test('every entry belongs to the cupertino library', () {
      expect(
        kRegistry.libraries.keys.toList(),
        equals(<WidgetLibrary>[WidgetLibrary.cupertino]),
        reason: 'a per-package registry declares exactly its own library',
      );
      expect(
        kRegistry.widgets.every((w) => w.library == WidgetLibrary.cupertino),
        isTrue,
      );
    });

    test('canonical encode succeeds with allocated wire IDs', () {
      final encoded = encodeCatalog(kRegistry);
      expect(encoded, isNot(contains('w0000')));
      expect(encoded, isNot(contains('p0000')));
      expect(kRegistry.widgets.any((w) => w.wireId.isUnallocated), isFalse);
      expect(
        kRegistry.widgets.expand((w) => w.properties).any(
              (p) => p.wireId.isUnallocated,
            ),
        isFalse,
      );
      expect(encoded, isNot(contains('a0000')));
      expect(encoded, isNot(contains('legacyStructuredType')));
      expect(encoded, isNot(contains('legacyFlatProperties')));
      expect(encoded, isNot(contains('factoryConvention')));
      expect(() => requireNativeCatalog(kRegistry), returnsNormally);
    });

    test('flutterType strings reference real Flutter widget URIs', () {
      for (final w in kRegistry.widgets) {
        expect(
          w.flutterType,
          startsWith('package:flutter/'),
          reason: '${w.name} must point at a real Flutter widget',
        );
      }
    });

    test('every event-firing widget has a matching event property', () {
      // The bijection key on the property side is `firesAs ?? name`,
      // matching the factory emitter's eligibility check.
      for (final w in kRegistry.widgets) {
        for (final event in w.fires) {
          final eventName = event.name; // e.g. onPressed, onChanged
          expect(
            w.properties.any(
              (p) =>
                  (p.firesAs ?? p.name) == eventName &&
                  p.type == PropertyType.event,
            ),
            isTrue,
            reason: '${w.name} fires $eventName but lacks a matching '
                'PropertyType.event property (checked against firesAs ?? name)',
          );
        }
      }
    });
  });
}
