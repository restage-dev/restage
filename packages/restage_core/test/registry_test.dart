import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/registry.dart';
import 'package:restage_shared/restage_shared.dart';

void main() {
  group('restage_core registry', () {
    test('every entry belongs to the core library', () {
      expect(
        kRegistry.libraries.keys.toList(),
        equals(<WidgetLibrary>[WidgetLibrary.core]),
        reason: 'a per-package registry declares exactly its own library',
      );
      expect(
        kRegistry.widgets.every((w) => w.library == WidgetLibrary.core),
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
      // Most core widgets are real Flutter framework widgets
      // (`package:flutter/...`); a small set of curated first-party widgets
      // authored inside the package itself (e.g. the formatting widgets)
      // resolve to `package:restage_core/...`. Both are valid.
      for (final w in kRegistry.widgets) {
        expect(
          w.flutterType,
          anyOf(
            startsWith('package:flutter/'),
            startsWith('package:restage_core/'),
          ),
          reason: '${w.name} must point at a real Flutter widget or a '
              'first-party restage_core widget',
        );
      }
    });

    test('Text decomposes TextStyle with full native mapping', () {
      final text = kRegistry.findByName('Text', WidgetLibrary.core);
      expect(text, isNotNull);
      expect(text!.decomposes, hasLength(1));

      final textStyle = kRegistry.structuredTypes.singleWhere(
        (entry) => entry.name == 'TextStyle',
      );
      final constructor = textStyle.variants.singleWhere(
        (variant) =>
            variant is ConstructorVariant && variant.namedConstructor == null,
      ) as ConstructorVariant;
      final recipe = text.decomposes.single;
      expect(
        recipe.structuredRef,
        WireIdRef(library: 'restage.core', wireId: textStyle.wireId),
      );
      expect(recipe.targetArg, 'style');
      expect(
        recipe.construction!.receiver,
        isA<ResultStructuredTypeReceiver>(),
      );
      expect(
        recipe.construction!.variantRef,
        WireIdRef(library: 'restage.core', wireId: constructor.wireId),
      );

      const mappedFieldNames = [
        'inherit',
        'color',
        'backgroundColor',
        'fontFamily',
        'fontSize',
        'fontWeight',
        'fontStyle',
        'letterSpacing',
        'wordSpacing',
        'textBaseline',
        'height',
        'leadingDistribution',
        'locale',
        'foreground',
        'background',
        'shadows',
        'fontFeatures',
        'fontVariations',
        'decoration',
        'decorationColor',
        'decorationStyle',
        'decorationThickness',
        'debugLabel',
        'fontFamilyFallback',
        'overflow',
      ];
      const listProjectedFields = {
        'shadows',
        'fontFeatures',
        'fontVariations',
        'fontFamilyFallback',
      };

      expect(recipe.fieldMappings, hasLength(mappedFieldNames.length));
      for (final name in mappedFieldNames) {
        final field = textStyle.fields.singleWhere(
          (candidate) => candidate.name == name,
        );
        final property = text.properties.singleWhere(
          (candidate) => candidate.name == name,
        );
        final mapping = recipe.fieldMappings.singleWhere(
          (candidate) =>
              candidate.fieldRef == field.wireId &&
              candidate.propertyRef == property.wireId,
        );
        if (listProjectedFields.contains(name)) {
          expect(mapping.transform, isA<ProjectListTransform>());
          expect(
            (mapping.transform as ProjectListTransform).itemTransform,
            isA<IdentityTransform>(),
          );
        } else {
          expect(mapping.transform, isA<IdentityTransform>());
        }
      }

      expect(
        text.properties.any((property) => property.name == 'fontPackage'),
        isTrue,
      );
      final inheritProperty = text.properties.singleWhere(
        (property) => property.name == 'inherit',
      );
      expect(inheritProperty.defaultValue, true);
      final packageParameter = constructor.parameters.singleWhere(
        (parameter) => parameter.name == 'package',
      );
      final fontPackage = text.properties.singleWhere(
        (property) => property.name == 'fontPackage',
      );
      expect(
        recipe.parameterMappings.any(
          (mapping) =>
              mapping.parameterRef == packageParameter.wireId &&
              mapping.propertyRef == fontPackage.wireId &&
              mapping.transform is IdentityTransform,
        ),
        isTrue,
      );
    });

    group('declarative Animated* motion suite', () {
      // The implicit-animation family: each surfaces its animated property
      // plus the shared `duration`, wraps a single child, and renders
      // natively in the generic RFW Viewer (no imperative escape hatch).
      // `curve` and `onEnd` are common `ImplicitlyAnimatedWidget` knobs:
      // both are catalogued as closed, declarative controls.
      const signatureProperty = <String, String>{
        'AnimatedContainer': 'width',
        'AnimatedOpacity': 'opacity',
        'AnimatedPadding': 'padding',
        'AnimatedAlign': 'alignment',
        'AnimatedPositioned': 'left',
        'AnimatedScale': 'scale',
        'AnimatedRotation': 'turns',
        'AnimatedDefaultTextStyle': 'fontSize',
        'AnimatedSize': 'alignment',
        'AnimatedSlide': 'offset',
      };

      test('curve support remains scoped to the curated set', () {
        final curveOwners = {
          for (final widget in kRegistry.widgets)
            if (widget.properties.any((p) => p.type == PropertyType.curve))
              widget.name,
        };
        // The Animated* implicit-animation family, plus the first-party motion
        // widgets that legitimately expose a tween `curve` (RestageFadeIn's fade
        // easing, RestagePulse's sweep easing). No other widget surfaces curve.
        expect(curveOwners, {
          ...signatureProperty.keys,
          'RestageFadeIn',
          'RestagePulse',
        });

        final fadeInImage = kRegistry.findByName(
          'FadeInImageAssetNetwork',
          WidgetLibrary.core,
        );
        expect(fadeInImage, isNotNull);
        expect(
          fadeInImage!.properties.map((p) => p.name),
          isNot(containsAll(['fadeOutCurve', 'fadeInCurve'])),
        );
      });

      for (final entry in signatureProperty.entries) {
        test(
            '${entry.key} is curated with its animated property + '
            'duration, curve, onEnd, and a single child', () {
          final widget = kRegistry.findByName(entry.key, WidgetLibrary.core);
          expect(
            widget,
            isNotNull,
            reason: '${entry.key} must be curated in the core registry',
          );
          final propertyNames = widget!.properties.map((p) => p.name).toSet();
          expect(
            propertyNames,
            contains(entry.value),
            reason: '${entry.key} surfaces its animated property',
          );
          expect(
            propertyNames,
            contains('duration'),
            reason: 'every implicit-animation widget surfaces its duration',
          );
          expect(
            propertyNames,
            contains('curve'),
            reason: 'every implicit-animation widget surfaces curve control',
          );
          expect(
            propertyNames,
            contains('onEnd'),
            reason: 'every implicit-animation widget surfaces onEnd',
          );
          final curve = widget.properties.singleWhere(
            (p) => p.name == 'curve',
          );
          expect(curve.type, PropertyType.curve);
          expect(curve.defaultValue, 'linear');
          expect(
            widget.properties.singleWhere((p) => p.name == 'onEnd').type,
            PropertyType.event,
          );
          expect(widget.fires, contains(WidgetEventName.onEnd));
          expect(
            widget.childrenSlot,
            ChildrenSlot.single,
            reason: '${entry.key} wraps a single child',
          );
        });
      }

      test(
          'AnimatedDefaultTextStyle decomposes TextStyle onto flat '
          'properties like DefaultTextStyle', () {
        final widget = kRegistry.findByName(
          'AnimatedDefaultTextStyle',
          WidgetLibrary.core,
        );
        expect(widget, isNotNull);
        expect(widget!.decomposes, hasLength(1));
        expect(widget.decomposes.single.targetArg, 'style');
        final propertyNames = widget.properties.map((p) => p.name).toSet();
        expect(
          propertyNames,
          containsAll(<String>['color', 'fontSize', 'fontWeight']),
          reason: 'the TextStyle synthetics are hoisted onto flat properties',
        );
      });

      test(
          'alignment is surfaced on AnimatedAlign and as concrete Alignment '
          'on AnimatedScale/AnimatedRotation', () {
        PropertyEntry alignmentOf(String name) => kRegistry
            .findByName(name, WidgetLibrary.core)!
            .properties
            .singleWhere((p) => p.name == 'alignment');

        // AnimatedAlign.alignment is `AlignmentGeometry` — the catalog's
        // alignment surface targets it, so it is surfaced.
        expect(alignmentOf('AnimatedAlign').type, PropertyType.alignment);
        // AnimatedScale/AnimatedRotation type `alignment` as the concrete
        // `Alignment`, so they route through the concrete alignmentXY decoder.
        for (final name in ['AnimatedScale', 'AnimatedRotation']) {
          final alignment = alignmentOf(name);
          expect(alignment.type, PropertyType.alignmentXY);
          expect(alignment.defaultValue, 'center');
        }
      });

      test('AnimatedSize is curated with duration, alignment, and clipBehavior',
          () {
        final widget = kRegistry.findByName(
          'AnimatedSize',
          WidgetLibrary.core,
        );
        expect(widget, isNotNull);
        final propertyNames = widget!.properties.map((p) => p.name).toSet();
        expect(
          propertyNames,
          containsAll(<String>[
            'duration',
            'reverseDuration',
            'curve',
            'onEnd',
            'alignment',
            'clipBehavior',
            'child',
          ]),
        );
        expect(widget.childrenSlot, ChildrenSlot.single);
        final alignment = widget.properties.singleWhere(
          (p) => p.name == 'alignment',
        );
        expect(alignment.type, PropertyType.alignment);
        expect(alignment.defaultValue, 'center');
      });

      test('pure-curation layout batch widgets are present', () {
        final expectations = <String, Set<String>>{
          'IntrinsicHeight': {'child'},
          'IntrinsicWidth': {'stepWidth', 'stepHeight', 'child'},
          'FractionallySizedBox': {
            'alignment',
            'widthFactor',
            'heightFactor',
            'child',
          },
        };

        for (final entry in expectations.entries) {
          final widget = kRegistry.findByName(entry.key, WidgetLibrary.core);
          expect(widget, isNotNull, reason: '${entry.key} must be curated');
          expect(widget!.category, WidgetCategory.layout);
          expect(widget.childrenSlot, ChildrenSlot.single);
          expect(
            widget.properties.map((p) => p.name).toSet(),
            containsAll(entry.value),
          );
        }

        final fractional = kRegistry.findByName(
          'FractionallySizedBox',
          WidgetLibrary.core,
        )!;
        final fractionalAlignment = fractional.properties.singleWhere(
          (p) => p.name == 'alignment',
        );
        expect(fractionalAlignment.type, PropertyType.alignment);
        expect(fractionalAlignment.defaultValue, 'center');
      });
    });

    test('TransformRotate surfaces origin as an optional offset slot', () {
      final transform = kRegistry.findByName(
        'TransformRotate',
        WidgetLibrary.core,
      )!;
      final origin = transform.properties.singleWhere(
        (p) => p.name == 'origin',
      );
      expect(origin.type, PropertyType.offset);
      // `Transform.rotate({Offset? origin})` defaults to null (centre on
      // `alignment`); the slot is optional with no synthetic default — never a
      // forced `Offset.zero`.
      expect(origin.required, isFalse);
      expect(origin.defaultValue, isNull);
      expect(origin.defaultSource, isNull);
    });

    test('scroll views surface keyboardDismissBehavior', () {
      // `ScrollViewKeyboardDismissBehavior` is a clean 2-member enum the
      // reflector surfaces on every scroll view that takes it once it is no
      // longer in the type denylist.
      for (final name in <String>['ListView', 'SingleChildScrollView']) {
        final w = kRegistry.findByName(name, WidgetLibrary.core);
        expect(w, isNotNull, reason: name);
        final prop = w!.properties
            .where((p) => p.name == 'keyboardDismissBehavior')
            .toList();
        expect(prop, hasLength(1), reason: '$name.keyboardDismissBehavior');
        expect(prop.single.type, PropertyType.enumValue, reason: name);
        expect(
          prop.single.enumType,
          'ScrollViewKeyboardDismissBehavior',
          reason: name,
        );
      }
    });

    test('price widgets compose the fontFeatures TextStyle synthetic', () {
      // FP-1 regression lock: fontFeatures shipped with the native TextStyle
      // decompose, and the formatting widgets carry the same synthetic set, so
      // tabular-figure alignment composes onto a formatted price.
      for (final name in <String>['RestagePrice', 'RestageFormattedNumber']) {
        final w = kRegistry.findByName(name, WidgetLibrary.core);
        expect(w, isNotNull, reason: name);
        final prop =
            w!.properties.where((p) => p.name == 'fontFeatures').toList();
        expect(prop, hasLength(1), reason: '$name.fontFeatures');
        expect(prop.single.type, PropertyType.fontFeatureList, reason: name);
      }
    });
  });
}
