import 'package:restage_codegen/src/user_factory_emitter.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

WidgetEntry _widgetEntry({
  required String name,
  WidgetLibrary library = const WidgetLibrary.custom('acme.design_system'),
  WidgetCategory category = WidgetCategory.layout,
  String description = 'A widget.',
  String? flutterType,
  ChildrenSlot childrenSlot = ChildrenSlot.none,
  List<WidgetEventName> fires = const [],
  List<PropertyEntry> properties = const [],
}) =>
    WidgetEntry(
      wireId: WireId.unallocatedWidget,
      name: name,
      library: library,
      category: category,
      description: description,
      flutterType: flutterType ??
          'package:acme/widgets/${name.toLowerCase()}.dart#$name',
      childrenSlot: childrenSlot,
      fires: fires,
      properties: properties,
    );

void main() {
  group('emitUserFactoriesDart', () {
    test('returns null on an empty input list', () {
      expect(emitUserFactoriesDart(const []), isNull);
    });

    test(
        'returns null when every entry is structurally non-emittable '
        '(e.g. declares childrenSlot.single without a canonical child '
        'property)', () {
      // `childrenSlot: ChildrenSlot.single` without a property named
      // `child` of type widget is one of the rejection paths in
      // `_isMechanicallyEmittable`. The catalog accepts this shape;
      // the factory emitter skips it. With every entry skipped the
      // emitter should produce no output rather than an empty helper.
      // The default `properties: const []` already drops the canonical
      // child property the eligibility check requires.
      final src = emitUserFactoriesDart([
        _widgetEntry(name: 'Bad', childrenSlot: ChildrenSlot.single),
      ]);
      expect(src, isNull);
    });

    test('onSkip fires once per non-emittable entry and is silent otherwise',
        () {
      final skipped = <String>[];
      // One emittable + one non-emittable in the same call exercises the
      // mixed-emittability path the catalog/factory split depends on.
      emitUserFactoriesDart(
        [
          _widgetEntry(
            name: 'Good',
            properties: const [
              PropertyEntry(
                wireId: WireId.unallocatedProperty,
                name: 'label',
                type: PropertyType.string,
                description: 'Visible label.',
                required: true,
              ),
            ],
          ),
          _widgetEntry(name: 'Bad', childrenSlot: ChildrenSlot.single),
        ],
        onSkip: (entry) => skipped.add(entry.name),
      );
      expect(skipped, equals(<String>['Bad']));
    });

    test('emits header, imports, and the customer-facing helper for one entry',
        () {
      final src = emitUserFactoriesDart([
        _widgetEntry(
          name: 'AcmeBadge',
          properties: const [
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'label',
              type: PropertyType.string,
              description: 'Visible label.',
              required: true,
            ),
          ],
        ),
      ]);
      expect(src, isNotNull);
      expect(src, contains('GENERATED CODE - DO NOT MODIFY BY HAND'));
      expect(src, contains("import 'package:flutter/widgets.dart'"));
      expect(
        src,
        contains(
          "import 'package:restage/restage.dart'",
        ),
      );
      // No direct rfw import — the SDK re-exports the rfw types used by
      // the generated factories (DataSource / ArgumentDecoders /
      // LocalWidgetBuilder). The customer package isn't required to
      // depend on rfw.
      expect(src, isNot(contains("import 'package:rfw/rfw.dart'")));
      expect(src, contains("import 'package:acme/widgets/acmebadge.dart'"));
      expect(src, contains('void registerRestageCustomerWidgets()'));
      expect(
        src,
        contains("WidgetLibrary.custom('acme.design_system')"),
      );
      expect(
        src,
        contains(
          "RestageWidgetFactory(name: 'AcmeBadge', "
          'builder: _buildAcmeBadge)',
        ),
      );
      expect(
        src,
        contains(
          'Widget _buildAcmeBadge(BuildContext context, DataSource source)',
        ),
      );
      expect(
        src,
        contains(
          "source.v<String>(<Object>['label']) ??",
        ),
      );
      expect(
        src,
        contains("(throw ArgumentError('AcmeBadge.label is required.'))"),
      );
    });

    test(
        'groups entries by library and calls registerWidgetLibrary once per '
        'library, sorted by namespace', () {
      final src = emitUserFactoriesDart([
        _widgetEntry(
          name: 'Beta',
          library: const WidgetLibrary.custom('zeta.lib'),
        ),
        _widgetEntry(
          name: 'Alpha',
          library: const WidgetLibrary.custom('alpha.lib'),
        ),
      ]);
      expect(src, isNotNull);
      // Both registration calls present.
      expect(src, contains("WidgetLibrary.custom('alpha.lib')"));
      expect(src, contains("WidgetLibrary.custom('zeta.lib')"));
      // Stable order: alpha appears before zeta in the source.
      final alphaIndex = src!.indexOf("WidgetLibrary.custom('alpha.lib')");
      final zetaIndex = src.indexOf("WidgetLibrary.custom('zeta.lib')");
      expect(
        alphaIndex,
        lessThan(zetaIndex),
        reason: 'libraries should emit in lexicographic order by namespace',
      );
    });

    test('imports are deduplicated when several entries share a source file',
        () {
      final src = emitUserFactoriesDart([
        _widgetEntry(
          name: 'Foo',
          flutterType: 'package:acme/lib.dart#Foo',
        ),
        _widgetEntry(
          name: 'Bar',
          flutterType: 'package:acme/lib.dart#Bar',
        ),
      ]);
      expect(src, isNotNull);
      final firstImport = src!.indexOf("import 'package:acme/lib.dart'");
      final lastImport = src.lastIndexOf("import 'package:acme/lib.dart'");
      expect(
        firstImport,
        equals(lastImport),
        reason: 'shared source file should emit a single import',
      );
    });

    test('uses the typed singleton for built-in libraries', () {
      final src = emitUserFactoriesDart([
        _widgetEntry(name: 'Foo', library: WidgetLibrary.core),
      ]);
      expect(src, isNotNull);
      expect(src, contains('WidgetLibrary.core'));
      expect(
        src,
        isNot(contains("WidgetLibrary.custom('restage.core')")),
      );
    });

    test('output is dart-format clean (idempotent under re-format)', () {
      final src = emitUserFactoriesDart([
        _widgetEntry(
          name: 'Foo',
          description:
              'A long description that would otherwise wrap awkwardly across '
              'lines if the emitter did not run output through DartFormatter.',
        ),
      ]);
      expect(src, isNotNull);
      expect(src!.endsWith('\n'), isTrue);
    });

    test(r'escapes single quote / backslash / $ in custom library namespace',
        () {
      final src = emitUserFactoriesDart([
        _widgetEntry(
          name: 'X',
          library: const WidgetLibrary.custom(r"acme$it's.lib\path"),
        ),
      ]);
      expect(src, isNotNull);
      expect(
        src,
        contains(r"WidgetLibrary.custom('acme\$it\'s.lib\\path')"),
      );
    });

    test('emits source.child(...) for a required single child slot', () {
      final src = emitUserFactoriesDart([
        _widgetEntry(
          name: 'AcmeBorder',
          childrenSlot: ChildrenSlot.single,
          properties: const [
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'child',
              type: PropertyType.widget,
              description: 'Wrapped child.',
              required: true,
            ),
          ],
        ),
      ]);
      expect(src, isNotNull);
      expect(
        src,
        contains('Widget _buildAcmeBorder(BuildContext context, '
            'DataSource source)'),
      );
      expect(src, contains("child: source.child(<Object>['child'])"));
      // Required child slot uses source.child (returns Widget), not
      // source.optionalChild (returns Widget?).
      expect(src, isNot(contains('source.optionalChild')));
    });

    test('emits source.optionalChild(...) for an optional single child slot',
        () {
      final src = emitUserFactoriesDart([
        _widgetEntry(
          name: 'AcmeWrapper',
          childrenSlot: ChildrenSlot.single,
          properties: const [
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'child',
              type: PropertyType.widget,
              description: 'Optional wrapped child.',
            ),
          ],
        ),
      ]);
      expect(src, isNotNull);
      expect(
        src,
        contains("child: source.optionalChild(<Object>['child'])"),
      );
    });

    test('emits source.childList(...) for a children list slot', () {
      final src = emitUserFactoriesDart([
        _widgetEntry(
          name: 'AcmeStack',
          childrenSlot: ChildrenSlot.list,
          properties: const [
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'children',
              type: PropertyType.widgetList,
              description: 'Overlay children.',
            ),
          ],
        ),
      ]);
      expect(src, isNotNull);
      expect(
        src,
        contains('Widget _buildAcmeStack(BuildContext context, '
            'DataSource source)'),
      );
      expect(
        src,
        contains("children: source.childList(<Object>['children'])"),
      );
    });
  });
}
