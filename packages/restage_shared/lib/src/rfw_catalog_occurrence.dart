import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:meta/meta.dart';
import 'package:restage_shared/src/rfw_formats.dart' as fmt;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

const int _kMaximumRfwCatalogOccurrenceCount = 1024;
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
        renderEntryNames.length > _kMaximumRfwCatalogOccurrenceCount ||
        renderEntryNames.any((name) => !_isRfwIdentifier(name)) ||
        this.renderEntryNames.length != renderEntryNames.length ||
        catalogConstructors.length > _kMaximumRfwCatalogOccurrenceCount ||
        localSymbols.length > _kMaximumRfwCatalogOccurrenceCount) {
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

/// Stable ledger anchor for a reachable ordinary local declaration body.
@immutable
final class RfwCatalogOccurrenceLocalDeclarationAnchor {
  const RfwCatalogOccurrenceLocalDeclarationAnchor._({
    required this.localName,
    required this.structuralOccurrenceKey,
  });

  /// Exact local declaration name in the parsed RFW library.
  final String localName;

  /// Stable declaration witness used as body-occurrence ancestry.
  final String structuralOccurrenceKey;
}

/// Structural evidence for one resolved catalog constructor occurrence.
@immutable
final class RfwCatalogOccurrenceDescriptor {
  const RfwCatalogOccurrenceDescriptor._({
    required this.structuralOccurrenceKey,
    required this.parentStructuralOccurrenceKey,
    required this.sourceLibraryIdentity,
    required this.sourceDeclarationIdentity,
    required this.artifactProvenance,
    required this.renderEntryName,
    required this.catalogLibraryNamespace,
    required this.catalogWidgetWireId,
    required this.namedChildSlot,
    required this.siblingOrdinal,
  });

  /// Stable locator used by a continuity ledger.
  final String structuralOccurrenceKey;

  /// Nearest resolved catalog parent, when present.
  final String? parentStructuralOccurrenceKey;

  /// Resolved source-library provenance.
  final String sourceLibraryIdentity;

  /// Resolved source-declaration provenance.
  final String sourceDeclarationIdentity;

  /// Stable source-form artifact provenance.
  final String artifactProvenance;

  /// Explicit render entry containing this occurrence.
  final String renderEntryName;

  /// Exact selected catalog namespace.
  final String catalogLibraryNamespace;

  /// Exact selected catalog widget wire identity.
  final WireId catalogWidgetWireId;

  /// Named child slot at the constructor boundary.
  final String namedChildSlot;

  /// Deterministic tie-breaker among matching siblings.
  final int siblingOrdinal;

  /// Stable evidence available to a compiler-owned continuity ledger.
  Map<String, Object?> get reconciliationEvidence => <String, Object?>{
        'artifactProvenance': artifactProvenance,
        'catalogLibraryNamespace': catalogLibraryNamespace,
        'catalogWidgetWireId': catalogWidgetWireId.value,
        'namedChildSlot': namedChildSlot,
        'parentStructuralOccurrenceKey': parentStructuralOccurrenceKey,
        'renderEntryName': renderEntryName,
        'siblingOrdinal': siblingOrdinal,
        'sourceDeclarationIdentity': sourceDeclarationIdentity,
        'sourceLibraryIdentity': sourceLibraryIdentity,
      };
}

/// Opaque value-stable reference to one resolved catalog occurrence.
@immutable
final class RfwCatalogOccurrenceHandle {
  const RfwCatalogOccurrenceHandle._(this._value);

  final String _value;

  @override
  bool operator ==(Object other) =>
      other is RfwCatalogOccurrenceHandle && other._value == _value;

  @override
  int get hashCode => _value.hashCode;
}

/// Exact parsed RFW call and its resolved catalog descriptor.
@immutable
final class RfwCatalogOccurrence {
  const RfwCatalogOccurrence._({
    required this.descriptor,
    required this.constructorCall,
    required this.handle,
  });

  /// Compiler-owned structural descriptor for this exact call.
  final RfwCatalogOccurrenceDescriptor descriptor;

  /// Exact parsed RFW call object in the source library.
  final fmt.ConstructorCall constructorCall;

  /// Opaque value-stable occurrence reference.
  final RfwCatalogOccurrenceHandle handle;
}

/// One exact final call bound to an already-resolved occurrence.
@immutable
final class RfwCatalogOccurrenceFinalBinding {
  const RfwCatalogOccurrenceFinalBinding._({
    required this.occurrence,
    required this.constructorCall,
  });

  /// Frozen occurrence selected before final encoding.
  final RfwCatalogOccurrence occurrence;

  /// Exact call object in the final parsed library.
  final fmt.ConstructorCall constructorCall;

  /// Value-stable reference for [occurrence].
  RfwCatalogOccurrenceHandle get handle => occurrence.handle;

  /// Ledger descriptor for [occurrence].
  RfwCatalogOccurrenceDescriptor get descriptor => occurrence.descriptor;
}

/// Exact final-library binding for a frozen occurrence set.
@immutable
final class ResolvedRfwCatalogOccurrenceRebinding {
  ResolvedRfwCatalogOccurrenceRebinding._({
    required this.finalLibrary,
    required this.occurrenceSet,
    required Iterable<RfwCatalogOccurrenceFinalBinding> bindings,
    required Map<fmt.ConstructorCall, RfwCatalogOccurrenceFinalBinding>
        bindingsByCall,
    required Map<RfwCatalogOccurrenceHandle, RfwCatalogOccurrenceFinalBinding>
        bindingsByHandle,
  })  : bindings = List.unmodifiable(bindings),
        _bindingsByCall = UnmodifiableMapView(bindingsByCall),
        _bindingsByHandle = UnmodifiableMapView(bindingsByHandle);

  /// Final parsed library whose calls are bound by [bindings].
  final fmt.RemoteWidgetLibrary finalLibrary;

  /// Frozen occurrence set that established every bound handle.
  final ResolvedRfwCatalogOccurrenceSet occurrenceSet;

  /// Exact call bindings in deterministic frozen-occurrence order.
  final List<RfwCatalogOccurrenceFinalBinding> bindings;

  final Map<fmt.ConstructorCall, RfwCatalogOccurrenceFinalBinding>
      _bindingsByCall;
  final Map<RfwCatalogOccurrenceHandle, RfwCatalogOccurrenceFinalBinding>
      _bindingsByHandle;

  /// Returns a binding by exact final call object.
  RfwCatalogOccurrenceFinalBinding? bindingForCall(
    fmt.ConstructorCall constructorCall,
  ) =>
      _bindingsByCall[constructorCall];

  /// Returns a binding by its value-stable handle.
  RfwCatalogOccurrenceFinalBinding? bindingForHandle(
    RfwCatalogOccurrenceHandle handle,
  ) =>
      _bindingsByHandle[handle];

  /// Requires one known frozen occurrence handle.
  RfwCatalogOccurrenceFinalBinding requireBindingForHandle(
    RfwCatalogOccurrenceHandle handle,
  ) {
    final binding = bindingForHandle(handle);
    if (binding == null) {
      throw const FormatException('Unknown RFW catalog occurrence handle');
    }
    return binding;
  }
}

/// Frozen resolved catalog occurrences for one parsed RFW library.
///
/// Resolution uses exact typed catalog evidence only once. Later
/// [rebindFinalLibrary] calls compare final constructor topology to this
/// frozen set and attach the original handles without running eligibility
/// rules again.
@immutable
final class ResolvedRfwCatalogOccurrenceSet {
  /// Resolves all eligible catalog calls reachable from explicit render roots.
  factory ResolvedRfwCatalogOccurrenceSet.resolve({
    required fmt.RemoteWidgetLibrary parsedLibrary,
    required RfwCatalogOccurrenceResolutionInput input,
  }) {
    final widgetsByName = <String, fmt.WidgetDeclaration>{
      for (final widget in parsedLibrary.widgets) widget.name: widget,
    };
    if (widgetsByName.length != parsedLibrary.widgets.length ||
        !input.renderEntryNames.every(widgetsByName.containsKey)) {
      throw const FormatException(
        'RFW occurrence resolution requires every explicit render root once',
      );
    }
    final parsedLocalNames = widgetsByName.keys.toSet();
    final inputLocalNames =
        input.localSymbols.map((symbol) => symbol.name).toSet();
    if (parsedLocalNames.length != inputLocalNames.length ||
        !parsedLocalNames.containsAll(inputLocalNames)) {
      throw const FormatException(
        'RFW local declaration evidence does not match the parsed library',
      );
    }

    final occurrences = <RfwCatalogOccurrence>[];
    final occurrencesByCall =
        Map<fmt.ConstructorCall, RfwCatalogOccurrence>.identity();
    final occurrencesByHandle =
        <RfwCatalogOccurrenceHandle, RfwCatalogOccurrence>{};
    final occurrenceLocations = <RfwCatalogOccurrenceHandle, String>{};
    final reachableCallsByLocation = <String, _ReachableRfwCall>{};
    final reachableOrdinaryLocalNames = <String>{};
    final localAnchorsByName =
        <String, RfwCatalogOccurrenceLocalDeclarationAnchor>{};
    final descriptorKeys = <String>{};
    final siblingOrdinals = <String, int>{};

    RfwCatalogOccurrenceDescriptor descriptorFor(
      RfwCatalogConstructorProvenance origin, {
      required String renderEntryName,
      required String? parentStructuralOccurrenceKey,
      required String namedChildSlot,
    }) {
      final parentWitness = parentStructuralOccurrenceKey ??
          _renderEntryWitness(
            sourceLibraryIdentity: input.sourceLibraryIdentity,
            sourceDeclarationIdentity: input.sourceDeclarationIdentity,
            renderEntryName: renderEntryName,
          );
      final siblingKey = _stableKey(
        'rfw.catalog.occurrence.sibling.v1',
        <String, Object?>{
          'catalogLibraryNamespace': origin.catalogLibraryNamespace,
          'catalogWidgetWireId': origin.catalogWidgetWireId.value,
          'namedChildSlot': namedChildSlot,
          'parentStructuralOccurrenceKey': parentWitness,
        },
      );
      final siblingOrdinal = siblingOrdinals.update(
        siblingKey,
        (value) => value + 1,
        ifAbsent: () => 0,
      );
      final key = _stableKey(
        'rfw.catalog.occurrence.v1',
        <String, Object?>{
          'artifactProvenance': input.artifactProvenance,
          'catalogLibraryNamespace': origin.catalogLibraryNamespace,
          'catalogWidgetWireId': origin.catalogWidgetWireId.value,
          'namedChildSlot': namedChildSlot,
          'parentStructuralOccurrenceKey': parentWitness,
          'renderEntryName': renderEntryName,
          'siblingOrdinal': siblingOrdinal,
          'sourceDeclarationIdentity': input.sourceDeclarationIdentity,
          'sourceLibraryIdentity': input.sourceLibraryIdentity,
        },
      );
      if (!descriptorKeys.add(key)) {
        throw const FormatException(
          'RFW occurrence resolution repeated one structural occurrence',
        );
      }
      return RfwCatalogOccurrenceDescriptor._(
        structuralOccurrenceKey: key,
        parentStructuralOccurrenceKey: parentStructuralOccurrenceKey,
        sourceLibraryIdentity: input.sourceLibraryIdentity,
        sourceDeclarationIdentity: input.sourceDeclarationIdentity,
        artifactProvenance: input.artifactProvenance,
        renderEntryName: renderEntryName,
        catalogLibraryNamespace: origin.catalogLibraryNamespace,
        catalogWidgetWireId: origin.catalogWidgetWireId,
        namedChildSlot: namedChildSlot,
        siblingOrdinal: siblingOrdinal,
      );
    }

    void visitValue(
      Object? value, {
      required String renderEntryName,
      required String? parentStructuralOccurrenceKey,
      required String namedChildSlot,
      required List<String> callPath,
    }) {
      switch (value) {
        case final fmt.ConstructorCall call:
          final location = _callLocation(renderEntryName, callPath);
          final reachable = _ReachableRfwCall(
            location: location,
            constructorName: call.name,
            constructorCall: call,
          );
          if (reachableCallsByLocation.putIfAbsent(location, () => reachable) !=
              reachable) {
            throw const FormatException(
              'RFW occurrence resolution repeated one call location',
            );
          }
          final origin = input.catalogConstructorForName(call.name);
          final localSymbol = input.localSymbolForName(call.name);
          final localOrigin = localSymbol?.generatedCatalogOrigin;
          final eligible = origin != null &&
              (localSymbol == null ||
                  (localOrigin != null && localOrigin.matches(origin)));
          var currentParent = parentStructuralOccurrenceKey;
          if (eligible) {
            if (occurrences.length == _kMaximumRfwCatalogOccurrenceCount) {
              throw const FormatException(
                'RFW occurrence resolution exceeded the route capacity',
              );
            }
            final descriptor = descriptorFor(
              origin,
              renderEntryName: renderEntryName,
              parentStructuralOccurrenceKey: parentStructuralOccurrenceKey,
              namedChildSlot: namedChildSlot,
            );
            final occurrence = RfwCatalogOccurrence._(
              descriptor: descriptor,
              constructorCall: call,
              handle: RfwCatalogOccurrenceHandle._(
                _handleValue(descriptor.structuralOccurrenceKey),
              ),
            );
            if (occurrencesByCall.putIfAbsent(call, () => occurrence) !=
                occurrence) {
              throw const FormatException(
                'RFW occurrence resolution repeated one constructor object',
              );
            }
            if (occurrenceLocations.putIfAbsent(
                  occurrence.handle,
                  () => location,
                ) !=
                location) {
              throw const FormatException(
                'RFW occurrence resolution repeated one occurrence handle',
              );
            }
            if (occurrencesByHandle.putIfAbsent(
                  occurrence.handle,
                  () => occurrence,
                ) !=
                occurrence) {
              throw const FormatException(
                'RFW occurrence resolution repeated one occurrence handle',
              );
            }
            occurrences.add(occurrence);
            currentParent = descriptor.structuralOccurrenceKey;
          }
          final arguments = call.arguments.entries.toList()
            ..sort((left, right) => left.key.compareTo(right.key));
          for (final argument in arguments) {
            visitValue(
              argument.value,
              renderEntryName: renderEntryName,
              parentStructuralOccurrenceKey: currentParent,
              namedChildSlot: 'argument:${argument.key}',
              callPath: [...callPath, 'argument:${argument.key}'],
            );
          }
          if (localSymbol != null && localOrigin == null) {
            reachableOrdinaryLocalNames.add(localSymbol.name);
          }
        case final fmt.EventHandler handler:
          final arguments = handler.eventArguments.entries.toList()
            ..sort((left, right) => left.key.compareTo(right.key));
          for (final argument in arguments) {
            visitValue(
              argument.value,
              renderEntryName: renderEntryName,
              parentStructuralOccurrenceKey: parentStructuralOccurrenceKey,
              namedChildSlot: 'event:${handler.eventName}:${argument.key}',
              callPath: [
                ...callPath,
                'event:${handler.eventName}:${argument.key}',
              ],
            );
          }
        case final fmt.SetStateHandler handler:
          visitValue(
            handler.value,
            renderEntryName: renderEntryName,
            parentStructuralOccurrenceKey: parentStructuralOccurrenceKey,
            namedChildSlot: '$namedChildSlot:set-state',
            callPath: [...callPath, 'set-state'],
          );
        case final fmt.WidgetBuilderDeclaration builder:
          visitValue(
            builder.widget,
            renderEntryName: renderEntryName,
            parentStructuralOccurrenceKey: parentStructuralOccurrenceKey,
            namedChildSlot: 'builder:${builder.argumentName}',
            callPath: [...callPath, 'builder:${builder.argumentName}'],
          );
        case final fmt.Loop loop:
          visitValue(
            loop.input,
            renderEntryName: renderEntryName,
            parentStructuralOccurrenceKey: parentStructuralOccurrenceKey,
            namedChildSlot: '$namedChildSlot:loop-input',
            callPath: [...callPath, 'loop-input'],
          );
          visitValue(
            loop.output,
            renderEntryName: renderEntryName,
            parentStructuralOccurrenceKey: parentStructuralOccurrenceKey,
            namedChildSlot: '$namedChildSlot:loop-output',
            callPath: [...callPath, 'loop-output'],
          );
        case final fmt.Switch switchNode:
          visitValue(
            switchNode.input,
            renderEntryName: renderEntryName,
            parentStructuralOccurrenceKey: parentStructuralOccurrenceKey,
            namedChildSlot: '$namedChildSlot:switch-input',
            callPath: [...callPath, 'switch-input'],
          );
          final outputs = switchNode.outputs.entries.toList()
            ..sort(
              (left, right) => '${left.key}'.compareTo('${right.key}'),
            );
          for (final output in outputs) {
            visitValue(
              output.value,
              renderEntryName: renderEntryName,
              parentStructuralOccurrenceKey: parentStructuralOccurrenceKey,
              namedChildSlot: '$namedChildSlot:switch-output:${output.key}',
              callPath: [...callPath, 'switch-output:${output.key}'],
            );
          }
        case final Map<Object?, Object?> map:
          final entries = map.entries.toList()
            ..sort((left, right) => '${left.key}'.compareTo('${right.key}'));
          for (final entry in entries) {
            visitValue(
              entry.value,
              renderEntryName: renderEntryName,
              parentStructuralOccurrenceKey: parentStructuralOccurrenceKey,
              namedChildSlot: '$namedChildSlot:map:${entry.key}',
              callPath: [...callPath, 'map:${entry.key}'],
            );
          }
        case final List<Object?> values:
          for (var index = 0; index < values.length; index += 1) {
            visitValue(
              values[index],
              renderEntryName: renderEntryName,
              parentStructuralOccurrenceKey: parentStructuralOccurrenceKey,
              namedChildSlot: '$namedChildSlot:list',
              callPath: [...callPath, 'list:$index'],
            );
          }
        default:
          return;
      }
    }

    final renderEntries = input.renderEntryNames.toList()..sort();
    for (final renderEntryName in renderEntries) {
      visitValue(
        widgetsByName[renderEntryName]!.root,
        renderEntryName: renderEntryName,
        parentStructuralOccurrenceKey: null,
        namedChildSlot: 'root',
        callPath: const ['root'],
      );
    }
    final traversedOrdinaryLocalBodies = <String>{...renderEntries};
    while (true) {
      final nextLocalNames = reachableOrdinaryLocalNames
          .where((name) => !traversedOrdinaryLocalBodies.contains(name))
          .toList()
        ..sort();
      if (nextLocalNames.isEmpty) break;
      final localName = nextLocalNames.first;
      final declaration = widgetsByName[localName];
      if (declaration == null) {
        throw FormatException(
          'A reachable RFW local declaration is absent: $localName',
        );
      }
      traversedOrdinaryLocalBodies.add(localName);
      final anchor = RfwCatalogOccurrenceLocalDeclarationAnchor._(
        localName: localName,
        structuralOccurrenceKey: _localDeclarationAnchorWitness(
          artifactProvenance: input.artifactProvenance,
          sourceDeclarationIdentity: input.sourceDeclarationIdentity,
          sourceLibraryIdentity: input.sourceLibraryIdentity,
          localName: localName,
        ),
      );
      localAnchorsByName[localName] = anchor;
      visitValue(
        declaration.root,
        renderEntryName: _localDeclarationEntryName(localName),
        parentStructuralOccurrenceKey: anchor.structuralOccurrenceKey,
        namedChildSlot: 'local-declaration:$localName',
        callPath: ['local:$localName', 'root'],
      );
    }
    occurrences.sort(
      (left, right) => left.descriptor.structuralOccurrenceKey.compareTo(
        right.descriptor.structuralOccurrenceKey,
      ),
    );
    return ResolvedRfwCatalogOccurrenceSet._(
      parsedLibrary: parsedLibrary,
      input: input,
      occurrences: occurrences,
      occurrencesByCall: occurrencesByCall,
      occurrencesByHandle: occurrencesByHandle,
      occurrenceLocations: occurrenceLocations,
      reachableCallsByLocation: reachableCallsByLocation,
      localDeclarationAnchors: localAnchorsByName.values.where(
        (anchor) => occurrences.any(
          (occurrence) =>
              occurrence.descriptor.parentStructuralOccurrenceKey ==
              anchor.structuralOccurrenceKey,
        ),
      ),
    );
  }

  ResolvedRfwCatalogOccurrenceSet._({
    required this.parsedLibrary,
    required this.input,
    required Iterable<RfwCatalogOccurrence> occurrences,
    required Map<fmt.ConstructorCall, RfwCatalogOccurrence> occurrencesByCall,
    required Map<RfwCatalogOccurrenceHandle, RfwCatalogOccurrence>
        occurrencesByHandle,
    required Map<RfwCatalogOccurrenceHandle, String> occurrenceLocations,
    required Map<String, _ReachableRfwCall> reachableCallsByLocation,
    required Iterable<RfwCatalogOccurrenceLocalDeclarationAnchor>
        localDeclarationAnchors,
  })  : occurrences = List.unmodifiable(occurrences),
        _occurrencesByCall = UnmodifiableMapView(occurrencesByCall),
        _occurrencesByHandle = UnmodifiableMapView(occurrencesByHandle),
        _occurrenceLocations = UnmodifiableMapView(occurrenceLocations),
        _reachableCallsByLocation =
            UnmodifiableMapView(reachableCallsByLocation),
        localDeclarationAnchors = List.unmodifiable(localDeclarationAnchors);

  /// Parsed pre-encode library that owns [occurrences] object identities.
  final fmt.RemoteWidgetLibrary parsedLibrary;

  /// Closed resolution evidence used exactly once for [parsedLibrary].
  final RfwCatalogOccurrenceResolutionInput input;

  /// Every resolved catalog occurrence reachable from an explicit render root.
  final List<RfwCatalogOccurrence> occurrences;

  final Map<fmt.ConstructorCall, RfwCatalogOccurrence> _occurrencesByCall;
  final Map<RfwCatalogOccurrenceHandle, RfwCatalogOccurrence>
      _occurrencesByHandle;
  final Map<RfwCatalogOccurrenceHandle, String> _occurrenceLocations;
  final Map<String, _ReachableRfwCall> _reachableCallsByLocation;

  /// Reachable ordinary local-body anchors used by resolved occurrences.
  final List<RfwCatalogOccurrenceLocalDeclarationAnchor>
      localDeclarationAnchors;

  /// Stable non-occurrence anchor used by a compiler continuity ledger.
  String get artifactAnchorStructuralOccurrenceKey => _stableKey(
        'rfw.catalog.artifact-anchor.v1',
        <String, Object?>{
          'artifactProvenance': input.artifactProvenance,
          'sourceDeclarationIdentity': input.sourceDeclarationIdentity,
          'sourceLibraryIdentity': input.sourceLibraryIdentity,
        },
      );

  /// Returns an occurrence by exact parsed source call object.
  RfwCatalogOccurrence? occurrenceForCall(
    fmt.ConstructorCall constructorCall,
  ) =>
      _occurrencesByCall[constructorCall];

  /// Returns an occurrence by its opaque value-stable handle.
  RfwCatalogOccurrence? occurrenceForHandle(
    RfwCatalogOccurrenceHandle handle,
  ) =>
      _occurrencesByHandle[handle];

  /// Rebinds this frozen set to [finalLibrary] without resolving eligibility.
  ResolvedRfwCatalogOccurrenceRebinding rebindFinalLibrary(
    fmt.RemoteWidgetLibrary finalLibrary,
  ) {
    if (!_sameImportClosure(parsedLibrary, finalLibrary)) {
      throw const FormatException(
        'Final RFW import closure does not match the frozen occurrence set',
      );
    }
    final finalCalls = _reachableCalls(finalLibrary, input);
    if (finalCalls.length != _reachableCallsByLocation.length ||
        !finalCalls.keys.toSet().containsAll(_reachableCallsByLocation.keys) ||
        !_reachableCallsByLocation.keys.toSet().containsAll(finalCalls.keys)) {
      throw const FormatException(
        'Final RFW constructor topology does not match the frozen '
        'occurrence set',
      );
    }
    for (final entry in _reachableCallsByLocation.entries) {
      final rebound = finalCalls[entry.key]!;
      if (rebound.constructorName != entry.value.constructorName) {
        throw const FormatException(
          'Final RFW constructor topology changed one resolved call',
        );
      }
    }

    final bindings = <RfwCatalogOccurrenceFinalBinding>[];
    final bindingsByCall =
        Map<fmt.ConstructorCall, RfwCatalogOccurrenceFinalBinding>.identity();
    final bindingsByHandle =
        <RfwCatalogOccurrenceHandle, RfwCatalogOccurrenceFinalBinding>{};
    for (final occurrence in occurrences) {
      final location = _occurrenceLocations[occurrence.handle];
      final rebound = location == null ? null : finalCalls[location];
      if (rebound == null) {
        throw const FormatException(
          'Final RFW library omitted one resolved catalog occurrence',
        );
      }
      final binding = RfwCatalogOccurrenceFinalBinding._(
        occurrence: occurrence,
        constructorCall: rebound.constructorCall,
      );
      if (bindingsByCall.putIfAbsent(binding.constructorCall, () => binding) !=
              binding ||
          bindingsByHandle.putIfAbsent(binding.handle, () => binding) !=
              binding) {
        throw const FormatException(
          'Final RFW occurrence bindings must remain one-to-one',
        );
      }
      bindings.add(binding);
    }
    return ResolvedRfwCatalogOccurrenceRebinding._(
      finalLibrary: finalLibrary,
      occurrenceSet: this,
      bindings: bindings,
      bindingsByCall: bindingsByCall,
      bindingsByHandle: bindingsByHandle,
    );
  }
}

bool _sameImportClosure(
  fmt.RemoteWidgetLibrary first,
  fmt.RemoteWidgetLibrary second,
) {
  Set<String> normalized(fmt.RemoteWidgetLibrary library) => {
        for (final entry in library.imports) jsonEncode(entry.name.parts),
      };
  final firstClosure = normalized(first);
  final secondClosure = normalized(second);
  return firstClosure.length == secondClosure.length &&
      firstClosure.containsAll(secondClosure);
}

Map<String, _ReachableRfwCall> _reachableCalls(
  fmt.RemoteWidgetLibrary library,
  RfwCatalogOccurrenceResolutionInput input,
) {
  final widgetsByName = <String, fmt.WidgetDeclaration>{
    for (final widget in library.widgets) widget.name: widget,
  };
  final inputLocalNames =
      input.localSymbols.map((symbol) => symbol.name).toSet();
  if (widgetsByName.length != library.widgets.length ||
      widgetsByName.length != inputLocalNames.length ||
      !widgetsByName.keys.every(inputLocalNames.contains) ||
      !input.renderEntryNames.every(widgetsByName.containsKey)) {
    throw const FormatException(
      'Final RFW local declarations do not match the frozen occurrence set',
    );
  }
  final calls = <String, _ReachableRfwCall>{};
  final reachableOrdinaryLocalNames = <String>{};

  void visitValue(
    Object? value, {
    required String renderEntryName,
    required List<String> callPath,
  }) {
    switch (value) {
      case final fmt.ConstructorCall call:
        final location = _callLocation(renderEntryName, callPath);
        final reachable = _ReachableRfwCall(
          location: location,
          constructorName: call.name,
          constructorCall: call,
        );
        if (calls.putIfAbsent(location, () => reachable) != reachable) {
          throw const FormatException('Final RFW call location was repeated');
        }
        final arguments = call.arguments.entries.toList()
          ..sort((left, right) => left.key.compareTo(right.key));
        for (final argument in arguments) {
          visitValue(
            argument.value,
            renderEntryName: renderEntryName,
            callPath: [...callPath, 'argument:${argument.key}'],
          );
        }
        final localSymbol = input.localSymbolForName(call.name);
        if (localSymbol != null && localSymbol.generatedCatalogOrigin == null) {
          reachableOrdinaryLocalNames.add(localSymbol.name);
        }
      case final fmt.EventHandler handler:
        final arguments = handler.eventArguments.entries.toList()
          ..sort((left, right) => left.key.compareTo(right.key));
        for (final argument in arguments) {
          visitValue(
            argument.value,
            renderEntryName: renderEntryName,
            callPath: [
              ...callPath,
              'event:${handler.eventName}:${argument.key}',
            ],
          );
        }
      case final fmt.SetStateHandler handler:
        visitValue(
          handler.value,
          renderEntryName: renderEntryName,
          callPath: [...callPath, 'set-state'],
        );
      case final fmt.WidgetBuilderDeclaration builder:
        visitValue(
          builder.widget,
          renderEntryName: renderEntryName,
          callPath: [...callPath, 'builder:${builder.argumentName}'],
        );
      case final fmt.Loop loop:
        visitValue(
          loop.input,
          renderEntryName: renderEntryName,
          callPath: [...callPath, 'loop-input'],
        );
        visitValue(
          loop.output,
          renderEntryName: renderEntryName,
          callPath: [...callPath, 'loop-output'],
        );
      case final fmt.Switch switchNode:
        visitValue(
          switchNode.input,
          renderEntryName: renderEntryName,
          callPath: [...callPath, 'switch-input'],
        );
        final outputs = switchNode.outputs.entries.toList()
          ..sort((left, right) => '${left.key}'.compareTo('${right.key}'));
        for (final output in outputs) {
          visitValue(
            output.value,
            renderEntryName: renderEntryName,
            callPath: [...callPath, 'switch-output:${output.key}'],
          );
        }
      case final Map<Object?, Object?> map:
        final entries = map.entries.toList()
          ..sort((left, right) => '${left.key}'.compareTo('${right.key}'));
        for (final entry in entries) {
          visitValue(
            entry.value,
            renderEntryName: renderEntryName,
            callPath: [...callPath, 'map:${entry.key}'],
          );
        }
      case final List<Object?> values:
        for (var index = 0; index < values.length; index += 1) {
          visitValue(
            values[index],
            renderEntryName: renderEntryName,
            callPath: [...callPath, 'list:$index'],
          );
        }
      default:
        return;
    }
  }

  final roots = input.renderEntryNames.toList()..sort();
  for (final root in roots) {
    visitValue(
      widgetsByName[root]!.root,
      renderEntryName: root,
      callPath: const ['root'],
    );
  }
  final traversedOrdinaryLocalBodies = <String>{...roots};
  while (true) {
    final nextLocalNames = reachableOrdinaryLocalNames
        .where((name) => !traversedOrdinaryLocalBodies.contains(name))
        .toList()
      ..sort();
    if (nextLocalNames.isEmpty) break;
    final localName = nextLocalNames.first;
    final declaration = widgetsByName[localName];
    if (declaration == null) {
      throw FormatException(
        'Final RFW library is missing reachable local declaration $localName',
      );
    }
    traversedOrdinaryLocalBodies.add(localName);
    visitValue(
      declaration.root,
      renderEntryName: _localDeclarationEntryName(localName),
      callPath: ['local:$localName', 'root'],
    );
  }
  return calls;
}

String _renderEntryWitness({
  required String sourceLibraryIdentity,
  required String sourceDeclarationIdentity,
  required String renderEntryName,
}) =>
    _stableKey(
      'rfw.catalog.render-entry.v1',
      <String, Object?>{
        'renderEntryName': renderEntryName,
        'sourceDeclarationIdentity': sourceDeclarationIdentity,
        'sourceLibraryIdentity': sourceLibraryIdentity,
      },
    );

String _localDeclarationEntryName(String localName) => 'local:$localName';

String _localDeclarationAnchorWitness({
  required String artifactProvenance,
  required String sourceDeclarationIdentity,
  required String sourceLibraryIdentity,
  required String localName,
}) =>
    _stableKey(
      'rfw.catalog.local-declaration-anchor.v1',
      <String, Object?>{
        'artifactProvenance': artifactProvenance,
        'localName': localName,
        'sourceDeclarationIdentity': sourceDeclarationIdentity,
        'sourceLibraryIdentity': sourceLibraryIdentity,
      },
    );

String _callLocation(String renderEntryName, List<String> callPath) =>
    _stableKey(
      'rfw.catalog.call-location.v1',
      <String, Object?>{
        'callPath': callPath,
        'renderEntryName': renderEntryName,
      },
    );

String _stableKey(String role, Map<String, Object?> value) {
  final bytes = utf8.encode('$role\u0000${jsonEncode(value)}');
  return '$role.${crypto.sha256.convert(bytes)}';
}

String _handleValue(String structuralOccurrenceKey) => _stableKey(
      'rfw.catalog.occurrence-handle.v1',
      <String, Object?>{
        'structuralOccurrenceKey': structuralOccurrenceKey,
      },
    );

final class _ReachableRfwCall {
  const _ReachableRfwCall({
    required this.location,
    required this.constructorName,
    required this.constructorCall,
  });

  final String location;
  final String constructorName;
  final fmt.ConstructorCall constructorCall;
}
