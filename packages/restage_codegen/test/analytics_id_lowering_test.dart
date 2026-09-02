import 'dart:convert';

import 'package:restage_codegen/src/analytics_id_lowering.dart';
import 'package:restage_codegen/src/capability_derivation.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_shared/restage_shared.dart' show CapabilitySidecar;
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final catalog = Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: '1970-01-01T00:00:00Z',
    libraries: {
      WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
      const WidgetLibrary.custom('acme.widgets'):
          const LibraryInfo(version: '0.1.0', capabilityVersion: 1),
    },
    widgets: [
      entry(
        name: 'Card',
        properties: [
          prop('title', PropertyType.string),
          analyticsIdProperty(),
        ],
      ),
      entry(
        name: 'Column',
        childrenSlot: ChildrenSlot.list,
        properties: [
          prop('children', PropertyType.widgetList),
          analyticsIdProperty(),
        ],
      ),
      entry(
        name: 'Builder',
        properties: [analyticsIdProperty()],
      ),
      entry(
        name: 'OpaqueBadge',
        library: const WidgetLibrary.custom('acme.widgets'),
        properties: [
          prop('title', PropertyType.string),
          analyticsIdProperty(),
        ],
      ),
      entry(
        name: 'InlineBadge',
        library: const WidgetLibrary.custom('acme.widgets'),
        properties: [
          prop('title', PropertyType.string),
          analyticsIdProperty(),
        ],
      ),
    ],
  );

  AnalyticsIdLoweringResult lower(
    String source, {
    bool authoritative = false,
    String rootWidgetName = 'Root',
    Set<String> generatedCatalogLocals = const {'InlineBadge'},
  }) {
    const sourceIdentifier = 'analytics-id-test';
    final library = fmt.parseLibraryFile(
      source,
      sourceIdentifier: sourceIdentifier,
    );
    final occurrenceSet = authoritative
        ? _resolveFixtureOccurrences(
            library,
            catalog,
            rootWidgetName: rootWidgetName,
            generatedCatalogLocals: generatedCatalogLocals,
          )
        : null;
    return lowerAnalyticsIds(
      text: source,
      library: library,
      sourceIdentifier: sourceIdentifier,
      location: 'test.rwftxt',
      occurrenceSet: occurrenceSet,
    );
  }

  String sidecar(AnalyticsIdLoweringResult result) {
    final blob = fmt.encodeLibraryBlob(result.library);
    final derivation = deriveCapabilityManifest(result.library, catalog);
    expect(derivation.issues, isEmpty);
    return jsonEncode(
      CapabilitySidecar(
        blobSha256: CapabilitySidecar.hashBlob(blob),
        manifest: derivation.manifest!,
      ).toJson(),
    );
  }

  group('lowerAnalyticsIds', () {
    test('rejects labeled generic built-in and opaque customer RFW calls', () {
      const absent = '''
import restage.core;
import acme.widgets;
widget Root = Column(children: [
  Card(title: "Built in"),
  OpaqueBadge(title: "Opaque"),
]);
''';
      const added = '''
import restage.core;
import acme.widgets;
widget Root = Column(children: [
  Card(title: "Built in", analyticsId: "checkout.primary"),
  OpaqueBadge(title: "Opaque", analyticsId: "checkout.primary"),
]);
''';
      const renamed = '''
import restage.core;
import acme.widgets;
widget Root = Column(children: [
  Card(title: "Built in", analyticsId: "checkout.confirm"),
  OpaqueBadge(title: "Opaque", analyticsId: "checkout.confirm"),
]);
''';

      final withoutLabel = lower(absent);
      final withLabel = lower(added);
      final withRenamedLabel = lower(renamed);

      expect(withoutLabel.issues, isEmpty);
      expect(withLabel.issues, isNotEmpty);
      expect(withRenamedLabel.issues, isNotEmpty);
      expect(withLabel.text, added);
      expect(withRenamedLabel.text, renamed);
      expect(withLabel.declarations, isEmpty);
      expect(withRenamedLabel.declarations, isEmpty);
      expect(
        fmt.encodeLibraryBlob(withLabel.library),
        fmt.encodeLibraryBlob(fmt.parseLibraryFile(withLabel.text)),
      );
      expect(
        fmt.encodeLibraryBlob(withRenamedLabel.library),
        fmt.encodeLibraryBlob(fmt.parseLibraryFile(withRenamedLabel.text)),
      );
    });

    test('binds built-in, opaque, and inlined customer RFW occurrences', () {
      const absent = '''
import restage.core;
import acme.widgets;
widget InlineBadge = Card(title: args.title);
widget Root = Column(children: [
  Card(title: "Built in"),
  OpaqueBadge(title: "Opaque"),
  InlineBadge(title: "Inline"),
]);
''';
      const added = '''
import restage.core;
import acme.widgets;
widget InlineBadge = Card(title: args.title);
widget Root = Column(children: [
  Card(title: "Built in", analyticsId: "checkout.primary"),
  OpaqueBadge(title: "Opaque", analyticsId: "checkout.primary"),
  InlineBadge(title: "Inline", analyticsId: "checkout.primary"),
]);
''';
      const renamed = '''
import restage.core;
import acme.widgets;
widget InlineBadge = Card(title: args.title);
widget Root = Column(children: [
  Card(title: "Built in", analyticsId: "checkout.confirm"),
  OpaqueBadge(title: "Opaque", analyticsId: "checkout.confirm"),
  InlineBadge(title: "Inline", analyticsId: "checkout.confirm"),
]);
''';
      final withoutLabel = lower(absent, authoritative: true);
      final withLabel = lower(added, authoritative: true);
      final withRenamedLabel = lower(renamed, authoritative: true);

      expect(withoutLabel.issues, isEmpty);
      expect(withLabel.issues, isEmpty);
      expect(withRenamedLabel.issues, isEmpty);
      expect(withLabel.text, absent);
      expect(withRenamedLabel.text, absent);
      expect(withLabel.text, isNot(contains('__restage')));
      expect(withLabel.text, isNot(contains('analyticsId')));
      expect(
        fmt.encodeLibraryBlob(withLabel.library),
        fmt.encodeLibraryBlob(withoutLabel.library),
      );
      expect(
        fmt.encodeLibraryBlob(withRenamedLabel.library),
        fmt.encodeLibraryBlob(withoutLabel.library),
      );
      expect(sidecar(withLabel), sidecar(withoutLabel));
      expect(sidecar(withRenamedLabel), sidecar(withoutLabel));
      expect(withLabel.declarations, hasLength(3));
      expect(
        withLabel.declarations
            .map((declaration) => declaration.presentationHandle),
        hasLength(3),
      );
      expect(
        withLabel.declarations.map((declaration) => declaration.analyticsId),
        everyElement('checkout.primary'),
      );
      expect(
        withRenamedLabel.declarations
            .map((declaration) => declaration.analyticsId),
        everyElement('checkout.confirm'),
      );
      expect(
        withLabel.declarations
            .map((declaration) => declaration.presentationHandle)
            .toSet(),
        hasLength(3),
      );
    });

    test('removes labels recursively and keeps exact-call joins', () {
      const source = '''
import restage.core;
widget Root = Column(children: [
  Card(analyticsId: "first"),
  ...for row in data.rows: Card(analyticsId: "second"),
  switch data.enabled {
    true: Card(analyticsId: "third"),
    default: Card(analyticsId: "fourth"),
  },
  Builder(builder: (scope) => Card(analyticsId: "fifth")),
]);
''';
      final result = lower(source, authoritative: true);

      expect(result.issues, isEmpty);
      expect(result.declarations.map((item) => item.analyticsId), [
        'first',
        'second',
        'third',
        'fourth',
        'fifth',
      ]);
      expect(result.text, isNot(contains('analyticsId')));
      expect(() => fmt.parseLibraryFile(result.text), returnsNormally);
      final root = result.library.widgets.single.root as fmt.ConstructorCall;
      final loop =
          (root.arguments['children']! as List<Object?>)[1]! as fmt.Loop;
      final loopCard = loop.output as fmt.ConstructorCall;
      expect(loopCard.arguments, isNot(contains('analyticsId')));
      expect(
        result.declarations
            .map((declaration) => declaration.presentationHandle)
            .toSet(),
        hasLength(5),
      );
    });

    test('source edits skip parentheses inside comments', () {
      const source = '''
import restage.core;
widget Root = Card /* (
  analyticsId: "comment"
) */ (
  title: "x",
  analyticsId: "checkout.primary",
);
''';
      const sourceIdentifier = 'comment-aware-lowering';
      final library = fmt.parseLibraryFile(
        source,
        sourceIdentifier: sourceIdentifier,
      );
      final occurrenceSet = _resolveFixtureOccurrences(
        library,
        catalog,
        rootWidgetName: 'Root',
      );
      final result = lowerAnalyticsIds(
        text: source,
        library: library,
        sourceIdentifier: sourceIdentifier,
        location: 'test.rwftxt',
        occurrenceSet: occurrenceSet,
      );

      expect(result.issues, isEmpty);
      expect(result.text, isNot(contains('analyticsId')));
      expect(result.text, isNot(contains('checkout.primary')));
      expect(
        fmt.encodeLibraryBlob(fmt.parseLibraryFile(result.text)),
        fmt.encodeLibraryBlob(result.library),
      );
    });

    test('unknown labeled calls fail without creating a mismatched pair', () {
      const source = '''
widget Root = Unknown(analyticsId: "checkout.primary");
''';
      final result = lower(source);

      expect(result.issues.map((issue) => issue.code), [
        IssueCode.invalidAnalyticsId,
      ]);
      expect(result.text, source);
      expect(
        fmt.encodeLibraryBlob(fmt.parseLibraryFile(result.text)),
        fmt.encodeLibraryBlob(result.library),
      );
    });

    test('preserves encodable string-keyed maps in the sanitized copy', () {
      const source = '''
widget Root = Unknown(
  payload: {
    "outer": {"inner": "value"},
  },
);
''';
      final result = lower(source);

      expect(result.issues, isEmpty);
      expect(
        fmt.encodeLibraryBlob(result.library),
        fmt.encodeLibraryBlob(fmt.parseLibraryFile(source)),
      );
    });

    test('same-name labels bind through exact parsed-call identity', () {
      const source = '''
import restage.core;
widget Root = Column(children: [
  Card(title: "First", analyticsId: "checkout.first"),
  Card(title: "Second", analyticsId: "checkout.second"),
]);
''';
      const sourceIdentifier = 'object-identity-lowering';
      final library = fmt.parseLibraryFile(
        source,
        sourceIdentifier: sourceIdentifier,
      );
      final cards = _callsNamed(library, 'Card');
      final occurrenceSet = _resolveFixtureOccurrences(
        library,
        catalog,
        rootWidgetName: 'Root',
      );
      final firstHandle = occurrenceSet.occurrenceForCall(cards.first)!.handle;
      final secondHandle = occurrenceSet.occurrenceForCall(cards.last)!.handle;
      expect(firstHandle, isNot(secondHandle));
      final result = lowerAnalyticsIds(
        text: source,
        library: library,
        sourceIdentifier: sourceIdentifier,
        location: 'test.rwftxt',
        occurrenceSet: occurrenceSet,
      );

      expect(result.issues, isEmpty);
      expect(
        result.declarations.map(
          (declaration) => (
            declaration.analyticsId,
            declaration.presentationHandle,
          ),
        ),
        [
          ('checkout.first', firstHandle),
          ('checkout.second', secondHandle),
        ],
      );
    });

    test('rejects malformed and dynamic values while still removing the key',
        () {
      for (final value in [
        '""',
        '"Upper"',
        '"has space"',
        '"café"',
        'args.label',
        'data.label',
        r'"label-${args.value}"',
      ]) {
        final result = lower(
          '''
import restage.core;
widget Root = Card(analyticsId: $value);
''',
          authoritative: true,
        );

        expect(
          result.issues.map((issue) => issue.code),
          contains(IssueCode.invalidAnalyticsId),
          reason: value,
        );
        expect(result.text, isNot(contains('analyticsId')), reason: value);
        expect(result.declarations, isEmpty, reason: value);
      }
    });

    test('binds an inlined local call only through exact-call discovery', () {
      const source = '''
import restage.core;
widget InlineBadge = Card(title: args.title);
widget Root = InlineBadge(title: "Inline", analyticsId: "checkout.inline");
''';

      final accepted = lower(
        source,
        authoritative: true,
      );
      final rejected = lower(source);

      expect(accepted.issues, isEmpty);
      expect(accepted.text, isNot(contains('analyticsId')));
      expect(accepted.declarations, hasLength(1));
      expect(rejected.issues.single.code, IssueCode.invalidAnalyticsId);
      expect(rejected.text, source);
      expect(rejected.declarations, isEmpty);
    });

    test('publication discovery can admit only the inlined outer call', () {
      const source = '''
import restage.core;
widget InlineBadge = Card(title: args.title);
widget Paywall = InlineBadge(
  title: "Inline",
  analyticsId: "checkout.inline",
);
''';
      const sourceIdentifier = 'outer-only-lowering';
      final library = fmt.parseLibraryFile(
        source,
        sourceIdentifier: sourceIdentifier,
      );
      final outer = _callsNamed(library, 'InlineBadge').single;
      final occurrenceSet = _resolveFixtureOccurrences(
        library,
        catalog,
        rootWidgetName: 'Paywall',
      );
      final result = lowerAnalyticsIds(
        text: source,
        library: library,
        sourceIdentifier: sourceIdentifier,
        location: 'test.rwftxt',
        occurrenceSet: occurrenceSet,
      );

      expect(result.issues, isEmpty);
      expect(result.declarations, hasLength(1));
      expect(
        result.declarations.single.presentationHandle,
        occurrenceSet.occurrenceForCall(outer)!.handle,
      );
      expect(result.text, isNot(contains('checkout.inline')));
    });

    test('allows unlabeled handles and a shared label across references', () {
      const source = '''
import restage.core;
widget Root = Column(children: [
  Card(),
  Card(analyticsId: "checkout.primary"),
  Card(analyticsId: "checkout.primary"),
]);
''';
      final result = lower(source, authoritative: true);

      expect(result.issues, isEmpty);
      expect(result.declarations, hasLength(2));
      expect(
        result.declarations
            .map((declaration) => declaration.presentationHandle)
            .toSet(),
        hasLength(2),
      );
    });

    test('requires authoritative provenance for a labeled catalog call', () {
      const source = '''
import restage.core;
widget Root = Column(children: [
  Card(analyticsId: "checkout.primary"),
]);
''';
      final missing = lower(source);
      final complete = lower(source, authoritative: true);

      expect(missing.issues, isNotEmpty);
      expect(missing.declarations, isEmpty);
      expect(complete.issues, isEmpty);
      expect(complete.declarations, hasLength(1));
    });

    test('rejects an occurrence set owned by a different parsed library', () {
      const source = '''
import restage.core;
widget Root = Card(analyticsId: "checkout.primary");
''';
      const sourceIdentifier = 'wrong-object-lowering';
      final issuedLibrary = fmt.parseLibraryFile(
        source,
        sourceIdentifier: sourceIdentifier,
      );
      final parsedAgain = fmt.parseLibraryFile(
        source,
        sourceIdentifier: sourceIdentifier,
      );
      final occurrenceSet = _resolveFixtureOccurrences(
        issuedLibrary,
        catalog,
        rootWidgetName: 'Root',
      );

      expect(
        () => lowerAnalyticsIds(
          text: source,
          library: parsedAgain,
          sourceIdentifier: sourceIdentifier,
          location: 'test.rwftxt',
          occurrenceSet: occurrenceSet,
        ),
        throwsArgumentError,
      );
    });
  });
}

fmt.ResolvedRfwCatalogOccurrenceSet _resolveFixtureOccurrences(
  fmt.RemoteWidgetLibrary library,
  Catalog catalog, {
  required String rootWidgetName,
  Set<String> generatedCatalogLocals = const {'InlineBadge'},
}) {
  final origins = <String, fmt.RfwCatalogConstructorProvenance>{
    for (final widget in catalog.widgets)
      widget.name: fmt.RfwCatalogConstructorProvenance(
        constructorName: widget.name,
        catalogLibraryNamespace: widget.library.namespace,
        catalogWidgetWireId: widget.wireId,
      ),
  };
  return fmt.ResolvedRfwCatalogOccurrenceSet.resolve(
    parsedLibrary: library,
    input: fmt.RfwCatalogOccurrenceResolutionInput(
      artifactProvenance: 'fixture.artifact',
      sourceLibraryIdentity: 'fixture.library',
      sourceDeclarationIdentity: 'fixture.library#Fixture',
      renderEntryNames: [rootWidgetName],
      catalogConstructors: origins.values,
      localSymbols: [
        for (final widget in library.widgets)
          fmt.RfwCatalogLocalSymbol(
            name: widget.name,
            generatedCatalogOrigin: generatedCatalogLocals.contains(widget.name)
                ? origins[widget.name]
                : null,
          ),
      ],
    ),
  );
}

List<fmt.ConstructorCall> _callsNamed(
  fmt.RemoteWidgetLibrary library,
  String name,
) {
  final result = <fmt.ConstructorCall>[];

  void visit(Object? value) {
    switch (value) {
      case final fmt.ConstructorCall call:
        if (call.name == name) result.add(call);
        call.arguments.values.forEach(visit);
      case final Map<Object?, Object?> map:
        map.values.forEach(visit);
      case final List<Object?> list:
        list.forEach(visit);
      default:
        return;
    }
  }

  for (final widget in library.widgets) {
    if (widget.initialState != null) visit(widget.initialState);
    visit(widget.root);
  }
  return result;
}
