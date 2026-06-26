import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:restage_codegen/src/a2ui/a2ui_event_lowering.dart';
import 'package:restage_codegen/src/a2ui/a2ui_schema_node.dart';
import 'package:restage_codegen/src/a2ui/a2ui_seam_assembly.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// Unit coverage for `assembleA2uiSeams` — the resolver-fed seam assembly that
/// the production build phase drives off `buildStep.resolver`. The function is
/// the unification of the regen proofs' inline `_eventSeam` / `_pairingSeam` /
/// `_richShapes` legs into one catalog-driven pass: for each customer
/// `WidgetEntry` property, an `event` property reflects its constructor
/// parameter into the event seam (+ reads `@RestageProperty(writeBackValue:)`
/// into the pairing seam), a `structured` property reflects into the rich-shape
/// seam, and every other property type is handled by the catalog (no seam).
///
/// These tests resolve the REAL committed interactive + rich-shape fixtures
/// (the same fixtures the regen proofs reflect) via the analyzer and assert the
/// assembled seams match the regen proofs' known values — proving the unified
/// function reproduces the proven inline legs.
const _interactiveFixture =
    '../restage_a2ui/test/generated/interactive_fixture.dart';
const _richShapeFixture =
    '../restage_a2ui/test/generated/rich_shape_fixture.dart';

Future<ResolvedLibraryResult> _resolve(String relativePath) async {
  final abs = File('${Directory.current.path}/$relativePath')
      .resolveSymbolicLinksSync();
  final collection = AnalysisContextCollection(includedPaths: [abs]);
  final context = collection.contextFor(abs);
  final resolved = await context.currentSession.getResolvedLibrary(abs);
  if (resolved is! ResolvedLibraryResult) {
    throw StateError('failed to resolve $relativePath: $resolved');
  }
  return resolved;
}

ClassElement _classFor(ResolvedLibraryResult library, String name) =>
    library.element.classes.firstWhere(
      (c) => c.name == name,
      orElse: () => throw StateError("no class '$name' in the fixture"),
    );

/// Pairs a hand-built catalog entry with its resolved fixture class — the shape
/// `assembleA2uiSeams` consumes (the production builder matches the merged
/// catalog's customer widgets to the resolved `@RestageWidget` elements by
/// name).
({WidgetEntry entry, ClassElement element}) _widget(
  ResolvedLibraryResult library,
  String name,
  String widgetClass,
  List<PropertyEntry> properties,
) =>
    (
      entry: entry(name: name, properties: properties),
      element: _classFor(library, widgetClass),
    );

void main() {
  group('assembleA2uiSeams — the interactive (event + pairing) legs', () {
    late ResolvedLibraryResult library;

    setUpAll(() async {
      library = await _resolve(_interactiveFixture);
    });

    test('an auto-pair write-back callback reflects into the event seam', () {
      final seams = assembleA2uiSeams([
        _widget(library, 'QuickCheck', 'QuickCheckFixture', [
          prop('selected', PropertyType.integer, required: true),
          prop('onSelected', PropertyType.event, required: true),
        ]),
      ]);

      expect(
        seams.eventSeam[('QuickCheck', 'onSelected')],
        const A2uiCallbackWriteBack(
          A2uiScalarType.integer,
          nullable: false,
          isList: false,
        ),
      );
      // A scalar value property is carried by the catalog, never the rich seam.
      expect(seams.richShapes, isEmpty);
      // An auto-pair callback carries no writeBackValue annotation.
      expect(seams.pairingSeam, isEmpty);
    });

    test('a list write-back callback reflects as an isList write-back', () {
      final seams = assembleA2uiSeams([
        _widget(library, 'MultiSelect', 'MultiSelectFixture', [
          prop('chosen', PropertyType.stringList, required: true),
          prop('onChosen', PropertyType.event, required: true),
        ]),
      ]);

      expect(
        seams.eventSeam[('MultiSelect', 'onChosen')],
        const A2uiCallbackWriteBack(
          A2uiScalarType.string,
          nullable: false,
          isList: true,
        ),
      );
      expect(seams.pairingSeam, isEmpty);
    });

    test('a void callback reflects as a dispatch', () {
      final seams = assembleA2uiSeams([
        _widget(library, 'ActionButton', 'ActionButtonFixture', [
          prop('label', PropertyType.string, required: true),
          prop('onPressed', PropertyType.event, required: true),
        ]),
      ]);

      expect(
        seams.eventSeam[('ActionButton', 'onPressed')],
        const A2uiCallbackDispatch(),
      );
      expect(seams.pairingSeam, isEmpty);
    });

    test(
        'an event property with no matching constructor parameter fails LOUD '
        '(a catalog/constructor inconsistency, never a silent drop)', () {
      // `QuickCheckFixture` has no `onPhantom` constructor parameter, so the
      // catalog declares an event property the widget cannot receive — the
      // fail-closed-LOUD disposition is a build failure, not a silent skip.
      expect(
        () => assembleA2uiSeams([
          _widget(library, 'QuickCheck', 'QuickCheckFixture', [
            prop('onPhantom', PropertyType.event, required: true),
          ]),
        ]),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('onPhantom'),
              contains('no matching default-constructor parameter'),
            ),
          ),
        ),
      );
    });

    test(
        'the multi-control case reads ONLY the annotated callbacks into the '
        'pairing seam (@RestageProperty(writeBackValue:))', () {
      final seams = assembleA2uiSeams([
        _widget(library, 'Range', 'RangeFixture', [
          prop('low', PropertyType.integer, required: true),
          prop('high', PropertyType.integer, required: true),
          prop('onLow', PropertyType.event, required: true),
          prop('onHigh', PropertyType.event, required: true),
        ]),
      ]);

      expect(
        seams.eventSeam[('Range', 'onLow')],
        const A2uiCallbackWriteBack(
          A2uiScalarType.integer,
          nullable: false,
          isList: false,
        ),
      );
      expect(
        seams.eventSeam[('Range', 'onHigh')],
        const A2uiCallbackWriteBack(
          A2uiScalarType.integer,
          nullable: false,
          isList: false,
        ),
      );
      // The explicit pairings — and ONLY these (the auto-pair / dispatch
      // callbacks across the other widgets carry no writeBackValue).
      expect(seams.pairingSeam, {
        ('Range', 'onLow'): 'low',
        ('Range', 'onHigh'): 'high',
      });
    });
  });

  group('assembleA2uiSeams — the rich-shape (structured) leg', () {
    late ResolvedLibraryResult library;

    setUpAll(() async {
      library = await _resolve(_richShapeFixture);
    });

    test('a structured property reflects into the rich-shape seam', () {
      final seams = assembleA2uiSeams([
        _widget(library, 'PlanCard', 'PlanCardFixture', [
          prop('plan', PropertyType.structured, required: true),
        ]),
      ]);

      final node = seams.richShapes[('PlanCard', 'plan')];
      expect(node, isA<ObjectNode>());
      expect(
        ((node! as ObjectNode).construction! as A2uiClassConstruction)
            .dartTypeName,
        'PlanTier',
      );
      // A structured property produces no event/pairing seam.
      expect(seams.eventSeam, isEmpty);
      expect(seams.pairingSeam, isEmpty);
    });
  });
}
