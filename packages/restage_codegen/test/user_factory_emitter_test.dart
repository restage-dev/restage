import 'package:restage_codegen/src/user_factory_emitter.dart';
import 'package:restage_shared/restage_shared.dart'
    show kReservedPreviewConstructorName, kReservedPreviewLibraryName;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

WidgetEntry _widgetEntry({
  required String name,
  WidgetLibrary library = const WidgetLibrary.custom('acme.design_system'),
  WidgetCategory category = WidgetCategory.layout,
  String description = 'A widget.',
  String? flutterType,
  ChildrenSlot childrenSlot = ChildrenSlot.none,
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
      properties: properties,
    );

void main() {
  group('emitUserFactoriesDart', () {
    test('returns null on an empty input list', () {
      expect(emitUserFactoriesDart(const []), isNull);
    });

    test('rejects preview-only namespace and constructor claims', () {
      expect(
        () => emitUserFactoriesDart([
          _widgetEntry(
            name: 'Badge',
            library: const WidgetLibrary.custom(
              kReservedPreviewLibraryName,
            ),
          ),
        ]),
        throwsArgumentError,
      );
      expect(
        () => emitUserFactoriesDart([
          _widgetEntry(name: kReservedPreviewConstructorName),
        ]),
        throwsArgumentError,
      );
    });

    test(
        'returns null when every entry is structurally non-emittable '
        '(e.g. malformed historical wire slot without its property)', () {
      // A historical `ChildrenSlot.single` wire value without the corresponding
      // `child` property is one rejection path in `_isMechanicallyEmittable`.
      // Customer annotations can no longer create this malformed shape, but
      // decoded or manually assembled wire entries still need a hard guard.
      // The catalog model accepts this shape;
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
      expect(src, contains('public unnamed generative constructors'));
      expect(src, isNot(contains('@RestageProperty annotations')));
      expect(src, isNot(contains('edit the @RestageWidget /')));
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
        'qualifies the constructor with the import alias when the package has '
        'NO structured-type properties (regression)', () {
      // A `@RestageWidget` package where every property is a scalar (no
      // structured-type decomposition) has no structured-type context, so
      // the customer reconstruction record is absent. The import-alias map
      // is nonetheless always computed, and the import block emits each
      // customer library aliased (`as s0`). The constructor call MUST use
      // the same alias — a bare `AcmeBadge(...)` reference is undefined
      // under the prefixed import and fails analysis in the generated
      // `user_factories.g.dart`.
      final src = emitUserFactoriesDart([
        _widgetEntry(
          name: 'AcmeBadge',
          flutterType: 'package:acme/widgets/acme_badge.dart#AcmeBadge',
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
      // The library is imported with the uniform-prefix alias.
      expect(
        src,
        contains("import 'package:acme/widgets/acme_badge.dart' as s0;"),
      );
      // The constructor is called through that alias, not bare.
      expect(src, contains('return s0.AcmeBadge('));
      expect(
        src,
        isNot(contains('return AcmeBadge(')),
        reason: 'a bare constructor reference is undefined under the '
            'prefixed import and would not analyze',
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
              constructorNullable: true,
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

    test(
      'required nullable widget decoders and casts follow constructor '
      'nullability for named and positional arguments',
      () {
        final src = emitUserFactoriesDart([
          _widgetEntry(
            name: 'RequiredNullableRegions',
            properties: const <PropertyEntry>[
              PropertyEntry(
                wireId: WireId.unallocatedProperty,
                name: 'positionalNullable',
                type: PropertyType.widget,
                description: 'Required nullable positional region.',
                required: true,
                positional: true,
                constructorNullable: true,
                widgetType: 'PreferredSizeWidget',
              ),
              PropertyEntry(
                wireId: WireId.unallocatedProperty,
                name: 'positionalControl',
                type: PropertyType.widget,
                description: 'Required non-nullable positional control.',
                required: true,
                positional: true,
                widgetType: 'PreferredSizeWidget',
              ),
              PropertyEntry(
                wireId: WireId.unallocatedProperty,
                name: 'namedNullable',
                type: PropertyType.widget,
                description: 'Required nullable named region.',
                required: true,
                constructorNullable: true,
                widgetType: 'PreferredSizeWidget',
              ),
              PropertyEntry(
                wireId: WireId.unallocatedProperty,
                name: 'namedControl',
                type: PropertyType.widget,
                description: 'Required non-nullable named control.',
                required: true,
                widgetType: 'PreferredSizeWidget',
              ),
            ],
          ),
        ]);

        expect(src, isNotNull);
        final flat = src!.replaceAll(RegExp(r'\s+'), ' ');
        expect(
          flat,
          contains(
            "source.optionalChild(<Object>['positionalNullable']) "
            'as PreferredSizeWidget?',
          ),
        );
        expect(
          flat,
          contains(
            "source.child(<Object>['positionalControl']) "
            'as PreferredSizeWidget',
          ),
        );
        expect(
          flat,
          contains(
            "namedNullable: source.optionalChild(<Object>['namedNullable']) "
            'as PreferredSizeWidget?',
          ),
        );
        expect(
          flat,
          contains(
            "namedControl: source.child(<Object>['namedControl']) "
            'as PreferredSizeWidget',
          ),
        );
      },
    );

    test(
      'customer factories lower every exact widget and widget-list property',
      () {
        final src = emitUserFactoriesDart([
          _widgetEntry(
            name: 'MultiRegion',
            properties: const <PropertyEntry>[
              PropertyEntry(
                wireId: WireId.unallocatedProperty,
                name: 'header',
                type: PropertyType.widget,
                description: 'Header region.',
                required: true,
                positional: true,
              ),
              PropertyEntry(
                wireId: WireId.unallocatedProperty,
                name: 'primaryActions',
                type: PropertyType.widgetList,
                description: 'Primary actions.',
                required: true,
              ),
              PropertyEntry(
                wireId: WireId.unallocatedProperty,
                name: 'footer',
                type: PropertyType.widget,
                description: 'Optional footer.',
                constructorNullable: true,
              ),
              PropertyEntry(
                wireId: WireId.unallocatedProperty,
                name: 'secondaryActions',
                type: PropertyType.widgetList,
                description: 'Optional secondary actions.',
                constructorNullable: true,
              ),
            ],
          ),
        ]);

        expect(src, isNotNull);
        final flat = src!.replaceAll(RegExp(r'\s+'), ' ');
        expect(
          flat,
          contains("source.child(<Object>['header'])"),
        );
        expect(
          flat,
          contains(
            "primaryActions: source.childList(<Object>['primaryActions'])",
          ),
        );
        expect(
          flat,
          contains("footer: source.optionalChild(<Object>['footer'])"),
        );
        expect(
          flat,
          contains(
            "secondaryActions: source.isList(<Object>['secondaryActions']) "
            "? source.childList(<Object>['secondaryActions']) : null",
          ),
        );
      },
    );
  });
}
