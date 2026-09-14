import 'dart:io';

import 'package:restage_codegen/src/capability_derivation.dart';
import 'package:restage_codegen/src/issue.dart' show IssueCode;
import 'package:restage_shared/restage_shared.dart'
    show LibraryRequirement, WidgetVocabulary;
import 'package:restage_shared/rfw_formats.dart' show parseLibraryFile;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// The catalog a built-in library actually ships, read from the committed
/// `catalog.json` — tolerant of either the package dir or the workspace root as
/// cwd, the way the sibling built-in tests resolve it.
Catalog _committedCatalog(String package) {
  final fromPackage = File('../$package/lib/src/widget_catalog/catalog.json');
  final file = fromPackage.existsSync()
      ? fromPackage
      : File('packages/$package/lib/src/widget_catalog/catalog.json');
  return decodeCatalog(file.readAsStringSync());
}

void main() {
  // A built-in (restage.core) catalog whose widgets carry distinct
  // `sinceVersion`s so the floor (max over referenced built-ins) is testable.
  final builtInCatalog = catalogWith([
    entry(
      name: 'Text',
      properties: [prop('text', PropertyType.string, required: true)],
    ),
    entry(
      name: 'Column',
      childrenSlot: ChildrenSlot.list,
      properties: [prop('children', PropertyType.widgetList)],
    ),
    entry(
      name: 'Banner',
      properties: const [],
      sinceVersion: 2,
    ),
    entry(
      name: 'Hero',
      properties: const [],
      sinceVersion: 3,
    ),
  ]);

  group('deriveCapabilityManifest — builtInFloor', () {
    test('a surface using only baseline built-ins floors at the baseline', () {
      const dsl = '''
        import restage.core;
        widget Paywall = Text(text: "hi");
      ''';
      final surface = parseLibraryFile(dsl, sourceIdentifier: 'test');
      final result = deriveCapabilityManifest(surface, builtInCatalog);
      expect(result.issues, isEmpty);
      expect(result.manifest, isNotNull);
      expect(result.manifest!.builtInFloor, kBaselineCatalogVersion);
      expect(result.manifest!.requiredLibraries, isEmpty);
    });

    test('floors at the highest sinceVersion over referenced built-ins', () {
      const dsl = '''
        import restage.core;
        widget Paywall = Banner();
      ''';
      final surface = parseLibraryFile(dsl, sourceIdentifier: 'test');
      final result = deriveCapabilityManifest(surface, builtInCatalog);
      expect(result.issues, isEmpty);
      expect(result.manifest!.builtInFloor, 2);
    });

    test('takes the MAX sinceVersion across several referenced built-ins', () {
      const dsl = '''
        import restage.core;
        widget Paywall = Column(children: [Text(text: "a"), Banner(), Hero()]);
      ''';
      final surface = parseLibraryFile(dsl, sourceIdentifier: 'test');
      final result = deriveCapabilityManifest(surface, builtInCatalog);
      expect(result.issues, isEmpty);
      expect(result.manifest!.builtInFloor, 3);
    });

    test('walks nested children for the floor (not just the root)', () {
      const dsl = '''
        import restage.core;
        widget Paywall = Column(children: [Text(text: "a"), Hero()]);
      ''';
      final surface = parseLibraryFile(dsl, sourceIdentifier: 'test');
      final result = deriveCapabilityManifest(surface, builtInCatalog);
      expect(result.manifest!.builtInFloor, 3);
    });

    test('includes a constructor in a list loop output', () {
      const dsl = '''
        import restage.core;
        widget Paywall = Column(children: [
          ...for value in data.context.values: Hero()
        ]);
      ''';
      final surface = parseLibraryFile(dsl, sourceIdentifier: 'test');
      final result = deriveCapabilityManifest(surface, builtInCatalog);

      expect(result.issues, isEmpty);
      expect(result.manifest!.builtInFloor, 3);
    });

    test('the core version-5 landing stays above its historical global ceiling',
        () {
      // ColoredBox landed at version 5 when Material's version 4 was the
      // global ceiling. Later catalog additions must not move that historical
      // comparison: expanded Icon now legitimately advances Material to 6.
      const oldGlobalCeiling = 4;
      final core = _committedCatalog('restage_core');
      final surface = parseLibraryFile(
        '''
import restage.core;
widget Paywall = ColoredBox(color: 0xFF000000);
''',
        sourceIdentifier: 'test',
      );
      final result = deriveCapabilityManifest(surface, core);
      expect(result.issues, isEmpty);
      expect(result.manifest!.builtInFloor, 5);
      expect(result.manifest!.builtInFloor, greaterThan(oldGlobalCeiling));
    });

    test('a surface referencing no catalog widgets floors at the baseline', () {
      // A library-local `widget` definition referenced by name is not a catalog
      // lookup; with no catalog references at all the floor is the baseline.
      const dsl = '''
        import restage.core;
        widget Inner = Text(text: "x");
        widget Paywall = Inner();
      ''';
      final surface = parseLibraryFile(dsl, sourceIdentifier: 'test');
      final result = deriveCapabilityManifest(surface, builtInCatalog);
      expect(result.issues, isEmpty);
      // `Inner` resolves library-locally (skipped); its body `Text` is at
      // baseline.
      expect(result.manifest!.builtInFloor, kBaselineCatalogVersion);
    });

    test('counts built-ins used inside a library-local widget body', () {
      // The local `Inner` reference is skipped, but its BODY is walked as its
      // own library widget — the `Hero()` inside lifts the floor.
      const dsl = '''
        import restage.core;
        widget Inner = Hero();
        widget Paywall = Column(children: [Text(text: "a"), Inner()]);
      ''';
      final surface = parseLibraryFile(dsl, sourceIdentifier: 'test');
      final result = deriveCapabilityManifest(surface, builtInCatalog);
      expect(result.manifest!.builtInFloor, 3);
    });

    test('the floor is over used WIDGETS, not properties', () {
      // Setting (or not setting) a property does not change the floor — there
      // is no property-level version axis; the floor tracks the widget's
      // `sinceVersion`. `Text` (baseline) used with a property still floors at
      // baseline, not higher.
      const withProp = '''
        import restage.core;
        widget Paywall = Text(text: "hi");
      ''';
      const withoutProp = '''
        import restage.core;
        widget Paywall = Banner();
      ''';
      final a = deriveCapabilityManifest(
        parseLibraryFile(withProp, sourceIdentifier: 'a'),
        builtInCatalog,
      );
      final b = deriveCapabilityManifest(
        parseLibraryFile(withoutProp, sourceIdentifier: 'b'),
        builtInCatalog,
      );
      expect(a.manifest!.builtInFloor, kBaselineCatalogVersion);
      expect(b.manifest!.builtInFloor, 2);
    });
  });

  // A mixed catalog: built-in `restage.core` widgets plus a custom library.
  const customLib = WidgetLibrary.custom('acme.widgets');
  Catalog mixedCatalog({int? customCapabilityVersion}) => Catalog(
        schemaVersion: kSupportedSchemaVersion,
        generatedAt: '1970-01-01T00:00:00Z',
        libraries: {
          WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
          customLib: LibraryInfo(
            version: '1.0.0',
            capabilityVersion: customCapabilityVersion,
          ),
        },
        widgets: [
          entry(
            name: 'Text',
            properties: [prop('text', PropertyType.string, required: true)],
          ),
          entry(name: 'Banner', properties: const [], sinceVersion: 2),
          entry(
            name: 'AcmeButton',
            properties: const [],
            library: customLib,
          ),
        ],
      );

  group('deriveCapabilityManifest — requiredLibraries (custom)', () {
    test('a referenced custom library contributes its capabilityVersion', () {
      const dsl = '''
        import restage.core;
        widget Paywall = AcmeButton();
      ''';
      final surface = parseLibraryFile(dsl, sourceIdentifier: 'test');
      final result = deriveCapabilityManifest(
        surface,
        mixedCatalog(customCapabilityVersion: 5),
      );
      expect(result.issues, isEmpty);
      expect(result.manifest, isNotNull);
      // No built-ins referenced → floor at baseline.
      expect(result.manifest!.builtInFloor, kBaselineCatalogVersion);
      expect(result.manifest!.requiredLibraries, [
        const LibraryRequirement(namespace: 'acme.widgets', minVersion: 5),
      ]);
    });

    test('a mixed surface carries BOTH the built-in floor and the library', () {
      const dsl = '''
        import restage.core;
        widget Paywall = Column(children: [Banner(), AcmeButton()]);
      ''';
      final surface = parseLibraryFile(dsl, sourceIdentifier: 'test');
      final result = deriveCapabilityManifest(
        surface,
        mixedCatalog(customCapabilityVersion: 4),
      );
      expect(result.issues, isEmpty);
      // Column + Banner are built-in (Banner@2); AcmeButton is custom@4.
      expect(result.manifest!.builtInFloor, 2);
      expect(result.manifest!.requiredLibraries, [
        const LibraryRequirement(namespace: 'acme.widgets', minVersion: 4),
      ]);
    });

    test(
        'fail-when-referenced: a referenced custom library with no '
        'capabilityVersion fails the build', () {
      const dsl = '''
        import restage.core;
        widget Paywall = AcmeButton();
      ''';
      final surface = parseLibraryFile(dsl, sourceIdentifier: 'test');
      final result = deriveCapabilityManifest(
        surface,
        mixedCatalog(),
      );
      expect(result.manifest, isNull);
      expect(
        result.issues.map((i) => i.code),
        contains(IssueCode.customLibraryMissingCapabilityVersion),
      );
      // The diagnostic names the offending library and the remediation.
      final issue = result.issues.firstWhere(
        (i) => i.code == IssueCode.customLibraryMissingCapabilityVersion,
      );
      expect(issue.message, contains('acme.widgets'));
      expect(issue.message, contains('capabilityVersion'));
    });

    test(
        'an UNREFERENCED custom library that omits its version does not '
        'fail the build', () {
      // The catalog carries `acme.widgets` with no capabilityVersion, but the
      // surface references only built-ins — fail-when-REFERENCED, so this is
      // clean.
      const dsl = '''
        import restage.core;
        widget Paywall = Banner();
      ''';
      final surface = parseLibraryFile(dsl, sourceIdentifier: 'test');
      final result = deriveCapabilityManifest(surface, mixedCatalog());
      expect(result.issues, isEmpty);
      expect(result.manifest!.builtInFloor, 2);
      expect(result.manifest!.requiredLibraries, isEmpty);
    });

    // Two custom libraries, referenced in a deterministic REVERSE namespace
    // order (zeta before alpha) inside a single children list — so the test
    // controls reference order itself rather than relying on widget-definition
    // ordering. Locks that the derivation canonicalizes by namespace.
    const zeta = WidgetLibrary.custom('zeta.widgets');
    const alpha = WidgetLibrary.custom('alpha.widgets');
    Catalog twoCustomCatalog({int? zetaVersion, int? alphaVersion}) => Catalog(
          schemaVersion: kSupportedSchemaVersion,
          generatedAt: '1970-01-01T00:00:00Z',
          libraries: {
            WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
            zeta: LibraryInfo(version: '1.0.0', capabilityVersion: zetaVersion),
            alpha:
                LibraryInfo(version: '1.0.0', capabilityVersion: alphaVersion),
          },
          widgets: [
            entry(
              name: 'Column',
              childrenSlot: ChildrenSlot.list,
              properties: [prop('children', PropertyType.widgetList)],
            ),
            entry(name: 'ZetaCard', properties: const [], library: zeta),
            entry(name: 'AlphaCard', properties: const [], library: alpha),
          ],
        );
    const reverseOrderDsl = '''
      import restage.core;
      widget Paywall = Column(children: [ZetaCard(), AlphaCard()]);
    ''';

    test(
        'requiredLibraries is canonical (sorted by namespace) regardless of '
        'reference order', () {
      final surface = parseLibraryFile(reverseOrderDsl, sourceIdentifier: 't');
      final result = deriveCapabilityManifest(
        surface,
        twoCustomCatalog(zetaVersion: 7, alphaVersion: 2),
      );
      expect(result.issues, isEmpty);
      expect(result.manifest!.requiredLibraries, [
        const LibraryRequirement(namespace: 'alpha.widgets', minVersion: 2),
        const LibraryRequirement(namespace: 'zeta.widgets', minVersion: 7),
      ]);
    });

    test('fail-when-referenced diagnostics are deterministic (namespace order)',
        () {
      // Both referenced custom libs omit capabilityVersion; referenced
      // zeta-before-alpha, the issues still come out namespace-sorted — the
      // diagnostic order does not depend on authoring order.
      final surface = parseLibraryFile(reverseOrderDsl, sourceIdentifier: 't');
      final result = deriveCapabilityManifest(surface, twoCustomCatalog());
      expect(result.manifest, isNull);
      expect(
        result.issues.map((i) => i.location).toList(),
        ['alpha.widgets', 'zeta.widgets'],
      );
    });
  });

  group('deriveCapabilityManifest — name shadow (ambiguity fails closed)', () {
    const customLib = WidgetLibrary.custom('acme.widgets');
    const customInfo = LibraryInfo(version: '1.0.0', capabilityVersion: 3);
    // `Banner` is registered in BOTH the built-in core library AND a custom
    // library — a shadow. A surface that references the bare name `Banner`
    // cannot be stamped: the runtime resolves by import order, the derivation
    // by catalog priority, so a wrong-library stamp could fail open.
    Catalog shadowCatalog() => Catalog(
          schemaVersion: kSupportedSchemaVersion,
          generatedAt: '1970-01-01T00:00:00Z',
          libraries: {
            WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
            customLib: customInfo,
          },
          widgets: [
            entry(name: 'Banner', properties: const [], sinceVersion: 2),
            entry(name: 'Banner', properties: const [], library: customLib),
          ],
        );

    test('a custom library shadowing a built-in name fails closed', () {
      const dsl = '''
        import restage.core;
        widget Paywall = Banner();
      ''';
      final surface = parseLibraryFile(dsl, sourceIdentifier: 'test');
      final result = deriveCapabilityManifest(surface, shadowCatalog());
      expect(result.manifest, isNull);
      expect(
        result.issues.map((i) => i.code),
        contains(IssueCode.ambiguousWidgetName),
      );
      final issue = result.issues.firstWhere(
        (i) => i.code == IssueCode.ambiguousWidgetName,
      );
      // Names the offending widget and both libraries it spans.
      expect(issue.message, contains('Banner'));
      expect(issue.message, contains('acme.widgets'));
      expect(issue.location, 'Banner');
    });

    test('a shadow reached only through a nested child still fails closed', () {
      // The ambiguity must be detected wherever the reference appears, not just
      // at the root.
      const dsl = '''
        import restage.core;
        widget Paywall = Banner();
      ''';
      // Reuse shadowCatalog but reference through a column child to prove the
      // walk reaches nested references.
      final nestedCatalog = Catalog(
        schemaVersion: kSupportedSchemaVersion,
        generatedAt: '1970-01-01T00:00:00Z',
        libraries: {
          WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
          customLib: const LibraryInfo(version: '1.0.0', capabilityVersion: 3),
        },
        widgets: [
          entry(
            name: 'Column',
            childrenSlot: ChildrenSlot.list,
            properties: [prop('children', PropertyType.widgetList)],
          ),
          entry(name: 'Banner', properties: const [], sinceVersion: 2),
          entry(name: 'Banner', properties: const [], library: customLib),
        ],
      );
      const nestedDsl = '''
        import restage.core;
        widget Paywall = Column(children: [Banner()]);
      ''';
      // The simple-root case stays covered by the first test.
      expect(
        deriveCapabilityManifest(
          parseLibraryFile(dsl, sourceIdentifier: 'a'),
          shadowCatalog(),
        ).manifest,
        isNull,
      );
      final result = deriveCapabilityManifest(
        parseLibraryFile(nestedDsl, sourceIdentifier: 'b'),
        nestedCatalog,
      );
      expect(result.manifest, isNull);
      expect(
        result.issues.map((i) => i.code),
        contains(IssueCode.ambiguousWidgetName),
      );
    });

    test('two libraries with DISTINCT names do not trip the ambiguity guard',
        () {
      // A custom library whose widget name is unique resolves cleanly — the
      // guard is for cross-library NAME collisions only, not for the mere
      // presence of a custom library.
      const dsl = '''
        import restage.core;
        widget Paywall = AcmeButton();
      ''';
      final result = deriveCapabilityManifest(
        parseLibraryFile(dsl, sourceIdentifier: 'test'),
        mixedCatalog(customCapabilityVersion: 5),
      );
      expect(result.issues, isEmpty);
      expect(result.manifest, isNotNull);
    });
  });

  group('deriveCapabilityManifest — cumulative render-support', () {
    test(
        'a DEPRECATED built-in still contributes to the floor '
        '(deprecated != removed)', () {
      // A catalog version is a cumulative render-support set — a
      // deprecated widget is still supported, so the derivation must not skip
      // it. A deprecated widget at sinceVersion 2, referenced, still floors at
      // 2.
      final catalog = catalogWith([
        entry(
          name: 'OldHero',
          properties: const [],
          sinceVersion: 2,
          deprecatedSince: '3',
        ),
      ]);
      const dsl = '''
        import restage.core;
        widget Paywall = OldHero();
      ''';
      final surface = parseLibraryFile(dsl, sourceIdentifier: 'test');
      final result = deriveCapabilityManifest(surface, catalog);
      expect(result.issues, isEmpty);
      expect(result.manifest!.builtInFloor, 2);
    });
  });

  group('deriveCapabilityManifest — referencedWidgets', () {
    List<String> qualifiedNames(CapabilityDerivationResult result) => [
          for (final entry in result.referencedWidgets)
            WidgetVocabulary.qualifiedName(entry.library.namespace, entry.name),
        ];

    // The same three widgets — two built-ins and a custom — referenced in two
    // different orders, so the canonical order is testable against both.
    const customFirstDsl = '''
      import restage.core;
      widget A = AcmeButton();
      widget B = Banner();
      widget Paywall = Text(text: "hi");
    ''';
    const customLastDsl = '''
      import restage.core;
      widget A = Text(text: "hi");
      widget B = Banner();
      widget Paywall = AcmeButton();
    ''';

    test('names every catalog widget the surface references', () {
      final result = deriveCapabilityManifest(
        parseLibraryFile(customFirstDsl, sourceIdentifier: 'test'),
        mixedCatalog(customCapabilityVersion: 5),
      );
      expect(result.issues, isEmpty);
      expect(qualifiedNames(result), [
        'acme.widgets:AcmeButton',
        'restage.core:Banner',
        'restage.core:Text',
      ]);
    });

    test('the order is by qualified name, not by reference order', () {
      final customFirst = deriveCapabilityManifest(
        parseLibraryFile(customFirstDsl, sourceIdentifier: 'a'),
        mixedCatalog(customCapabilityVersion: 5),
      );
      final customLast = deriveCapabilityManifest(
        parseLibraryFile(customLastDsl, sourceIdentifier: 'b'),
        mixedCatalog(customCapabilityVersion: 5),
      );
      expect(qualifiedNames(customLast), qualifiedNames(customFirst));
    });

    test('a widget referenced more than once appears once', () {
      const dsl = '''
        import restage.core;
        widget A = Banner();
        widget B = Banner();
        widget Paywall = Banner();
      ''';
      final result = deriveCapabilityManifest(
        parseLibraryFile(dsl, sourceIdentifier: 'test'),
        mixedCatalog(customCapabilityVersion: 5),
      );
      expect(qualifiedNames(result), ['restage.core:Banner']);
    });

    test('a failed derivation names nothing', () {
      // The custom library declares no capability version, so the result is
      // not usable and carries no referenced widgets to fold.
      const dsl = '''
        import restage.core;
        widget Paywall = AcmeButton();
      ''';
      final result = deriveCapabilityManifest(
        parseLibraryFile(dsl, sourceIdentifier: 'test'),
        mixedCatalog(),
      );
      expect(result.manifest, isNull);
      expect(result.referencedWidgets, isEmpty);
    });
  });
}
