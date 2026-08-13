import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// One source type that a downstream generator will reproduce without a
/// prefix.
///
/// [sourcePath] identifies the widget/property that requires the bare spelling
/// so namespace failures point back to customer source rather than generated
/// output.
final class DartBareSymbolImport {
  /// Creates a bare-symbol import requirement.
  const DartBareSymbolImport({
    required this.libraryUri,
    required this.symbol,
    required this.sourcePath,
  });

  /// Defining library of [symbol].
  final String libraryUri;

  /// Public type name reproduced bare by generated source.
  final String symbol;

  /// Customer source path that requires this spelling.
  final String sourcePath;
}

/// One name already present in a generated library's bare namespace.
///
/// A non-null [libraryUri] records the declaration identity already provided
/// by an implicit, broad, or manual `show` import. A null URI reserves a
/// generated declaration or externally assigned prefix that cannot satisfy a
/// type import of the same name.
final class DartBareSymbolReservation {
  /// Creates a bare-namespace reservation.
  const DartBareSymbolReservation({
    required this.symbol,
    required this.source,
    this.libraryUri,
  });

  /// Defining library when this reservation provides a Dart declaration.
  final String? libraryUri;

  /// Reserved public identifier.
  final String symbol;

  /// Human-readable origin used in fail-loud diagnostics.
  final String source;
}

final class _ResolvedBareImport {
  const _ResolvedBareImport({
    required this.libraryUri,
    required this.sourcePath,
  });

  final String libraryUri;
  final String sourcePath;
}

final class _ResolvedBareReservation {
  const _ResolvedBareReservation({
    required this.libraryUri,
    required this.source,
  });

  final String? libraryUri;
  final String source;
}

/// Deterministic import and qualification plan for generated Dart source.
///
/// Every non-`dart:core` identity is resolved to one import URI before aliases
/// are assigned. Flutter implementation-library identities are redirected to
/// their public barrel; all other libraries retain their exact URI. Prefixes
/// are assigned over the sorted resolved URI set, making same-named symbols
/// collision-proof and output byte-stable.
final class DartImportPlanner {
  /// Plans [libraryUris] using [prefixStem] followed by a zero-based index.
  ///
  /// [unprefixedLibraryUris] is reserved for target runtime imports whose
  /// symbols are deliberately emitted bare. [fixedPrefixes] lets a target
  /// reserve a semantic prefix (for example the generated story's source
  /// library) while every remaining import still uses deterministic indexing.
  /// [bareSymbolImports] adds narrow `show` imports beside those prefixes for
  /// generators that reproduce selected source types bare.
  /// [bareSymbolReservations] describes every name already available or
  /// reserved in that same bare namespace. The planner rejects conflicts with
  /// those names, other bare imports, and assigned import prefixes before
  /// source emission.
  DartImportPlanner({
    required Iterable<String> libraryUris,
    this.prefixStem = 'restage_import_',
    Set<String> unprefixedLibraryUris = const {},
    Map<String, String> fixedPrefixes = const {},
    Iterable<DartBareSymbolImport> bareSymbolImports = const [],
    Iterable<DartBareSymbolReservation> bareSymbolReservations = const [],
  }) {
    final sources = libraryUris.toSet();
    final resolvedUnprefixed = {
      for (final uri in unprefixedLibraryUris) publicDartImportUri(uri),
    };
    final resolvedFixed = <String, String>{};
    for (final entry in fixedPrefixes.entries) {
      final uri = publicDartImportUri(entry.key);
      _validatePublicIdentifier(
        entry.value,
        position: DartIdentifierPosition.importPrefix,
        role: 'import prefix',
      );
      if (resolvedUnprefixed.contains(uri)) {
        throw StateError(
          'Dart import $uri cannot be both unprefixed and fixed to '
          '${entry.value}.',
        );
      }
      final previous = resolvedFixed[uri];
      if (previous != null && previous != entry.value) {
        throw StateError(
          'Dart import $uri has conflicting fixed prefixes $previous and '
          '${entry.value}.',
        );
      }
      resolvedFixed[uri] = entry.value;
    }

    final resolvedReservations = <String, List<_ResolvedBareReservation>>{};
    for (final reservation in bareSymbolReservations) {
      _validatePublicIdentifier(
        reservation.symbol,
        position: DartIdentifierPosition.memberSelector,
        role: 'bare namespace reservation',
      );
      if (reservation.source.trim().isEmpty) {
        throw StateError(
          'Bare namespace reservation `${reservation.symbol}` has no source.',
        );
      }
      final resolvedUri = reservation.libraryUri == null
          ? null
          : publicDartImportUri(reservation.libraryUri!);
      resolvedReservations.putIfAbsent(reservation.symbol, () => []).add(
            _ResolvedBareReservation(
              libraryUri: resolvedUri,
              source: reservation.source,
            ),
          );
    }
    for (final reservations in resolvedReservations.values) {
      reservations.sort((left, right) {
        final byUri = (left.libraryUri ?? '').compareTo(
          right.libraryUri ?? '',
        );
        return byUri != 0 ? byUri : left.source.compareTo(right.source);
      });
    }
    for (final entry in resolvedReservations.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key))) {
      final bindings = <String, _ResolvedBareReservation>{};
      for (final reservation in entry.value) {
        final identity = reservation.libraryUri == null
            ? 'reservation:${reservation.source}'
            : 'library:${reservation.libraryUri}';
        bindings.putIfAbsent(identity, () => reservation);
      }
      if (bindings.length <= 1) continue;
      final origins = [
        for (final reservation in bindings.values)
          reservation.libraryUri == null
              ? reservation.source
              : '${reservation.source} '
                  '(${reservation.libraryUri}#${entry.key})',
      ];
      throw StateError(
        'Dart bare symbol `${entry.key}` has conflicting bare namespace '
        'bindings: ${origins.join('; ')}.',
      );
    }

    final requestedBareSymbols = bareSymbolImports.toList(growable: false)
      ..sort((left, right) {
        final bySymbol = left.symbol.compareTo(right.symbol);
        if (bySymbol != 0) return bySymbol;
        final byUri = left.libraryUri.compareTo(right.libraryUri);
        return byUri != 0 ? byUri : left.sourcePath.compareTo(right.sourcePath);
      });
    final resolvedUnprefixedSymbols = <String, Set<String>>{};
    final requestByBareSymbol = <String, _ResolvedBareImport>{};
    for (final request in requestedBareSymbols) {
      _validatePublicTypeIdentity(request.libraryUri, request.symbol);
      if (request.sourcePath.trim().isEmpty) {
        throw StateError(
          'Bare Dart type ${request.libraryUri}#${request.symbol} has no '
          'customer source path.',
        );
      }
      final uri = publicDartImportUri(request.libraryUri);
      var alreadyProvided = false;
      for (final reservation in resolvedReservations[request.symbol] ??
          const <_ResolvedBareReservation>[]) {
        if (reservation.libraryUri == uri) {
          alreadyProvided = true;
          continue;
        }
        final existingIdentity = reservation.libraryUri == null
            ? reservation.source
            : '${reservation.source} '
                '(${reservation.libraryUri}#${request.symbol})';
        throw StateError(
          'Dart type $uri#${request.symbol} at ${request.sourcePath} cannot '
          'be imported bare: `${request.symbol}` is already bound by '
          '$existingIdentity.',
        );
      }
      if (requestByBareSymbol[request.symbol] case final previous?) {
        if (previous.libraryUri != uri) {
          throw StateError(
            'Dart type $uri#${request.symbol} at ${request.sourcePath} cannot '
            'be imported bare because ${previous.libraryUri}#'
            '${request.symbol} at ${previous.sourcePath} already requires '
            'that spelling.',
          );
        }
        continue;
      }
      requestByBareSymbol[request.symbol] = _ResolvedBareImport(
        libraryUri: uri,
        sourcePath: request.sourcePath,
      );
      if (!alreadyProvided) {
        resolvedUnprefixedSymbols
            .putIfAbsent(uri, () => <String>{})
            .add(request.symbol);
      }
    }

    final resolvedUris = <String>{};
    for (final source in sources) {
      final resolved = publicDartImportUri(source);
      _resolvedBySource[source] = resolved;
      _resolvedBySource[resolved] = resolved;
      if (resolved != 'dart:core') resolvedUris.add(resolved);
    }
    for (final uri in resolvedUnprefixed) {
      _resolvedBySource[uri] = uri;
      if (uri != 'dart:core') resolvedUris.add(uri);
    }
    for (final uri in resolvedFixed.keys) {
      _resolvedBySource[uri] = uri;
      if (uri != 'dart:core') resolvedUris.add(uri);
    }
    for (final request in requestedBareSymbols) {
      final uri = publicDartImportUri(request.libraryUri);
      _resolvedBySource[request.libraryUri] = uri;
      _resolvedBySource[uri] = uri;
      if (uri != 'dart:core') resolvedUris.add(uri);
    }

    final ordered = resolvedUris.toList()..sort();
    var nextPrefix = 0;
    final uriByPrefix = <String, String>{};
    for (final uri in ordered) {
      if (resolvedUnprefixed.contains(uri)) {
        _prefixByResolvedUri[uri] = null;
      } else if (resolvedFixed[uri] case final fixed?) {
        _prefixByResolvedUri[uri] = fixed;
      } else {
        _prefixByResolvedUri[uri] = '$prefixStem${nextPrefix++}';
      }
      if (_prefixByResolvedUri[uri] case final prefix?) {
        _validatePublicIdentifier(
          prefix,
          position: DartIdentifierPosition.importPrefix,
          role: 'import prefix',
        );
        if (uriByPrefix[prefix] case final previous?) {
          throw StateError(
            'Dart imports $previous and $uri collide on prefix $prefix.',
          );
        }
        uriByPrefix[prefix] = uri;
      }
    }
    for (final entry in uriByPrefix.entries) {
      for (final reservation in resolvedReservations[entry.key] ??
          const <_ResolvedBareReservation>[]) {
        throw StateError(
          'Dart import ${entry.value} cannot use prefix ${entry.key}: that '
          'name is already bound by ${reservation.source}.',
        );
      }
    }
    for (final entry in requestByBareSymbol.entries) {
      if (uriByPrefix[entry.key] case final prefixLibrary?) {
        throw StateError(
          'Dart type ${entry.value.libraryUri}#${entry.key} at '
          '${entry.value.sourcePath} cannot be imported bare because import '
          'prefix ${entry.key} is assigned to $prefixLibrary.',
        );
      }
    }
    String narrowImport(String uri) {
      final symbols = resolvedUnprefixedSymbols[uri]!.toList()..sort();
      return "import '$uri' show ${symbols.join(', ')};";
    }

    _importDirectives = [
      for (final uri in ordered)
        if (_prefixByResolvedUri[uri] case final prefix?)
          "import '$uri' as $prefix;"
        else
          "import '$uri';",
      for (final uri in resolvedUnprefixedSymbols.keys.toList()..sort())
        if (uri != 'dart:core') narrowImport(uri),
    ];
  }

  /// Prefix stem used for planner-assigned imports.
  final String prefixStem;

  final Map<String, String> _resolvedBySource = {};
  final Map<String, String?> _prefixByResolvedUri = {};
  late final List<String> _importDirectives;

  /// Sorted import directives for the generated library.
  List<String> get importDirectives => List.unmodifiable(_importDirectives);

  /// Sorted directives for the planned subset referenced by [libraryUris].
  ///
  /// This preserves aliases from the full plan while allowing an emitter to
  /// discard an un-emittable declaration without renumbering the survivors.
  List<String> importDirectivesFor(Iterable<String> libraryUris) {
    final selected = <String>{};
    for (final source in libraryUris) {
      final resolved = publicDartImportUri(source);
      if (resolved == 'dart:core') continue;
      if (!_prefixByResolvedUri.containsKey(resolved)) {
        throw StateError('Dart library $source was not included in the plan.');
      }
      selected.add(resolved);
    }
    final ordered = selected.toList()..sort();
    return [
      for (final uri in ordered)
        if (_prefixByResolvedUri[uri] case final prefix?)
          "import '$uri' as $prefix;"
        else
          "import '$uri';",
    ];
  }

  /// Source-library URI to assigned prefix.
  ///
  /// Unprefixed and `dart:core` identities are absent. Both analyzer defining
  /// URIs and their resolved public Flutter barrel URI map to the same prefix.
  Map<String, String> get prefixesBySourceUri => Map.unmodifiable({
        for (final entry in _resolvedBySource.entries)
          if (_prefixByResolvedUri[entry.value] case final prefix?)
            entry.key: prefix,
      });

  /// Qualifies public [symbol] from [libraryUri] according to this plan.
  String qualify(String libraryUri, String symbol) {
    _validatePublicIdentifier(
      symbol,
      position: DartIdentifierPosition.memberSelector,
      role: 'Dart symbol',
    );
    return _qualifyValidated(libraryUri, symbol);
  }

  String _qualifyType(String libraryUri, String symbol) {
    _validatePublicTypeIdentity(libraryUri, symbol);
    return _qualifyValidated(libraryUri, symbol);
  }

  String _qualifyValidated(String libraryUri, String symbol) {
    final resolved = publicDartImportUri(libraryUri);
    if (resolved == 'dart:core') return symbol;
    if (!_prefixByResolvedUri.containsKey(resolved)) {
      throw StateError(
        'Dart identity $libraryUri#$symbol was not included in the import '
        'plan.',
      );
    }
    final prefix = _prefixByResolvedUri[resolved];
    return prefix == null ? symbol : '$prefix.$symbol';
  }

  /// Renders [type] with every generic argument qualified independently.
  String renderType(DartTypeIdentity type) => switch (type) {
        DartNamedTypeIdentity() => _renderNamedType(
            type,
            _qualifyType,
            renderType,
          ),
        DartRecordTypeIdentity() => _renderRecordType(type, renderType),
      };

  /// Qualifies a public top-level or owner-qualified static reference.
  String qualifyReference({
    required String libraryUri,
    required String member,
    String? owner,
  }) {
    _validatePublicIdentifier(
      member,
      position: DartIdentifierPosition.memberSelector,
      role: 'Dart member',
    );
    if (owner case final owner?) {
      _validatePublicIdentifier(
        owner,
        position: DartIdentifierPosition.typeName,
        role: 'Dart owner',
      );
      return '${_qualifyValidated(libraryUri, owner)}.$member';
    }
    return _qualifyValidated(libraryUri, member);
  }

  /// Qualifies the target of a public constructor invocation.
  String qualifyConstructor(
    DartTypeIdentity type, {
    String? constructorName,
  }) {
    if (constructorName case final name?) {
      _validatedDartConstructorSelector(name);
    }
    if (type is! DartNamedTypeIdentity) {
      throw StateError('A structural record type has no Dart constructor.');
    }
    _validatePublicIdentifier(
      type.symbolName,
      position: DartIdentifierPosition.typeName,
      role: 'Dart constructor type',
    );
    final nonNullable = type.nullable
        ? DartNamedTypeIdentity(
            libraryUri: type.libraryUri,
            symbolName: type.symbolName,
            typeArguments: type.typeArguments,
          )
        : type;
    final rendered = renderType(nonNullable);
    return constructorName == null ? rendered : '$rendered.$constructorName';
  }
}

/// Every library URI recursively referenced by [type].
Set<String> dartTypeIdentityLibraryUris(DartTypeIdentity type) =>
    switch (type) {
      DartNamedTypeIdentity(:final libraryUri, :final typeArguments) => {
          libraryUri,
          for (final argument in typeArguments)
            ...dartTypeIdentityLibraryUris(argument),
        },
      DartRecordTypeIdentity(:final positional, :final named) => {
          for (final field in positional) ...dartTypeIdentityLibraryUris(field),
          for (final field in _canonicalNamed(named, (field) => field.name))
            ...dartTypeIdentityLibraryUris(field.type),
        },
    };

/// Every library URI recursively referenced by [value].
Set<String> dartConstValueLibraryUris(DartConstValue value) => switch (value) {
      DartConstNull() || DartConstScalar() => const {},
      DartConstReference(:final libraryUri) => {libraryUri},
      DartConstInvocation(:final type, :final positional, :final named) => {
          ...dartTypeIdentityLibraryUris(type),
          for (final value in positional) ...dartConstValueLibraryUris(value),
          for (final argument
              in _canonicalNamed(named, (argument) => argument.name))
            ...dartConstValueLibraryUris(argument.value),
        },
      DartConstList(:final values, :final type) ||
      DartConstSet(:final values, :final type) =>
        {
          if (type != null) ...dartTypeIdentityLibraryUris(type),
          for (final value in values) ...dartConstValueLibraryUris(value),
        },
      DartConstMap(:final entries, :final type) => {
          if (type != null) ...dartTypeIdentityLibraryUris(type),
          for (final entry in entries) ...dartConstValueLibraryUris(entry.key),
          for (final entry in entries)
            ...dartConstValueLibraryUris(entry.value),
        },
      DartConstRecord(:final positional, :final named) => {
          for (final value in positional) ...dartConstValueLibraryUris(value),
          for (final field in _canonicalNamed(named, (field) => field.name))
            ...dartConstValueLibraryUris(field.value),
        },
    };

/// The design-system packages that publish copies of the framework's
/// material / cupertino layers, mapped to the framework area each one copies.
///
/// A class in one of these packages is treated as framework code rather than
/// customer code. The names are reserved on the package registry to the
/// framework vendor, so a look-alike cannot arrive through an ordinary hosted
/// dependency — which is what lets the framework-vs-customer predicates accept
/// them while keeping the value-substitution guarantee they exist to provide.
///
/// The guarantee is about ordinary dependencies, not an absolute: a deliberate
/// path or git dependency declared under one of these names shadows the hosted
/// package and would be accepted here. That is strictly weaker than the
/// alternative it replaces — matching on a bare class name, which accepts a
/// look-alike from anywhere with no declaration at all.
const Map<String, String> kDesignPackageFrameworkAreas = {
  'package:material_ui/': 'material',
  'package:cupertino_ui/': 'cupertino',
};

/// The keys of [kDesignPackageFrameworkAreas], spelled out so they can be
/// spread into a `const` list (a map's `keys` is not a constant expression).
const List<String> kDesignPackageLibraryPrefixes = [
  'package:material_ui/',
  'package:cupertino_ui/',
];

/// The framework identity that [uri] denotes.
///
/// A design-package implementation library maps to the framework
/// implementation library holding the same symbols — `package:material_ui/src/
/// card.dart` to `package:flutter/src/material/card.dart`. The file basename is
/// preserved on both sides of the copy, so this is a total mapping over the
/// symbols the catalog names, not a heuristic: every catalog entry sourced from
/// the framework's material / cupertino layers round-trips through it.
///
/// Any other URI — framework, SDK or customer — is returned unchanged.
///
/// Canonicalising at the points where an identity is DERIVED keeps every
/// downstream join exact. Without it a design-package construction would miss
/// its catalog entry by identity and fall through to a name lookup, which is
/// how a different type silently binds to one of our entries.
String canonicalFrameworkLibraryUri(String uri) {
  for (final entry in kDesignPackageFrameworkAreas.entries) {
    final implementationPrefix = '${entry.key}src/';
    if (!uri.startsWith(implementationPrefix)) continue;
    final rest = uri.substring(implementationPrefix.length);
    return 'package:flutter/src/${entry.value}/$rest';
  }
  return uri;
}

/// Resolves an analyzer defining-library URI to an importable public URI.
///
/// Flutter's analyzer elements commonly report `package:flutter/src/...` even
/// when customer code imported a public barrel. Generated customer code must
/// never import those implementation libraries directly — and the same holds
/// for a design package's own `lib/src/`, which generated code must reach
/// through that package's barrel rather than by naming its private tree.
String publicDartImportUri(String sourceUri) {
  if (sourceUri.isEmpty || sourceUri.contains('#')) {
    throw StateError('Unimportable Dart library URI `$sourceUri`.');
  }
  for (final prefix in kDesignPackageFrameworkAreas.keys) {
    if (!sourceUri.startsWith('${prefix}src/')) continue;
    final package = prefix.substring('package:'.length, prefix.length - 1);
    return '$prefix$package.dart';
  }
  const flutterImplementationPrefix = 'package:flutter/src/';
  if (!sourceUri.startsWith(flutterImplementationPrefix)) {
    if (!sourceUri.startsWith('dart:') &&
        !sourceUri.startsWith('package:') &&
        !sourceUri.startsWith('file:')) {
      throw StateError('Unimportable Dart library URI `$sourceUri`.');
    }
    return sourceUri;
  }

  final rest = sourceUri.substring(flutterImplementationPrefix.length);
  final separator = rest.indexOf('/');
  if (separator <= 0) {
    throw StateError(
      'Flutter identity `$sourceUri` has no known public barrel.',
    );
  }
  final area = rest.substring(0, separator);
  const publicAreas = {
    'animation',
    'cupertino',
    'foundation',
    'gestures',
    'material',
    'painting',
    'physics',
    'rendering',
    'scheduler',
    'semantics',
    'services',
    'widgets',
  };
  if (!publicAreas.contains(area)) {
    throw StateError(
      'Flutter identity `$sourceUri` has no known public barrel.',
    );
  }
  return 'package:flutter/$area.dart';
}

/// Whether [uri] belongs to application/package code rather than Dart or
/// Flutter itself.
bool isApplicationDartLibrary(String uri) =>
    !uri.startsWith('dart:') && !uri.startsWith('package:flutter/');

/// Qualifies one already-validated flat type spelling through [prefixes].
///
/// This adapter exists for analyzer sidecars that still retain a flat spelling
/// such as `Box<int>`. New identity-bearing paths should use
/// [DartImportPlanner.renderType], which qualifies every argument recursively.
String qualifyFlatDartType(
  String typeName,
  String? libraryUri,
  Map<String, String> prefixes,
) {
  final match = RegExp(r'^([A-Za-z$][A-Za-z0-9_$]*)(.*)$').firstMatch(typeName);
  if (match == null) {
    throw StateError('Cannot emit invalid Dart type spelling `$typeName`.');
  }
  _validatePublicTypeIdentity(libraryUri, match.group(1)!);
  final prefix = libraryUri == null ? null : prefixes[libraryUri];
  return prefix == null ? typeName : '$prefix.$typeName';
}

/// Renders recursive [type] identity through a planner-produced prefix map.
String renderDartTypeFromPrefixes(
  DartTypeIdentity type,
  Map<String, String> prefixes,
) =>
    switch (type) {
      DartNamedTypeIdentity() => _renderNamedType(
          type,
          (libraryUri, symbolName) =>
              qualifyFlatDartType(symbolName, libraryUri, prefixes),
          (argument) => renderDartTypeFromPrefixes(argument, prefixes),
        ),
      DartRecordTypeIdentity() => _renderRecordType(
          type,
          (field) => renderDartTypeFromPrefixes(field, prefixes),
        ),
    };

/// Renders a reconstructed const as import-qualified Dart source.
///
/// The input IR contains only public, importable identities and recursively
/// reconstructable constant values. This function remains exhaustive over the
/// sealed IR so adding a new accepted constant class cannot silently disappear
/// from generated targets.
String renderDartConstValueFromPrefixes(
  DartConstValue value,
  Map<String, String> prefixes,
) =>
    switch (value) {
      DartConstNull() => 'null',
      DartConstScalar(:final value) => _renderDartConstScalar(value),
      DartConstReference(:final libraryUri, :final owner, :final member) =>
        _renderDartConstReference(
          libraryUri: libraryUri,
          owner: owner,
          member: member,
          prefixes: prefixes,
        ),
      DartConstInvocation(
        :final type,
        :final constructorName,
        :final positional,
        :final named,
      ) =>
        _renderDartConstInvocation(
          type: type,
          constructorName: constructorName,
          positional: positional,
          named: named,
          prefixes: prefixes,
        ),
      DartConstList(:final values, :final type) => _renderDartConstList(
          values,
          type: type,
          prefixes: prefixes,
        ),
      DartConstSet(:final values, :final type) => _renderDartConstSet(
          values,
          type: type,
          prefixes: prefixes,
        ),
      DartConstMap(:final entries, :final type) => _renderDartConstMap(
          entries,
          type: type,
          prefixes: prefixes,
        ),
      DartConstRecord(:final positional, :final named) => positional.isEmpty &&
              named.isEmpty
          ? '()'
          : '(${[
              for (final item in positional)
                renderDartConstValueFromPrefixes(item, prefixes),
              for (final field in _canonicalNamed(named, (field) => field.name))
                _renderDartConstNamedValue(
                  field,
                  prefixes,
                  position: DartIdentifierPosition.recordField,
                  role: 'record field',
                ),
            ].join(', ')},)',
    };

String _renderDartConstList(
  List<DartConstValue> values, {
  required DartTypeIdentity? type,
  required Map<String, String> prefixes,
}) {
  final arguments = _renderCollectionTypeArguments(
    type,
    collectionName: 'List',
    arity: 1,
    prefixes: prefixes,
  );
  final inferredArguments = arguments ?? (values.isEmpty ? '<Never>' : '');
  final elements = values
      .map((value) => renderDartConstValueFromPrefixes(value, prefixes))
      .join(', ');
  return 'const $inferredArguments[$elements]';
}

String _renderDartConstSet(
  List<DartConstValue> values, {
  required DartTypeIdentity? type,
  required Map<String, String> prefixes,
}) {
  final arguments = _renderCollectionTypeArguments(
    type,
    collectionName: 'Set',
    arity: 1,
    prefixes: prefixes,
  );
  final inferredArguments = arguments ?? (values.isEmpty ? '<Never>' : '');
  final elements = values
      .map((value) => renderDartConstValueFromPrefixes(value, prefixes))
      .join(', ');
  return 'const $inferredArguments{$elements}';
}

String _renderDartConstMap(
  List<DartConstMapEntry> entries, {
  required DartTypeIdentity? type,
  required Map<String, String> prefixes,
}) {
  final arguments = _renderCollectionTypeArguments(
    type,
    collectionName: 'Map',
    arity: 2,
    prefixes: prefixes,
  );
  final inferredArguments =
      arguments ?? (entries.isEmpty ? '<Never, Never>' : '');
  final renderedEntries = entries
      .map((entry) => _renderDartConstMapEntry(entry, prefixes))
      .join(', ');
  return 'const $inferredArguments{$renderedEntries}';
}

String? _renderCollectionTypeArguments(
  DartTypeIdentity? type, {
  required String collectionName,
  required int arity,
  required Map<String, String> prefixes,
}) {
  if (type == null) return null;
  if (type is! DartNamedTypeIdentity) {
    throw StateError(
      'Cannot emit structural record identity as $collectionName.',
    );
  }
  if (type.libraryUri != 'dart:core' ||
      type.symbolName != collectionName ||
      type.nullable ||
      type.typeArguments.length != arity) {
    throw StateError(
      'Cannot emit collection identity '
      '${type.libraryUri}#${type.symbolName} as $collectionName.',
    );
  }
  return '<${type.typeArguments.map(
        (argument) => renderDartTypeFromPrefixes(argument, prefixes),
      ).join(', ')}>';
}

String _renderDartConstMapEntry(
  DartConstMapEntry entry,
  Map<String, String> prefixes,
) {
  final key = renderDartConstValueFromPrefixes(entry.key, prefixes);
  final value = renderDartConstValueFromPrefixes(entry.value, prefixes);
  return '$key: $value';
}

String _renderDartConstNamedValue(
  DartConstNamedValue value,
  Map<String, String> prefixes, {
  required DartIdentifierPosition position,
  required String role,
}) {
  final name = _validatedDartIdentifier(
    value.name,
    position: position,
    role: role,
  );
  final rendered = renderDartConstValueFromPrefixes(value.value, prefixes);
  return '$name: $rendered';
}

String _renderDartConstReference({
  required String libraryUri,
  required String? owner,
  required String member,
  required Map<String, String> prefixes,
}) {
  final validatedMember = _validatedDartIdentifier(
    member,
    position: DartIdentifierPosition.memberSelector,
    role: 'Dart member',
  );
  if (owner == null) {
    final prefix = prefixes[libraryUri];
    return prefix == null ? validatedMember : '$prefix.$validatedMember';
  }
  final validatedOwner = _validatedDartIdentifier(
    owner,
    position: DartIdentifierPosition.typeName,
    role: 'Dart owner',
  );
  final qualifiedOwner = qualifyFlatDartType(
    validatedOwner,
    libraryUri,
    prefixes,
  );
  return '$qualifiedOwner.$validatedMember';
}

String _renderDartConstInvocation({
  required DartTypeIdentity type,
  required String? constructorName,
  required List<DartConstValue> positional,
  required List<DartConstNamedValue> named,
  required Map<String, String> prefixes,
}) {
  if (type is! DartNamedTypeIdentity) {
    throw StateError('A structural record type has no const constructor.');
  }
  _validatePublicIdentifier(
    type.symbolName,
    position: DartIdentifierPosition.typeName,
    role: 'Dart constructor type',
  );
  final nonNullableType = type.nullable
      ? DartNamedTypeIdentity(
          libraryUri: type.libraryUri,
          symbolName: type.symbolName,
          typeArguments: type.typeArguments,
        )
      : type;
  final renderedType = renderDartTypeFromPrefixes(nonNullableType, prefixes);
  final validatedConstructor = constructorName == null
      ? null
      : _validatedDartConstructorSelector(constructorName);
  final renderedConstructor = validatedConstructor == null
      ? renderedType
      : '$renderedType.$validatedConstructor';
  final arguments = [
    for (final item in positional)
      renderDartConstValueFromPrefixes(item, prefixes),
    for (final argument in _canonicalNamed(named, (argument) => argument.name))
      _renderDartConstNamedValue(
        argument,
        prefixes,
        position: DartIdentifierPosition.namedArgument,
        role: 'named argument',
      ),
  ];
  return 'const $renderedConstructor(${arguments.join(', ')})';
}

String _renderDartConstScalar(Object value) => switch (value) {
      bool() || int() => value.toString(),
      double() when value.isFinite => value.toString(),
      String() => renderDartStringLiteral(value),
      _ => throw StateError(
          'Cannot emit non-portable Dart const scalar ${value.runtimeType}.',
        ),
    };

/// Renders [value] as a single-quoted Dart string literal.
///
/// Generated source paths, diagnostics, and reconstructed constants share
/// this renderer so `$` can never become interpolation and control characters
/// cannot break the generated library.
String renderDartStringLiteral(String value) {
  final buffer = StringBuffer("'");
  for (final rune in value.runes) {
    switch (rune) {
      case 0x08:
        buffer.write(r'\b');
      case 0x09:
        buffer.write(r'\t');
      case 0x0A:
        buffer.write(r'\n');
      case 0x0C:
        buffer.write(r'\f');
      case 0x0D:
        buffer.write(r'\r');
      case 0x24:
        buffer.write(r'\$');
      case 0x27:
        buffer.write(r"\'");
      case 0x5C:
        buffer.write(r'\\');
      default:
        if (rune < 0x20 || rune == 0x7F) {
          buffer
            ..write(r'\u')
            ..write(rune.toRadixString(16).padLeft(4, '0'));
        } else {
          buffer.writeCharCode(rune);
        }
    }
  }
  buffer.write("'");
  return buffer.toString();
}

String _validatedDartIdentifier(
  String value, {
  required DartIdentifierPosition position,
  required String role,
}) {
  _validatePublicIdentifier(value, position: position, role: role);
  return value;
}

String _validatedDartConstructorSelector(String value) {
  return _validatedDartIdentifier(
    value,
    position: DartIdentifierPosition.constructorSelector,
    role: 'Dart constructor',
  );
}

void _validatePublicIdentifier(
  String value, {
  required DartIdentifierPosition position,
  required String role,
}) {
  if (value.startsWith('_')) {
    throw StateError('Cannot emit private Dart identity `$value` ($role).');
  }
  if (!isPublicDartIdentifier(value, position: position)) {
    throw StateError('Cannot emit invalid Dart identity `$value` ($role).');
  }
}

void _validatePublicTypeIdentity(String? libraryUri, String symbolName) {
  if (symbolName.startsWith('_')) {
    throw StateError(
      'Cannot emit private Dart identity `$symbolName` (Dart type).',
    );
  }
  if (!isPublicDartTypeIdentity(libraryUri, symbolName)) {
    throw StateError(
      'Cannot emit invalid Dart type identity '
      '`${libraryUri ?? 'dart:core'}#$symbolName`.',
    );
  }
}

String _renderRecordType(
  DartRecordTypeIdentity type,
  String Function(DartTypeIdentity type) renderType,
) {
  final positional = [
    for (final field in type.positional) renderType(field),
  ];
  final named = _canonicalNamed(type.named, (field) => field.name).map((field) {
    final fieldName = _validatedDartIdentifier(
      field.name,
      position: DartIdentifierPosition.recordField,
      role: 'record field',
    );
    return '${renderType(field.type)} $fieldName';
  }).toList();
  final body = switch ((positional, named)) {
    ([], []) => '()',
    ([], final named) => '({${named.join(', ')}})',
    ([final field], []) => '($field,)',
    (final positional, []) => '(${positional.join(', ')})',
    (final positional, final named) =>
      '(${positional.join(', ')}, {${named.join(', ')}})',
  };
  return '$body${type.nullable ? '?' : ''}';
}

List<T> _canonicalNamed<T>(
  Iterable<T> values,
  String Function(T value) nameOf,
) =>
    values.toList()..sort((a, b) => nameOf(a).compareTo(nameOf(b)));

String _renderNamedType(
  DartNamedTypeIdentity type,
  String Function(String libraryUri, String symbolName) qualify,
  String Function(DartTypeIdentity type) renderType,
) {
  final arguments = type.typeArguments.isEmpty
      ? ''
      : '<${type.typeArguments.map(renderType).join(', ')}>';
  final nullable = type.nullable ? '?' : '';
  return '${qualify(type.libraryUri, type.symbolName)}$arguments$nullable';
}
