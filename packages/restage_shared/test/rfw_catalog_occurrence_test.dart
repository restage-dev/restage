import 'package:restage_shared/rfw_formats.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart' as catalog;
import 'package:test/test.dart';

void main() {
  test('resolves root calls and reachable ordinary local bodies', () {
    final set = _resolve(_source());

    expect(
      set.occurrences.map((occurrence) => occurrence.constructorCall.name),
      unorderedEquals([
        'BuiltInCard',
        'BuiltInCard',
        'OpaqueBadge',
        'InlineBadge',
        'InlineBadge',
      ]),
    );
    expect(
      set.occurrences
          .where((occurrence) => occurrence.constructorCall.name == 'Card'),
      isEmpty,
    );
    expect(
      set.occurrences
          .where((occurrence) => occurrence.constructorCall.name == 'Generic'),
      isEmpty,
    );
    expect(
      set.localDeclarationAnchors.map((anchor) => anchor.localName),
      ['Card'],
    );
    final cardAnchor = set.localDeclarationAnchors.single;
    expect(
      set.occurrences
          .where(
            (occurrence) =>
                occurrence.descriptor.parentStructuralOccurrenceKey ==
                cardAnchor.structuralOccurrenceKey,
          )
          .map((occurrence) => occurrence.constructorCall.name),
      ['BuiltInCard'],
    );

    final root = set.occurrences.firstWhere(
      (occurrence) =>
          occurrence.constructorCall.name == 'BuiltInCard' &&
          occurrence.descriptor.parentStructuralOccurrenceKey == null,
    );
    expect(
      set.occurrences
          .where((occurrence) => occurrence != root)
          .map(
            (occurrence) => occurrence.descriptor.parentStructuralOccurrenceKey,
          )
          .where((parent) => parent != cardAnchor.structuralOccurrenceKey),
      everyElement(root.descriptor.structuralOccurrenceKey),
    );
    final repeated = set.occurrences
        .where((occurrence) => occurrence.constructorCall.name == 'InlineBadge')
        .map((occurrence) => occurrence.handle)
        .toSet();
    expect(repeated, hasLength(2));
  });

  test('rebinds frozen handles without resolving catalog eligibility again',
      () {
    final set = _resolve(_source());
    final finalLibrary = parseLibraryFile(
      _source(rootTitle: 'changed'),
      sourceIdentifier: 'final-fixture',
    );
    final rebound = set.rebindFinalLibrary(finalLibrary);

    expect(rebound.bindings, hasLength(set.occurrences.length));
    for (final occurrence in set.occurrences) {
      final binding = rebound.requireBindingForHandle(occurrence.handle);
      expect(binding.descriptor, same(occurrence.descriptor));
      expect(rebound.bindingForCall(binding.constructorCall), same(binding));
    }

    expect(
      () => set.rebindFinalLibrary(
        parseLibraryFile(
          _source(includeOpaque: false),
          sourceIdentifier: 'missing-fixture',
        ),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => set.rebindFinalLibrary(
        parseLibraryFile(
          _source(extraOpaque: true),
          sourceIdentifier: 'extra-fixture',
        ),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => set.rebindFinalLibrary(
        parseLibraryFile(
          _source(remapInline: true),
          sourceIdentifier: 'remapped-fixture',
        ),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects a changed import closure with unchanged call topology', () {
    final origins = _origins();
    final frozen = ResolvedRfwCatalogOccurrenceSet.resolve(
      parsedLibrary: parseLibraryFile(
        '''
import restage.core;
import example.widgets;
widget Paywall = BuiltInCard();
''',
        sourceIdentifier: 'frozen-import-fixture',
      ),
      input: RfwCatalogOccurrenceResolutionInput(
        artifactProvenance: 'fixture.imports',
        sourceLibraryIdentity: 'package:fixture/presentation.dart',
        sourceDeclarationIdentity: 'package:fixture/presentation.dart#imports',
        renderEntryNames: const ['Paywall'],
        catalogConstructors: [origins.builtIn],
        localSymbols: [RfwCatalogLocalSymbol(name: 'Paywall')],
      ),
    );

    expect(
      frozen
          .rebindFinalLibrary(
            parseLibraryFile(
              '''
import example.widgets;
import restage.core;
widget Paywall = BuiltInCard();
''',
              sourceIdentifier: 'reordered-import-fixture',
            ),
          )
          .bindings,
      hasLength(1),
    );
    expect(
      () => frozen.rebindFinalLibrary(
        parseLibraryFile(
          '''
import example.widgets;
import restage.material;
widget Paywall = BuiltInCard();
''',
          sourceIdentifier: 'changed-import-fixture',
        ),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('visits each reachable ordinary local body once', () {
    final oneCall = _resolveHelper(_helperSource(callCount: 1));
    final twoCalls = _resolveHelper(_helperSource(callCount: 2));

    expect(oneCall.occurrences, hasLength(1));
    expect(twoCalls.occurrences, hasLength(1));
    expect(
      twoCalls.occurrences.single.constructorCall.name,
      'BuiltInCard',
    );
    expect(
      twoCalls.occurrences.single.handle,
      oneCall.occurrences.single.handle,
    );
    expect(
      twoCalls.occurrences.single.descriptor.parentStructuralOccurrenceKey,
      oneCall.occurrences.single.descriptor.parentStructuralOccurrenceKey,
    );
    expect(
      twoCalls.localDeclarationAnchors.single.localName,
      'Helper',
    );
  });

  test('terminates recursive ordinary local traversal', () {
    final set = ResolvedRfwCatalogOccurrenceSet.resolve(
      parsedLibrary: parseLibraryFile(
        '''
widget A = BuiltInCard(child: B());
widget B = A();
widget Paywall = Generic(children: [A(), A()]);
''',
        sourceIdentifier: 'recursive-fixture',
      ),
      input: _inputFor(
        localNames: const ['A', 'B', 'Paywall'],
      ),
    );

    expect(set.occurrences, hasLength(1));
    expect(set.occurrences.single.constructorCall.name, 'BuiltInCard');
    expect(
      set.localDeclarationAnchors.map((anchor) => anchor.localName),
      ['A'],
    );
  });

  test('rejects a generated catalog local as an explicit render root', () {
    final origins = _origins();
    var builtInCardWasAdmitted = false;

    expect(
      () {
        final input = RfwCatalogOccurrenceResolutionInput(
          artifactProvenance: 'fixture.generated-root',
          sourceLibraryIdentity: 'package:fixture/presentation.dart',
          sourceDeclarationIdentity: 'package:fixture/presentation.dart#root',
          renderEntryNames: const ['InlineBadge'],
          catalogConstructors: [origins.builtIn, origins.inline],
          localSymbols: [
            RfwCatalogLocalSymbol(
              name: 'InlineBadge',
              generatedCatalogOrigin: origins.inline,
            ),
          ],
        );
        final resolved = ResolvedRfwCatalogOccurrenceSet.resolve(
          parsedLibrary: parseLibraryFile(
            'widget InlineBadge = BuiltInCard();',
            sourceIdentifier: 'generated-root-fixture',
          ),
          input: input,
        );
        builtInCardWasAdmitted = resolved.occurrences.any(
          (occurrence) => occurrence.constructorCall.name == 'BuiltInCard',
        );
      },
      throwsArgumentError,
    );
    expect(builtInCardWasAdmitted, isFalse);
  });

  test('rejects duplicate and oversized resolver inputs', () {
    final origin = _origins().builtIn;
    final root = RfwCatalogLocalSymbol(name: 'Paywall');

    expect(
      () => RfwCatalogOccurrenceResolutionInput(
        artifactProvenance: 'fixture',
        sourceLibraryIdentity: 'library',
        sourceDeclarationIdentity: 'declaration',
        renderEntryNames: const ['Paywall'],
        catalogConstructors: [origin, origin],
        localSymbols: [root],
      ),
      throwsArgumentError,
    );
    expect(
      () => RfwCatalogOccurrenceResolutionInput(
        artifactProvenance: 'fixture',
        sourceLibraryIdentity: 'library',
        sourceDeclarationIdentity: 'declaration',
        renderEntryNames: const ['Paywall'],
        catalogConstructors: [origin],
        localSymbols: [root, root],
      ),
      throwsArgumentError,
    );
    expect(
      () => RfwCatalogOccurrenceResolutionInput(
        artifactProvenance: 'fixture',
        sourceLibraryIdentity: 'library',
        sourceDeclarationIdentity: 'declaration',
        renderEntryNames: List.generate(1025, (index) => 'root$index'),
        catalogConstructors: [origin],
        localSymbols: [root],
      ),
      throwsArgumentError,
    );
  });

  test('rejects more resolved occurrences than route capacity', () {
    final calls = List.generate(1025, (_) => 'BuiltInCard()').join(', ');
    expect(
      () => ResolvedRfwCatalogOccurrenceSet.resolve(
        parsedLibrary: parseLibraryFile(
          'widget Paywall = Generic(children: [$calls]);',
          sourceIdentifier: 'oversized-fixture',
        ),
        input: _inputFor(localNames: const ['Paywall']),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('enforces lexical evidence bounds and catalog provenance semantics', () {
    final identifierAtLimit = List.filled(128, 'A').join();
    final identifierPastLimit = List.filled(129, 'A').join();
    final namespaceAtLimit = List.filled(128, 'a').join();
    final namespacePastLimit = List.filled(129, 'a').join();

    expect(
      () => RfwCatalogConstructorProvenance(
        constructorName: identifierAtLimit,
        catalogLibraryNamespace: namespaceAtLimit,
        catalogWidgetWireId: catalog.WireId('w0001'),
      ),
      returnsNormally,
    );
    expect(
      () => RfwCatalogLocalSymbol(name: identifierAtLimit),
      returnsNormally,
    );
    expect(
      () => _resolutionInput(renderEntryName: identifierAtLimit),
      returnsNormally,
    );
    expect(
      () => RfwCatalogConstructorProvenance(
        constructorName: identifierPastLimit,
        catalogLibraryNamespace: namespaceAtLimit,
        catalogWidgetWireId: catalog.WireId('w0001'),
      ),
      throwsArgumentError,
    );
    expect(
      () => RfwCatalogLocalSymbol(name: identifierPastLimit),
      throwsArgumentError,
    );
    expect(
      () => _resolutionInput(renderEntryName: identifierPastLimit),
      throwsArgumentError,
    );
    expect(
      () => RfwCatalogConstructorProvenance(
        constructorName: 'BuiltInCard',
        catalogLibraryNamespace: namespacePastLimit,
        catalogWidgetWireId: catalog.WireId('w0001'),
      ),
      throwsArgumentError,
    );
    expect(
      () => RfwCatalogConstructorProvenance(
        constructorName: 'BuiltInCard',
        catalogLibraryNamespace: 'Example.invalid',
        catalogWidgetWireId: catalog.WireId('w0001'),
      ),
      throwsArgumentError,
    );
    expect(
      () => RfwCatalogConstructorProvenance(
        constructorName: 'BuiltInCard',
        catalogLibraryNamespace: 'example.presentation',
        catalogWidgetWireId: catalog.WireId('p0001'),
      ),
      throwsArgumentError,
    );
  });

  test('enforces scalar and byte bounds on resolver provenance', () {
    final asciiAtLimit = List.filled(1024, 'a').join();
    final asciiPastLimit = List.filled(1025, 'a').join();
    final multibyteAtLimit = List.filled(512, '\u00e9').join();
    final multibytePastLimit = List.filled(513, '\u00e9').join();

    expect(
      () => _resolutionInput(
        artifactProvenance: asciiAtLimit,
        sourceLibraryIdentity: multibyteAtLimit,
        sourceDeclarationIdentity: asciiAtLimit,
      ),
      returnsNormally,
    );
    for (final provenance in [asciiPastLimit, multibytePastLimit, '\ud800']) {
      expect(
        () => _resolutionInput(artifactProvenance: provenance),
        throwsArgumentError,
      );
      expect(
        () => _resolutionInput(sourceLibraryIdentity: provenance),
        throwsArgumentError,
      );
      expect(
        () => _resolutionInput(sourceDeclarationIdentity: provenance),
        throwsArgumentError,
      );
    }
    for (final control in ['\u0000', '\n', '\u001f', '\u007f', '\u009f']) {
      expect(
        () => _resolutionInput(artifactProvenance: 'a${control}b'),
        throwsArgumentError,
      );
    }
  });
}

RfwCatalogOccurrenceResolutionInput _resolutionInput({
  String artifactProvenance = 'fixture.artifact',
  String sourceLibraryIdentity = 'fixture.library',
  String sourceDeclarationIdentity = 'fixture.declaration',
  String renderEntryName = 'Paywall',
}) =>
    RfwCatalogOccurrenceResolutionInput(
      artifactProvenance: artifactProvenance,
      sourceLibraryIdentity: sourceLibraryIdentity,
      sourceDeclarationIdentity: sourceDeclarationIdentity,
      renderEntryNames: [renderEntryName],
      catalogConstructors: const [],
      localSymbols: [RfwCatalogLocalSymbol(name: renderEntryName)],
    );

ResolvedRfwCatalogOccurrenceSet _resolve(String source) =>
    ResolvedRfwCatalogOccurrenceSet.resolve(
      parsedLibrary: parseLibraryFile(source, sourceIdentifier: 'fixture'),
      input: _inputFor(
        localNames: const ['InlineBadge', 'Card', 'Dead', 'Paywall'],
      ),
    );

ResolvedRfwCatalogOccurrenceSet _resolveHelper(String source) =>
    ResolvedRfwCatalogOccurrenceSet.resolve(
      parsedLibrary: parseLibraryFile(source, sourceIdentifier: 'helper'),
      input: _inputFor(localNames: const ['Helper', 'Paywall']),
    );

RfwCatalogOccurrenceResolutionInput _inputFor({
  required Iterable<String> localNames,
}) {
  final origins = _origins();
  return RfwCatalogOccurrenceResolutionInput(
    artifactProvenance: 'fixture.paywall.root',
    sourceLibraryIdentity: 'package:fixture/presentation.dart',
    sourceDeclarationIdentity: 'package:fixture/presentation.dart#paywall',
    renderEntryNames: const ['Paywall'],
    catalogConstructors: [
      origins.builtIn,
      origins.opaque,
      origins.inline,
      origins.card,
    ],
    localSymbols: [
      for (final name in localNames)
        RfwCatalogLocalSymbol(
          name: name,
          generatedCatalogOrigin: name == 'InlineBadge' ? origins.inline : null,
        ),
    ],
  );
}

({
  RfwCatalogConstructorProvenance builtIn,
  RfwCatalogConstructorProvenance opaque,
  RfwCatalogConstructorProvenance inline,
  RfwCatalogConstructorProvenance card,
}) _origins() {
  const custom = catalog.WidgetLibrary.custom('example.presentation');
  final builtIn = RfwCatalogConstructorProvenance(
    constructorName: 'BuiltInCard',
    catalogLibraryNamespace: catalog.WidgetLibrary.core.namespace,
    catalogWidgetWireId: catalog.WireId('w0001'),
  );
  final opaque = RfwCatalogConstructorProvenance(
    constructorName: 'OpaqueBadge',
    catalogLibraryNamespace: custom.namespace,
    catalogWidgetWireId: catalog.WireId('w0001'),
  );
  final inline = RfwCatalogConstructorProvenance(
    constructorName: 'InlineBadge',
    catalogLibraryNamespace: custom.namespace,
    catalogWidgetWireId: catalog.WireId('w0002'),
  );
  final card = RfwCatalogConstructorProvenance(
    constructorName: 'Card',
    catalogLibraryNamespace: catalog.WidgetLibrary.core.namespace,
    catalogWidgetWireId: catalog.WireId('w0002'),
  );
  return (
    builtIn: builtIn,
    opaque: opaque,
    inline: inline,
    card: card,
  );
}

String _helperSource({required int callCount}) => '''
widget Helper = BuiltInCard(title: "shared");
widget Paywall = Generic(children: [
  ${List.filled(callCount, 'Helper()').join(', ')},
]);
''';

String _source({
  String rootTitle = 'first',
  bool includeOpaque = true,
  bool extraOpaque = false,
  bool remapInline = false,
}) {
  final opaque = includeOpaque ? 'OpaqueBadge(),' : '';
  final extra = extraOpaque ? 'OpaqueBadge(),' : '';
  final inline = remapInline ? 'OpaqueBadge()' : 'InlineBadge()';
  return '''
widget InlineBadge = BuiltInCard(title: "implementation");
widget Card = BuiltInCard(title: "shadow");
widget Dead = BuiltInCard(title: "unused");
widget Paywall = BuiltInCard(
  title: "$rootTitle",
  children: [$opaque $extra $inline, InlineBadge(), Card(), Generic()],
);
''';
}
