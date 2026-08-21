import 'package:restage_codegen/src/measurement/measurement_compiler_input.dart';
import 'package:restage_codegen/src/measurement/measurement_source_discovery.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

/// One exact source-locator to code-identity ledger binding.
///
/// The binding is supplied by the compiler-maintained ledger; source discovery
/// never mints a code identity from source shape, text, keys, or offsets.
final class MeasurementDiscoveredNodeBinding {
  /// Creates one exact discovered-node ledger binding.
  const MeasurementDiscoveredNodeBinding({
    required this.structuralOccurrenceKey,
    required this.codeIdentityId,
  });

  /// Deterministic source locator returned by discovery.
  final String structuralOccurrenceKey;

  /// Existing code identity selected by the compiler ledger.
  final CodeIdentityId codeIdentityId;
}

/// Complete source-discovery material supplied to the compiler boundary.
///
/// The [boundaryInput] remains the only source of graph, manifest,
/// publication, and lineage data. This adapter validates that its ordinary
/// nodes and callback slots are exactly the static source closure before the
/// unchanged producer is invoked.
final class MeasurementDiscoveredBoundaryInput {
  /// Creates a source-backed compiler-boundary input.
  MeasurementDiscoveredBoundaryInput({
    required this.boundaryInput,
    required this.discovery,
    required Iterable<MeasurementDiscoveredNodeBinding> nodeBindings,
  }) : nodeBindings = List.unmodifiable(nodeBindings);

  /// Fully resolved producer input.
  final MeasurementCompilerBoundaryInput boundaryInput;

  /// Complete static source discovery for this boundary root.
  final MeasurementSourceDiscoveryResult discovery;

  /// Exact structural-node bindings selected by the compiler ledger.
  final List<MeasurementDiscoveredNodeBinding> nodeBindings;
}

/// Validates source discovery against the existing compiler-boundary input.
///
/// It intentionally does not produce bytes itself. The caller delegates to
/// `MeasurementCompilerBoundary` only after this exact static join holds.
abstract final class MeasurementDiscoveredBoundaryAdapter {
  /// Rejects missing, extra, duplicate, or mismatched source/ledger joins.
  static void validate(MeasurementDiscoveredBoundaryInput input) {
    if (input.discovery.disposition !=
        MeasurementSourceDiscoveryDisposition.accepted) {
      throw ArgumentError(
        'A rejected source discovery cannot enter the compiler boundary',
      );
    }

    final discoveredNodes = _uniqueBy(
      input.discovery.nodes,
      (node) => node.structuralOccurrenceKey,
      'discovered source node locators',
    );
    final bindings = _uniqueBy(
      input.nodeBindings,
      (binding) => binding.structuralOccurrenceKey,
      'discovered source node bindings',
    );
    _requireExactKeys(
      expected: discoveredNodes.keys,
      actual: bindings.keys,
      label: 'discovered source nodes and code-identity bindings',
    );

    final bindingsByCodeIdentity = _uniqueBy(
      input.nodeBindings,
      (binding) => binding.codeIdentityId.value,
      'code identities selected for discovered source nodes',
    );
    final boundaryNodes = _uniqueBy(
      input.boundaryInput.nodes,
      (node) => node.codeIdentityId.value,
      'compiler boundary nodes',
    );
    _requireExactKeys(
      expected: bindingsByCodeIdentity.keys,
      actual: boundaryNodes.keys,
      label: 'discovered source bindings and compiler boundary nodes',
    );

    for (final entry in discoveredNodes.entries) {
      final binding = bindings[entry.key]!;
      final boundaryNode = boundaryNodes[binding.codeIdentityId.value]!;
      final parentKey = entry.value.parentStructuralOccurrenceKey;
      final expectedParentCodeIdentity =
          parentKey == null ? null : bindings[parentKey]?.codeIdentityId;
      if (parentKey != null && expectedParentCodeIdentity == null) {
        throw ArgumentError(
          'Every discovered source parent must have one ledger binding',
        );
      }
      if (boundaryNode.parentCodeIdentityId != expectedParentCodeIdentity) {
        throw ArgumentError(
          'Compiler node ancestry must exactly match discovered source '
          'ancestry',
        );
      }
    }

    final discoveredEvents = _uniqueBy(
      input.discovery.events,
      _discoveredEventKey,
      'discovered source callback slots',
    );
    final expectedBoundaryEvents = <String>{};
    for (final event in discoveredEvents.values) {
      final binding = bindings[event.node.structuralOccurrenceKey];
      if (binding == null) {
        throw ArgumentError(
          'Every discovered callback slot must join one ledger-backed node',
        );
      }
      expectedBoundaryEvents.add(
        _boundaryEventKey(
          codeIdentityId: binding.codeIdentityId,
          resolvedIdentity: event.resolvedEvent.resolvedSemanticIdentity,
        ),
      );
    }
    final actualBoundaryEvents = <String>{
      for (final event in input.boundaryInput.events)
        _boundaryEventKey(
          codeIdentityId: event.nodeCodeIdentityId,
          resolvedIdentity: event.resolvedEvent.resolvedSemanticIdentity,
        ),
    };
    if (actualBoundaryEvents.length != input.boundaryInput.events.length) {
      throw ArgumentError('Compiler boundary callback slots must be unique');
    }
    _requireExactKeys(
      expected: expectedBoundaryEvents,
      actual: actualBoundaryEvents,
      label: 'discovered callback slots and compiler boundary events',
    );
  }
}

String _discoveredEventKey(MeasurementDiscoveredEvent event) =>
    '${event.node.structuralOccurrenceKey}\u0000'
    '${event.resolvedEvent.resolvedSemanticIdentity}';

String _boundaryEventKey({
  required CodeIdentityId codeIdentityId,
  required String resolvedIdentity,
}) =>
    '${codeIdentityId.value}\u0000$resolvedIdentity';

Map<String, T> _uniqueBy<T>(
  Iterable<T> values,
  String Function(T value) keyOf,
  String label,
) {
  final result = <String, T>{};
  for (final value in values) {
    final key = keyOf(value);
    if (result.containsKey(key)) {
      throw ArgumentError('Duplicate $label claim: $key');
    }
    result[key] = value;
  }
  return result;
}

void _requireExactKeys({
  required Iterable<String> expected,
  required Iterable<String> actual,
  required String label,
}) {
  final expectedSet = expected.toSet();
  final actualSet = actual.toSet();
  final missing = expectedSet.difference(actualSet);
  final extra = actualSet.difference(expectedSet);
  if (missing.isEmpty && extra.isEmpty) return;
  throw ArgumentError(
    '$label must have exact keys; missing=${missing.toList()..sort()} '
    'extra=${extra.toList()..sort()}',
  );
}
