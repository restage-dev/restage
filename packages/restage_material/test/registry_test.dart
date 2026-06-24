import 'package:flutter_test/flutter_test.dart';
import 'package:restage_material/registry.dart';
import 'package:restage_shared/restage_shared.dart';

void main() {
  group('restage_material registry', () {
    test('every entry belongs to the material library', () {
      expect(
        kRegistry.libraries.keys.toList(),
        equals(<WidgetLibrary>[WidgetLibrary.material]),
        reason: 'a per-package registry declares exactly its own library',
      );
      expect(
        kRegistry.widgets.every((w) => w.library == WidgetLibrary.material),
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

    test('flutterType strings reference a recognised package URI', () {
      // Most curated entries point at real Flutter widget classes
      // (`package:flutter/...`); a small set of curated paywall
      // primitives are authored inside `restage_material` itself and
      // resolve to `package:restage_material/...`. Both are valid.
      for (final w in kRegistry.widgets) {
        expect(
          w.flutterType,
          anyOf(
            startsWith('package:flutter/'),
            startsWith('package:restage_material/'),
          ),
          reason: '${w.name} must point at a Flutter or restage_material '
              'widget URI',
        );
      }
    });

    test('button widgets decompose ButtonStyle via styleFrom recipe', () {
      final buttonStyle = kRegistry.structuredTypes.singleWhere(
        (entry) => entry.name == 'ButtonStyle',
      );
      final styleFrom = buttonStyle.variants.singleWhere(
        (variant) =>
            variant is StaticMethodVariant &&
            variant.staticAccessor == 'styleFrom',
      );
      const buttonNames = [
        'ElevatedButton',
        'FilledButton',
        'FilledButtonTonal',
        'OutlinedButton',
        'OutlinedButtonIcon',
        'TextButton',
        'TextButtonIcon',
      ];
      for (final name in buttonNames) {
        final w = kRegistry.findByName(name, WidgetLibrary.material);
        expect(w, isNotNull, reason: 'missing $name');
        expect(w!.decomposes, hasLength(1), reason: '$name needs ButtonStyle');
        final recipe = w.decomposes.single;
        expect(
          recipe.structuredRef,
          WireIdRef(library: 'restage.material', wireId: buttonStyle.wireId),
        );
        expect(recipe.targetArg, 'style');
        expect(
          recipe.construction!.receiver,
          isA<OwningWidgetTypeReceiver>(),
        );
        expect(recipe.construction!.memberName, 'styleFrom');
        expect(
          recipe.construction!.variantRef,
          WireIdRef(library: 'restage.material', wireId: styleFrom.wireId),
        );
        for (final mapping in recipe.fieldMappings) {
          expect(
            buttonStyle.fields.any((field) => field.wireId == mapping.fieldRef),
            isTrue,
            reason: '${mapping.fieldRef} must belong to ButtonStyle',
          );
          expect(
            w.properties.any(
              (property) => property.wireId == mapping.propertyRef,
            ),
            isTrue,
            reason: '${mapping.propertyRef} must be declared on $name',
          );
        }
        final hasBorderRadius = w.properties.any(
          (property) => property.name == 'borderRadius',
        );
        if (hasBorderRadius) {
          final shapeField = buttonStyle.fields.singleWhere(
            (field) => field.name == 'shape',
          );
          final shapeMapping = recipe.fieldMappings.singleWhere(
            (mapping) => mapping.fieldRef == shapeField.wireId,
          );
          expect(
            shapeMapping.transform,
            isA<ConstructVariantTransform>(),
          );
          expect(
            (shapeMapping.transform as ConstructVariantTransform)
                .argumentBindings
                .single,
            isA<NestedTransformArgumentBinding>(),
          );
        } else {
          expect(
            recipe.fieldMappings
                .every((mapping) => mapping.transform is IdentityTransform),
            isTrue,
          );
        }
      }
    });

    test('every event-firing button has a matching event property', () {
      // The bijection key on the property side is `firesAs ?? name`,
      // matching the factory emitter's eligibility check.
      for (final w in kRegistry.widgets) {
        for (final event in w.fires) {
          final eventName = event.name; // e.g. onPressed, onTap
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

    test('Badge surfaces offset as an optional offset slot', () {
      final badge = kRegistry.findByName('Badge', WidgetLibrary.material)!;
      final offset = badge.properties.singleWhere((p) => p.name == 'offset');
      expect(offset.type, PropertyType.offset);
      // `Badge({Offset? offset})` defaults to null; the slot is optional with
      // no synthetic default — never a forced `Offset.zero`.
      expect(offset.required, isFalse);
      expect(offset.defaultValue, isNull);
      expect(offset.defaultSource, isNull);
    });

    test('LinearProgressIndicator surfaces backgroundColor', () {
      // The translucent progress track behind the bar — the standard
      // onboarding-progress idiom. A plain `Color?`, so the reflector derives
      // it once it is no longer excluded.
      final w = kRegistry.findByName(
        'LinearProgressIndicator',
        WidgetLibrary.material,
      );
      expect(w, isNotNull);
      final prop =
          w!.properties.where((p) => p.name == 'backgroundColor').toList();
      expect(prop, hasLength(1));
      expect(prop.single.type, PropertyType.color);
    });
  });
}
