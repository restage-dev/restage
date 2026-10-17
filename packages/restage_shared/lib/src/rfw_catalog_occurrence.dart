import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:restage_shared/src/surface_contract/surface_contract_json.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// The most catalog occurrences, render roots, origins or local symbols one
/// library may carry.
const int kMaximumRfwCatalogOccurrenceCount = 1024;
const int _kMaximumRfwIdentifierCodeUnits = 128;
const int _kMaximumRfwIdentifierUtf8Bytes = 128;
const int _kMaximumRfwProvenanceCodeUnits = 1024;
const int _kMaximumRfwProvenanceUtf8Bytes = 1024;
final RegExp _rfwIdentifierPattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

/// Exact catalog origin selected for one emitted RFW constructor spelling.
@immutable
final class RfwCatalogConstructorProvenance {
  /// Creates one exact constructor origin.
  RfwCatalogConstructorProvenance({
    required this.constructorName,
    required this.catalogLibraryNamespace,
    required this.catalogWidgetWireId,
  }) {
    if (!_isRfwIdentifier(constructorName) ||
        !_isCatalogNamespace(catalogLibraryNamespace) ||
        catalogWidgetWireId.kind != WireIdKind.widget) {
      throw ArgumentError(
        'A catalog constructor origin requires a valid RFW name, catalog '
        'namespace, and widget wire identity',
      );
    }
  }

  /// RFW constructor spelling emitted by the trusted compiler.
  final String constructorName;

  /// Exact catalog library namespace selected before RFW emission.
  final String catalogLibraryNamespace;

  /// Exact catalog widget wire identity selected before RFW emission.
  final WireId catalogWidgetWireId;

  /// Canonical source-selected constructor identity.
  Map<String, Object?> toJson() => {
        'constructorName': constructorName,
        'catalogLibraryNamespace': catalogLibraryNamespace,
        'catalogWidgetWireId': catalogWidgetWireId.value,
      };

  /// Decodes the same closed identity used by the compiler.
  factory RfwCatalogConstructorProvenance.fromJson(Object? value) {
    final json = SurfaceContractJson.requireObject(value, r'$.catalogOrigin');
    SurfaceContractJson.exactKeys(
        json,
        const {
          'constructorName',
          'catalogLibraryNamespace',
          'catalogWidgetWireId',
        },
        r'$.catalogOrigin');
    return RfwCatalogConstructorProvenance(
      constructorName: SurfaceContractJson.requiredString(
          json, 'constructorName', r'$.catalogOrigin'),
      catalogLibraryNamespace: SurfaceContractJson.requiredString(
          json, 'catalogLibraryNamespace', r'$.catalogOrigin'),
      catalogWidgetWireId: WireId(SurfaceContractJson.requiredString(
          json, 'catalogWidgetWireId', r'$.catalogOrigin')),
    );
  }

  /// Whether [other] names the same exact emitted catalog constructor.
  bool matches(RfwCatalogConstructorProvenance other) =>
      constructorName == other.constructorName &&
      catalogLibraryNamespace == other.catalogLibraryNamespace &&
      catalogWidgetWireId == other.catalogWidgetWireId;

  @override
  bool operator ==(Object other) =>
      other is RfwCatalogConstructorProvenance && matches(other);

  @override
  int get hashCode => Object.hash(
        constructorName,
        catalogLibraryNamespace,
        catalogWidgetWireId,
      );
}

/// One local RFW declaration with its exact generated catalog origin, if any.
@immutable
final class RfwCatalogLocalSymbol {
  /// Creates one symbol in the emitted library's local declaration table.
  RfwCatalogLocalSymbol({
    required this.name,
    this.generatedCatalogOrigin,
  }) {
    if (!_isRfwIdentifier(name) ||
        (generatedCatalogOrigin != null &&
            generatedCatalogOrigin!.constructorName != name)) {
      throw ArgumentError(
        'A generated local catalog origin must match its local symbol name',
      );
    }
  }

  /// Canonical local-precedence evidence.
  Map<String, Object?> toJson() => {
        'name': name,
        if (generatedCatalogOrigin != null)
          'generatedCatalogOrigin': generatedCatalogOrigin!.toJson(),
      };

  /// Decodes a local declaration and its selected origin, if any.
  factory RfwCatalogLocalSymbol.fromJson(Object? value) {
    final json = SurfaceContractJson.requireObject(value, r'$.localSymbol');
    SurfaceContractJson.exactKeys(
        json,
        {
          'name',
          if (json.containsKey('generatedCatalogOrigin'))
            'generatedCatalogOrigin',
        },
        r'$.localSymbol');
    return RfwCatalogLocalSymbol(
      name: SurfaceContractJson.requiredString(json, 'name', r'$.localSymbol'),
      generatedCatalogOrigin: json.containsKey('generatedCatalogOrigin')
          ? RfwCatalogConstructorProvenance.fromJson(
              json['generatedCatalogOrigin'])
          : null,
    );
  }

  /// Exact local declaration spelling.
  final String name;

  /// Catalog origin for a compiler-generated local declaration.
  final RfwCatalogConstructorProvenance? generatedCatalogOrigin;
}

/// Closed input used to resolve catalog occurrences in one parsed RFW library.
@immutable
final class RfwCatalogOccurrenceResolutionInput {
  /// Creates the exact source and catalog evidence for one parsed library.
  factory RfwCatalogOccurrenceResolutionInput({
    required String artifactProvenance,
    required String sourceLibraryIdentity,
    required String sourceDeclarationIdentity,
    required Iterable<String> renderEntryNames,
    required Iterable<RfwCatalogConstructorProvenance> catalogConstructors,
    required Iterable<RfwCatalogLocalSymbol> localSymbols,
  }) {
    return RfwCatalogOccurrenceResolutionInput._(
      artifactProvenance: artifactProvenance,
      sourceLibraryIdentity: sourceLibraryIdentity,
      sourceDeclarationIdentity: sourceDeclarationIdentity,
      renderEntryNames: List.unmodifiable(renderEntryNames),
      catalogConstructors: List.unmodifiable(catalogConstructors),
      localSymbols: List.unmodifiable(localSymbols),
    );
  }

  RfwCatalogOccurrenceResolutionInput._({
    required this.artifactProvenance,
    required this.sourceLibraryIdentity,
    required this.sourceDeclarationIdentity,
    required List<String> renderEntryNames,
    required List<RfwCatalogConstructorProvenance> catalogConstructors,
    required List<RfwCatalogLocalSymbol> localSymbols,
  })  : renderEntryNames = Set.unmodifiable(renderEntryNames),
        catalogConstructors = List.unmodifiable(catalogConstructors),
        localSymbols = List.unmodifiable(localSymbols) {
    if (!_isProvenanceText(artifactProvenance) ||
        !_isProvenanceText(sourceLibraryIdentity) ||
        !_isProvenanceText(sourceDeclarationIdentity) ||
        renderEntryNames.isEmpty ||
        renderEntryNames.length > kMaximumRfwCatalogOccurrenceCount ||
        renderEntryNames.any((name) => !_isRfwIdentifier(name)) ||
        this.renderEntryNames.length != renderEntryNames.length ||
        catalogConstructors.length > kMaximumRfwCatalogOccurrenceCount ||
        localSymbols.length > kMaximumRfwCatalogOccurrenceCount) {
      throw ArgumentError(
        'RFW occurrence resolution requires bounded unique render roots and '
        'source provenance',
      );
    }

    final constructors = <String, RfwCatalogConstructorProvenance>{};
    for (final origin in this.catalogConstructors) {
      if (constructors.containsKey(origin.constructorName)) {
        throw ArgumentError(
          'One RFW constructor spelling was repeated',
        );
      }
      constructors[origin.constructorName] = origin;
    }
    final symbols = <String, RfwCatalogLocalSymbol>{};
    for (final symbol in this.localSymbols) {
      if (symbols.containsKey(symbol.name)) {
        throw ArgumentError('One RFW local declaration was repeated');
      }
      symbols[symbol.name] = symbol;
      final generated = symbol.generatedCatalogOrigin;
      final selected =
          generated == null ? null : constructors[generated.constructorName];
      if (generated != null &&
          (selected == null || !selected.matches(generated))) {
        throw ArgumentError(
          'A generated local declaration needs its exact catalog origin',
        );
      }
    }
    for (final renderEntryName in this.renderEntryNames) {
      if (symbols[renderEntryName]?.generatedCatalogOrigin != null) {
        throw ArgumentError(
          'An explicit RFW render root must be an ordinary local declaration',
        );
      }
    }
    _constructorsByName = Map.unmodifiable(constructors);
    _symbolsByName = Map.unmodifiable(symbols);
  }

  /// Canonical typed compiler input, with stable declaration ordering.
  Map<String, Object?> toJson() {
    final roots = renderEntryNames.toList()..sort();
    final constructors = catalogConstructors.toList()
      ..sort((a, b) => a.constructorName.compareTo(b.constructorName));
    final symbols = localSymbols.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return {
      'artifactProvenance': artifactProvenance,
      'sourceLibraryIdentity': sourceLibraryIdentity,
      'sourceDeclarationIdentity': sourceDeclarationIdentity,
      'renderEntryNames': roots,
      'catalogConstructors': [
        for (final origin in constructors) origin.toJson()
      ],
      'localSymbols': [for (final symbol in symbols) symbol.toJson()],
    };
  }

  /// Decodes bounded typed compiler input through the same constructor checks.
  factory RfwCatalogOccurrenceResolutionInput.fromJson(Object? value) {
    final json =
        SurfaceContractJson.requireObject(value, r'$.catalogResolution');
    SurfaceContractJson.exactKeys(
        json,
        const {
          'artifactProvenance',
          'sourceLibraryIdentity',
          'sourceDeclarationIdentity',
          'renderEntryNames',
          'catalogConstructors',
          'localSymbols',
        },
        r'$.catalogResolution');
    return RfwCatalogOccurrenceResolutionInput(
      artifactProvenance: SurfaceContractJson.requiredString(
          json, 'artifactProvenance', r'$.catalogResolution'),
      sourceLibraryIdentity: SurfaceContractJson.requiredString(
          json, 'sourceLibraryIdentity', r'$.catalogResolution'),
      sourceDeclarationIdentity: SurfaceContractJson.requiredString(
          json, 'sourceDeclarationIdentity', r'$.catalogResolution'),
      renderEntryNames: SurfaceContractJson.requireList(
              json['renderEntryNames'], r'$.catalogResolution.renderEntryNames')
          .map((value) {
        if (value is! String)
          throw const FormatException('An RFW render root must be a string.');
        return value;
      }),
      catalogConstructors: SurfaceContractJson.requireList(
              json['catalogConstructors'],
              r'$.catalogResolution.catalogConstructors')
          .map(RfwCatalogConstructorProvenance.fromJson),
      localSymbols: SurfaceContractJson.requireList(
              json['localSymbols'], r'$.catalogResolution.localSymbols')
          .map(RfwCatalogLocalSymbol.fromJson),
    );
  }

  /// Source-form artifact provenance shared between compiler passes.
  final String artifactProvenance;

  /// Resolved source-library identity.
  final String sourceLibraryIdentity;

  /// Resolved source-declaration identity.
  final String sourceDeclarationIdentity;

  /// Exact declared render roots admitted to occurrence resolution.
  final Set<String> renderEntryNames;

  /// Typed catalog origins emitted in this library.
  final List<RfwCatalogConstructorProvenance> catalogConstructors;

  /// Complete local declaration table with local-precedence evidence.
  final List<RfwCatalogLocalSymbol> localSymbols;

  late final Map<String, RfwCatalogConstructorProvenance> _constructorsByName;
  late final Map<String, RfwCatalogLocalSymbol> _symbolsByName;

  /// Returns the exact catalog origin for a constructor spelling.
  RfwCatalogConstructorProvenance? catalogConstructorForName(String name) =>
      _constructorsByName[name];

  /// Returns the exact local declaration evidence for [name].
  RfwCatalogLocalSymbol? localSymbolForName(String name) =>
      _symbolsByName[name];
}

bool _isRfwIdentifier(String value) =>
    value.length <= _kMaximumRfwIdentifierCodeUnits &&
    utf8.encode(value).length <= _kMaximumRfwIdentifierUtf8Bytes &&
    _rfwIdentifierPattern.hasMatch(value);

bool _isCatalogNamespace(String value) =>
    value.isNotEmpty &&
    value.length <= _kMaximumRfwIdentifierCodeUnits &&
    utf8.encode(value).length <= _kMaximumRfwIdentifierUtf8Bytes &&
    WidgetLibrary.isValidNamespace(value);

bool _isProvenanceText(String value) =>
    value.isNotEmpty &&
    value.length <= _kMaximumRfwProvenanceCodeUnits &&
    _isWellFormedUnicodeScalarText(value) &&
    utf8.encode(value).length <= _kMaximumRfwProvenanceUtf8Bytes &&
    !value.codeUnits.any(
      (unit) =>
          (unit >= 0x0000 && unit <= 0x001f) ||
          (unit >= 0x007f && unit <= 0x009f),
    );

bool _isWellFormedUnicodeScalarText(String value) {
  for (var index = 0; index < value.length; index += 1) {
    final unit = value.codeUnitAt(index);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (index + 1 >= value.length) return false;
      final trailing = value.codeUnitAt(index + 1);
      if (trailing < 0xdc00 || trailing > 0xdfff) return false;
      index += 1;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      return false;
    }
  }
  return true;
}
