import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// ENCODE side for a LIST-of-customer-structured value: a `List<Plan>` authored
/// in a paywall body compiles to a list of field-name-keyed maps the decoder
/// faithfully reconstructs, element by element. The list encode composes the
/// single-value encode (each element recurses through the same translator), so
/// the same fail-closed guards (a non-canonical constructor defers loud) apply
/// per element — so the list wrapper never silently emits a wrong or partial
/// element.
const String _probe = kSyntheticProbeLibraryUri;

Catalog _catalog(List<StructuredEntry> structuredTypes) => Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: '1970-01-01T00:00:00Z',
      libraries: {
        WidgetLibrary.material: const LibraryInfo(version: '1.0.0'),
      },
      widgets: const [],
      structuredTypes: structuredTypes,
    );

/// `Plan({required name, badge})` with ONLY its canonical unnamed constructor.
StructuredEntry _planEntry() => StructuredEntry(
      wireId: WireId('s0001'),
      name: 'Plan',
      library: WidgetLibrary.material,
      description: '',
      sourceType: '$_probe#Plan',
      fields: [
        StructuredField(
          wireId: WireId('p0001'),
          name: 'name',
          type: PropertyType.string,
          description: '',
          required: true,
        ),
        StructuredField(
          wireId: WireId('p0002'),
          name: 'badge',
          type: PropertyType.string,
          description: '',
        ),
      ],
      variants: [ConstructorVariant(wireId: WireId('v0001'))],
    );

/// `Plan({required name, badge})` plus a convenience `Plan.pro` named ctor —
/// the canonical unnamed variant is the reconstruction target, so authoring via
/// `.pro` must defer loud (its wire value would reconstruct through the wrong
/// constructor).
StructuredEntry _planWithNamedCtorEntry() => StructuredEntry(
      wireId: WireId('s0001'),
      name: 'Plan',
      library: WidgetLibrary.material,
      description: '',
      sourceType: '$_probe#Plan',
      fields: [
        StructuredField(
          wireId: WireId('p0001'),
          name: 'name',
          type: PropertyType.string,
          description: '',
          required: true,
        ),
        StructuredField(
          wireId: WireId('p0002'),
          name: 'badge',
          type: PropertyType.string,
          description: '',
        ),
      ],
      variants: [
        ConstructorVariant(wireId: WireId('v0001')),
        ConstructorVariant(wireId: WireId('v0002'), namedConstructor: 'pro'),
      ],
    );

void main() {
  group('customer structured LIST value encode', () {
    test('a list of canonical values encodes to a list of maps, in order',
        () async {
      final expr = await parseExpressionFromSourceForTest('''
        class Plan {
          const Plan({required this.name, this.badge});
          final String name;
          final String? badge;
        }
        Object x() => const [
          Plan(name: 'Pro', badge: 'Best'),
          Plan(name: 'Starter'),
        ];
      ''');
      final translator = ExpressionTranslator(
        catalog: _catalog([_planEntry()]),
        helpers: HelperRegistry(),
      );

      final result = translator.translate(expr);

      expect(result.issues, isEmpty);
      expect(result.dsl, '[{name: "Pro", badge: "Best"}, {name: "Starter"}]');
    });

    test(
        'a list containing a NON-CANONICAL constructor invocation defers LOUD '
        '(never a silently wrong / partial list)', () async {
      final expr = await parseExpressionFromSourceForTest('''
        class Plan {
          const Plan({required this.name, this.badge});
          const Plan.pro({required this.name}) : badge = 'PRO';
          final String name;
          final String? badge;
        }
        Object x() => const [
          Plan(name: 'Pro'),
          Plan.pro(name: 'Starter'),
        ];
      ''');
      final translator = ExpressionTranslator(
        catalog: _catalog([_planWithNamedCtorEntry()]),
        helpers: HelperRegistry(),
      );

      final result = translator.translate(expr);

      // The `.pro` element cannot round-trip through the canonical constructor,
      // so the encode raises an issue rather than shipping a wrong element.
      expect(result.issues, isNotEmpty);
    });
  });
}
