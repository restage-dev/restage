import 'dart:collection';

import 'package:collection/collection.dart';
import 'package:restage_codegen/src/a2ui/a2ui_schema_node.dart';

/// Canonical named definitions discovered across one schema document.
///
/// Every consumer receives the same reconciled definition. Occurrence
/// descriptions never participate in definition conflicts; canonical type
/// descriptions and structure do.
final class A2uiDefinitionRegistry {
  /// Discovers and reconciles every named object or dormant union reachable
  /// from [roots].
  A2uiDefinitionRegistry(Iterable<A2uiSchemaNode> roots) {
    for (final root in roots) {
      _visit(root, const []);
    }
    for (final entry in _mutableDefinitions.entries) {
      final id = entry.key;
      if (_description(_definitionDescription(entry.value)) != null &&
          _occurrenceDescriptionIds.contains(id)) {
        _descriptionSeparationTargets.add(id);
      }
      if (_hasCanonicalDocumentation(
        entry.value,
        atDefinitionRoot: true,
      )) {
        _canonicalOrderTargets.addAll(_ancestorIdsByDefinition[id] ?? {id});
      }
    }
    final ordered = SplayTreeMap<String, A2uiSchemaNode>.from({
      for (final entry in _mutableDefinitions.entries)
        entry.key: _orderedDefinition(
          entry.value,
          canonicalOrder: _canonicalOrderTargets.contains(entry.key),
        ),
    });
    definitions = Map.unmodifiable(ordered);
    hoistTargets = Set.unmodifiable({
      ..._referenceTargets,
      ..._descriptionSeparationTargets,
    });
    canonicalOrderTargets = Set.unmodifiable(_canonicalOrderTargets);
  }

  final Map<String, A2uiSchemaNode> _mutableDefinitions = {};
  final Set<String> _referenceTargets = {};
  final Set<String> _occurrenceDescriptionIds = {};
  final Set<String> _descriptionSeparationTargets = {};
  final Set<String> _canonicalOrderTargets = {};
  final Map<String, Set<String>> _ancestorIdsByDefinition = {};

  /// Canonical named objects and dormant unions in stable id order.
  late final Map<String, A2uiSchemaNode> definitions;

  /// Definitions that must be hoisted to preserve references or to keep an
  /// occurrence description separate from canonical type documentation.
  late final Set<String> hoistTargets;

  /// Named objects whose own field traversal is canonicalized.
  ///
  /// The set contains a description-separation target and its named object
  /// ancestors, never unrelated definitions or the anonymous widget root.
  late final Set<String> canonicalOrderTargets;

  /// Returns the canonical definition for [id], failing loud when absent.
  A2uiSchemaNode definitionFor(String id) {
    final definition = definitions[id];
    if (definition == null) {
      throw StateError(
        'A2UI projection: a reference to "$id" has no named definition in '
        'the schema document.',
      );
    }
    return definition;
  }

  void _visit(A2uiSchemaNode node, List<String> ancestorIds) {
    switch (node) {
      case ScalarNode() || EnumNode():
        break;
      case ListNode(:final element):
        _visit(element, ancestorIds);
      case MapNode(:final valueType):
        _visit(valueType, ancestorIds);
      case ObjectNode(:final fields, :final defId):
        final descendants =
            defId == null ? ancestorIds : <String>[...ancestorIds, defId];
        if (defId != null) {
          _register(defId, node);
          _ancestorIdsByDefinition
              .putIfAbsent(defId, () => <String>{})
              .addAll(descendants);
          if (_description(node.occurrenceDescription) != null) {
            _occurrenceDescriptionIds.add(defId);
          }
        }
        for (final field in fields.values) {
          _visit(field, descendants);
        }
      case RefNode(:final defId):
        _referenceTargets.add(defId);
      case UnionNode(:final variants, :final defId):
        final descendants =
            defId == null ? ancestorIds : <String>[...ancestorIds, defId];
        if (defId != null) {
          _register(defId, node);
          _ancestorIdsByDefinition
              .putIfAbsent(defId, () => <String>{})
              .addAll(descendants);
          if (_description(node.occurrenceDescription) != null) {
            _occurrenceDescriptionIds.add(defId);
          }
        }
        for (final variant in variants) {
          _visit(variant, descendants);
        }
    }
  }

  void _register(String id, A2uiSchemaNode candidate) {
    final canonicalCandidate = _canonicalDefinition(candidate, id);
    final existing = _mutableDefinitions[id];
    if (existing == null) {
      _mutableDefinitions[id] = canonicalCandidate;
      return;
    }
    if (!_sameDefinitionStructure(existing, canonicalCandidate)) {
      throw StateError('Conflicting canonical structure for "$id".');
    }
    final canonicalOrder =
        _hasCanonicalDocumentation(existing, atDefinitionRoot: true) ||
            _hasCanonicalDocumentation(
              canonicalCandidate,
              atDefinitionRoot: true,
            );
    _mutableDefinitions[id] = _mergeDefinition(
      _orderedDefinition(
        existing,
        canonicalOrder: canonicalOrder,
        documentationPeer: canonicalCandidate,
      ),
      _orderedDefinition(
        canonicalCandidate,
        canonicalOrder: canonicalOrder,
        documentationPeer: existing,
      ),
      id,
    );
  }

  A2uiSchemaNode _canonicalDefinition(A2uiSchemaNode node, String id) {
    if (node is ObjectNode) {
      return ObjectNode(
        fields: {
          for (final entry in node.fields.entries)
            entry.key: _canonicalizeNode(entry.value, '$id.${entry.key}'),
        },
        required: node.required,
        defId: node.defId,
        construction: node.construction,
        definitionDescription: _description(node.definitionDescription),
      );
    }
    if (node is UnionNode) {
      return UnionNode(
        variants: [
          for (var index = 0; index < node.variants.length; index++)
            _canonicalizeNode(node.variants[index], '$id.variants[$index]'),
        ],
        discriminatorField: node.discriminatorField,
        defId: node.defId,
        definitionDescription: _description(node.definitionDescription),
      );
    }
    throw StateError('A2UI registry: "$id" is not a named definition.');
  }

  A2uiSchemaNode _mergeDefinition(
    A2uiSchemaNode existing,
    A2uiSchemaNode candidate,
    String id,
  ) {
    if (existing is ObjectNode && candidate is ObjectNode) {
      return ObjectNode(
        fields: {
          for (final entry in existing.fields.entries)
            entry.key: _mergeNode(
              entry.value,
              candidate.fields[entry.key]!,
              '$id.${entry.key}',
            ),
        },
        required: existing.required,
        defId: existing.defId,
        construction: existing.construction,
        definitionDescription: _mergeDefinitionDescription(
          existing.definitionDescription,
          candidate.definitionDescription,
          id,
        ),
      );
    }
    if (existing is UnionNode && candidate is UnionNode) {
      return UnionNode(
        variants: [
          for (var index = 0; index < existing.variants.length; index++)
            _mergeNode(
              existing.variants[index],
              candidate.variants[index],
              '$id.variants[$index]',
            ),
        ],
        discriminatorField: existing.discriminatorField,
        defId: existing.defId,
        definitionDescription: _mergeDefinitionDescription(
          existing.definitionDescription,
          candidate.definitionDescription,
          id,
        ),
      );
    }
    throw StateError('Conflicting canonical structure for "$id".');
  }

  A2uiSchemaNode _orderedDefinition(
    A2uiSchemaNode node, {
    required bool canonicalOrder,
    A2uiSchemaNode? documentationPeer,
  }) =>
      _orderedCanonicalNode(
        node,
        documentationPeer: documentationPeer,
        atDefinitionRoot: true,
        insideDocumentedSubtree: false,
        forceCurrentObjectOrder: canonicalOrder,
      );
}

String? _definitionDescription(A2uiSchemaNode node) => switch (node) {
      ObjectNode(:final definitionDescription) => definitionDescription,
      UnionNode(:final definitionDescription) => definitionDescription,
      _ => null,
    };

/// Whether a canonical definition contains documentation that participates in
/// registry reconciliation. The named definition root's occurrence text is a
/// use-site fact and is deliberately excluded; nested occurrence text and
/// root/nested canonical definition text are mergeable definition facts.
bool _hasCanonicalDocumentation(
  A2uiSchemaNode node, {
  required bool atDefinitionRoot,
}) {
  final hasOccurrence =
      !atDefinitionRoot && _description(node.occurrenceDescription) != null;
  return switch (node) {
    ScalarNode() || EnumNode() || RefNode() => hasOccurrence,
    ListNode(:final element) => hasOccurrence ||
        _hasCanonicalDocumentation(element, atDefinitionRoot: false),
    MapNode(:final valueType) => hasOccurrence ||
        _hasCanonicalDocumentation(valueType, atDefinitionRoot: false),
    ObjectNode(:final fields, :final definitionDescription) => hasOccurrence ||
        _description(definitionDescription) != null ||
        fields.values.any(
          (field) => _hasCanonicalDocumentation(
            field,
            atDefinitionRoot: false,
          ),
        ),
    UnionNode(:final variants, :final definitionDescription) => hasOccurrence ||
        _description(definitionDescription) != null ||
        variants.any(
          (variant) => _hasCanonicalDocumentation(
            variant,
            atDefinitionRoot: false,
          ),
        ),
  };
}

bool _hasOwnCanonicalDocumentation(
  A2uiSchemaNode node, {
  required bool atDefinitionRoot,
}) {
  if (!atDefinitionRoot && _description(node.occurrenceDescription) != null) {
    return true;
  }
  return _description(_definitionDescription(node)) != null;
}

/// Recursively orders only documented object subtrees and the object ancestors
/// on the path to them. Once a node itself carries canonical documentation,
/// its descendant objects remain inside that canonical context. Unrelated
/// description-free sibling subtrees keep their authored traversal order.
A2uiSchemaNode _orderedCanonicalNode(
  A2uiSchemaNode node, {
  required A2uiSchemaNode? documentationPeer,
  required bool atDefinitionRoot,
  required bool insideDocumentedSubtree,
  required bool forceCurrentObjectOrder,
}) {
  final ownDocumentation = _hasOwnCanonicalDocumentation(
        node,
        atDefinitionRoot: atDefinitionRoot,
      ) ||
      (documentationPeer != null &&
          _hasOwnCanonicalDocumentation(
            documentationPeer,
            atDefinitionRoot: atDefinitionRoot,
          ));
  final descendantContext = insideDocumentedSubtree || ownDocumentation;

  switch (node) {
    case ScalarNode() || EnumNode() || RefNode():
      return node;
    case ListNode(
        :final element,
        :final occurrenceDescription,
        :final nullable,
      ):
      final peer = documentationPeer is ListNode ? documentationPeer : null;
      return ListNode(
        element: _orderedCanonicalNode(
          element,
          documentationPeer: peer?.element,
          atDefinitionRoot: false,
          insideDocumentedSubtree: descendantContext,
          forceCurrentObjectOrder: false,
        ),
        occurrenceDescription: occurrenceDescription,
        nullable: nullable,
      );
    case MapNode(
        :final valueType,
        :final occurrenceDescription,
        :final nullable,
      ):
      final peer = documentationPeer is MapNode ? documentationPeer : null;
      return MapNode(
        valueType: _orderedCanonicalNode(
          valueType,
          documentationPeer: peer?.valueType,
          atDefinitionRoot: false,
          insideDocumentedSubtree: descendantContext,
          forceCurrentObjectOrder: false,
        ),
        occurrenceDescription: occurrenceDescription,
        nullable: nullable,
      );
    case ObjectNode(
        :final fields,
        :final required,
        :final defId,
        :final construction,
        :final definitionDescription,
        :final occurrenceDescription,
        :final nullable,
      ):
      final peer = documentationPeer is ObjectNode ? documentationPeer : null;
      final containsDocumentation = _hasCanonicalDocumentation(
            node,
            atDefinitionRoot: atDefinitionRoot,
          ) ||
          (peer != null &&
              _hasCanonicalDocumentation(
                peer,
                atDefinitionRoot: atDefinitionRoot,
              ));
      final canonicalOrder = forceCurrentObjectOrder ||
          insideDocumentedSubtree ||
          containsDocumentation;
      final fieldNames = fields.keys.toList();
      final requiredNames = required.toList();
      if (canonicalOrder) {
        fieldNames.sort();
        requiredNames.sort();
      }
      return ObjectNode(
        fields: {
          for (final name in fieldNames)
            name: _orderedCanonicalNode(
              fields[name]!,
              documentationPeer: peer?.fields[name],
              atDefinitionRoot: false,
              insideDocumentedSubtree: descendantContext,
              forceCurrentObjectOrder: false,
            ),
        },
        required: requiredNames.toSet(),
        defId: defId,
        construction: construction,
        definitionDescription: definitionDescription,
        occurrenceDescription: occurrenceDescription,
        nullable: nullable,
      );
    case UnionNode(
        :final variants,
        :final discriminatorField,
        :final defId,
        :final definitionDescription,
        :final occurrenceDescription,
        :final nullable,
      ):
      final peer = documentationPeer is UnionNode ? documentationPeer : null;
      return UnionNode(
        variants: [
          for (var index = 0; index < variants.length; index++)
            _orderedCanonicalNode(
              variants[index],
              documentationPeer: peer?.variants[index],
              atDefinitionRoot: false,
              insideDocumentedSubtree: descendantContext,
              forceCurrentObjectOrder: false,
            ),
        ],
        discriminatorField: discriminatorField,
        defId: defId,
        definitionDescription: definitionDescription,
        occurrenceDescription: occurrenceDescription,
        nullable: nullable,
      );
  }
}

String? _description(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String? _mergeDefinitionDescription(
  String? existing,
  String? candidate,
  String id,
) {
  final left = _description(existing);
  final right = _description(candidate);
  if (left != null && right != null && left != right) {
    throw StateError('Conflicting canonical description for "$id".');
  }
  return left ?? right;
}

String? _mergeMemberDescription(
  String? existing,
  String? candidate,
  String path,
) {
  final left = _description(existing);
  final right = _description(candidate);
  if (left != null && right != null && left != right) {
    throw StateError(
      'Conflicting canonical member description for "$path".',
    );
  }
  return left ?? right;
}

A2uiSchemaNode _canonicalizeNode(A2uiSchemaNode node, String path) {
  switch (node) {
    case ScalarNode(
        :final type,
        :final preserveNumericRuntimeType,
        :final occurrenceDescription,
        :final nullable,
      ):
      return ScalarNode(
        type,
        preserveNumericRuntimeType: preserveNumericRuntimeType,
        occurrenceDescription: _description(occurrenceDescription),
        nullable: nullable,
      );
    case EnumNode(
        :final members,
        :final dartTypeName,
        :final libraryUri,
        :final occurrenceDescription,
        :final nullable,
      ):
      return EnumNode(
        members: members,
        dartTypeName: dartTypeName,
        libraryUri: libraryUri,
        occurrenceDescription: _description(occurrenceDescription),
        nullable: nullable,
      );
    case ListNode(
        :final element,
        :final occurrenceDescription,
        :final nullable,
      ):
      return ListNode(
        element: _canonicalizeNode(element, '$path[]'),
        occurrenceDescription: _description(occurrenceDescription),
        nullable: nullable,
      );
    case MapNode(
        :final valueType,
        :final occurrenceDescription,
        :final nullable,
      ):
      return MapNode(
        valueType: _canonicalizeNode(valueType, '$path{}'),
        occurrenceDescription: _description(occurrenceDescription),
        nullable: nullable,
      );
    case ObjectNode(
        :final fields,
        :final required,
        :final defId,
        :final construction,
        :final definitionDescription,
        :final occurrenceDescription,
        :final nullable,
      ):
      return ObjectNode(
        fields: {
          for (final entry in fields.entries)
            entry.key: _canonicalizeNode(
              entry.value,
              '$path.${entry.key}',
            ),
        },
        required: required,
        defId: defId,
        construction: construction,
        definitionDescription: _description(definitionDescription),
        occurrenceDescription: _description(occurrenceDescription),
        nullable: nullable,
      );
    case RefNode(
        :final defId,
        :final occurrenceDescription,
        :final nullable,
      ):
      return RefNode(
        defId,
        occurrenceDescription: _description(occurrenceDescription),
        nullable: nullable,
      );
    case UnionNode(
        :final variants,
        :final discriminatorField,
        :final defId,
        :final definitionDescription,
        :final occurrenceDescription,
        :final nullable,
      ):
      return UnionNode(
        variants: [
          for (var index = 0; index < variants.length; index++)
            _canonicalizeNode(variants[index], '$path.variants[$index]'),
        ],
        discriminatorField: discriminatorField,
        defId: defId,
        definitionDescription: _description(definitionDescription),
        occurrenceDescription: _description(occurrenceDescription),
        nullable: nullable,
      );
  }
}

A2uiSchemaNode _mergeNode(
  A2uiSchemaNode existing,
  A2uiSchemaNode candidate,
  String path,
) {
  switch (existing) {
    case ScalarNode(
        :final type,
        :final preserveNumericRuntimeType,
        :final occurrenceDescription,
        :final nullable,
      ):
      final other = candidate as ScalarNode;
      return ScalarNode(
        type,
        preserveNumericRuntimeType: preserveNumericRuntimeType,
        occurrenceDescription: _mergeMemberDescription(
          occurrenceDescription,
          other.occurrenceDescription,
          path,
        ),
        nullable: nullable,
      );
    case EnumNode(
        :final members,
        :final dartTypeName,
        :final libraryUri,
        :final occurrenceDescription,
        :final nullable,
      ):
      final other = candidate as EnumNode;
      return EnumNode(
        members: members,
        dartTypeName: dartTypeName,
        libraryUri: libraryUri,
        occurrenceDescription: _mergeMemberDescription(
          occurrenceDescription,
          other.occurrenceDescription,
          path,
        ),
        nullable: nullable,
      );
    case ListNode(
        :final element,
        :final occurrenceDescription,
        :final nullable,
      ):
      final other = candidate as ListNode;
      return ListNode(
        element: _mergeNode(element, other.element, '$path[]'),
        occurrenceDescription: _mergeMemberDescription(
          occurrenceDescription,
          other.occurrenceDescription,
          path,
        ),
        nullable: nullable,
      );
    case MapNode(
        :final valueType,
        :final occurrenceDescription,
        :final nullable,
      ):
      final other = candidate as MapNode;
      return MapNode(
        valueType: _mergeNode(valueType, other.valueType, '$path{}'),
        occurrenceDescription: _mergeMemberDescription(
          occurrenceDescription,
          other.occurrenceDescription,
          path,
        ),
        nullable: nullable,
      );
    case ObjectNode(
        :final fields,
        :final required,
        :final defId,
        :final construction,
        :final definitionDescription,
        :final occurrenceDescription,
        :final nullable,
      ):
      final other = candidate as ObjectNode;
      return ObjectNode(
        fields: {
          for (final entry in fields.entries)
            entry.key: _mergeNode(
              entry.value,
              other.fields[entry.key]!,
              '$path.${entry.key}',
            ),
        },
        required: required,
        defId: defId,
        construction: construction,
        definitionDescription: _mergeDefinitionDescription(
          definitionDescription,
          other.definitionDescription,
          defId ?? path,
        ),
        occurrenceDescription: _mergeMemberDescription(
          occurrenceDescription,
          other.occurrenceDescription,
          path,
        ),
        nullable: nullable,
      );
    case RefNode(
        :final defId,
        :final occurrenceDescription,
        :final nullable,
      ):
      final other = candidate as RefNode;
      return RefNode(
        defId,
        occurrenceDescription: _mergeMemberDescription(
          occurrenceDescription,
          other.occurrenceDescription,
          path,
        ),
        nullable: nullable,
      );
    case UnionNode(
        :final variants,
        :final discriminatorField,
        :final defId,
        :final definitionDescription,
        :final occurrenceDescription,
        :final nullable,
      ):
      final other = candidate as UnionNode;
      return UnionNode(
        variants: [
          for (var index = 0; index < variants.length; index++)
            _mergeNode(
              variants[index],
              other.variants[index],
              '$path.variants[$index]',
            ),
        ],
        discriminatorField: discriminatorField,
        defId: defId,
        definitionDescription: _mergeDefinitionDescription(
          definitionDescription,
          other.definitionDescription,
          defId ?? path,
        ),
        occurrenceDescription: _mergeMemberDescription(
          occurrenceDescription,
          other.occurrenceDescription,
          path,
        ),
        nullable: nullable,
      );
  }
}

bool _sameDefinitionStructure(
  A2uiSchemaNode left,
  A2uiSchemaNode right,
) {
  if (left is ObjectNode && right is ObjectNode) {
    return left.defId == right.defId &&
        left.construction == right.construction &&
        const SetEquality<String>().equals(left.required, right.required) &&
        _sameFieldStructure(left.fields, right.fields);
  }
  if (left is UnionNode && right is UnionNode) {
    return left.defId == right.defId &&
        left.discriminatorField == right.discriminatorField &&
        _sameNodeList(left.variants, right.variants);
  }
  return false;
}

bool _sameFieldStructure(
  Map<String, A2uiSchemaNode> left,
  Map<String, A2uiSchemaNode> right,
) {
  if (!const SetEquality<String>()
      .equals(left.keys.toSet(), right.keys.toSet())) {
    return false;
  }
  for (final name in left.keys) {
    if (!_sameNodeStructure(left[name]!, right[name]!)) return false;
  }
  return true;
}

bool _sameNodeStructure(A2uiSchemaNode left, A2uiSchemaNode right) {
  if (left.runtimeType != right.runtimeType ||
      left.nullable != right.nullable) {
    return false;
  }
  return switch ((left, right)) {
    (
      ScalarNode(
        type: final leftType,
        preserveNumericRuntimeType: final leftPreserve,
      ),
      ScalarNode(
        type: final rightType,
        preserveNumericRuntimeType: final rightPreserve,
      ),
    ) =>
      leftType == rightType && leftPreserve == rightPreserve,
    (
      EnumNode(
        members: final leftMembers,
        dartTypeName: final leftName,
        libraryUri: final leftLibrary,
      ),
      EnumNode(
        members: final rightMembers,
        dartTypeName: final rightName,
        libraryUri: final rightLibrary,
      ),
    ) =>
      const ListEquality<String>().equals(leftMembers, rightMembers) &&
          leftName == rightName &&
          leftLibrary == rightLibrary,
    (ListNode(element: final a), ListNode(element: final b)) =>
      _sameNodeStructure(a, b),
    (MapNode(valueType: final a), MapNode(valueType: final b)) =>
      _sameNodeStructure(a, b),
    (
      ObjectNode(
        fields: final leftFields,
        required: final leftRequired,
        defId: final leftId,
        construction: final leftConstruction,
      ),
      ObjectNode(
        fields: final rightFields,
        required: final rightRequired,
        defId: final rightId,
        construction: final rightConstruction,
      ),
    ) =>
      leftId == rightId &&
          leftConstruction == rightConstruction &&
          const SetEquality<String>().equals(leftRequired, rightRequired) &&
          _sameFieldStructure(leftFields, rightFields),
    (
      UnionNode(
        variants: final leftVariants,
        discriminatorField: final leftDiscriminator,
        defId: final leftId,
      ),
      UnionNode(
        variants: final rightVariants,
        discriminatorField: final rightDiscriminator,
        defId: final rightId,
      ),
    ) =>
      leftDiscriminator == rightDiscriminator &&
          leftId == rightId &&
          _sameNodeList(leftVariants, rightVariants),
    (RefNode(defId: final a), RefNode(defId: final b)) => a == b,
    _ => false,
  };
}

bool _sameNodeList(
  List<A2uiSchemaNode> left,
  List<A2uiSchemaNode> right,
) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (!_sameNodeStructure(left[index], right[index])) return false;
  }
  return true;
}
