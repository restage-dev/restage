import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/collection_unroll.dart';
import 'package:restage_codegen/src/host_data_shape.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

/// Structural scope for one statically resolved widget occurrence.
@immutable
final class MeasurementOccurrenceScope {
  const MeasurementOccurrenceScope._({
    required this.sourceRootIdentity,
    required this.pathSegments,
    required this.parentStructuralOccurrenceKey,
    this.itemIdentity,
    this.runtimeLoopDepth = 0,
    this.repeatedStatically = false,
  });

  /// Creates the root scope from an already-resolved source identity.
  factory MeasurementOccurrenceScope.root(String sourceRootIdentity) {
    if (sourceRootIdentity.isEmpty) {
      throw ArgumentError('A measurement source identity must not be empty');
    }
    return MeasurementOccurrenceScope._(
      sourceRootIdentity: sourceRootIdentity,
      pathSegments: const <String>[],
      parentStructuralOccurrenceKey: null,
    );
  }

  /// Exact resolved source that owns this scope.
  final String sourceRootIdentity;

  /// Stable structural segments preceding the next widget.
  final List<String> pathSegments;

  /// Direct parent widget occurrence, absent at the source root.
  final String? parentStructuralOccurrenceKey;

  /// Identity of the repeated element this scope sits in, if any.
  final MeasurementItemIdentity? itemIdentity;

  /// Number of run-time loops enclosing this scope.
  final int runtimeLoopDepth;

  /// Whether this scope repeats once per iteration of a static loop.
  final bool repeatedStatically;

  /// Enters one exact widget declaration.
  MeasurementWidgetOccurrence widget(InterfaceElement widgetClass) {
    final widgetIdentity = measurementClassIdentity(widgetClass);
    final structuralOccurrenceKey = _structuralOccurrenceKey(
      sourceRootIdentity,
      <String>[...pathSegments, 'widget:$widgetIdentity'],
    );
    return MeasurementWidgetOccurrence._(
      scope: this,
      structuralOccurrenceKey: structuralOccurrenceKey,
      widgetIdentity: widgetIdentity,
    );
  }

  /// Adds one resolved helper call before the next widget edge.
  MeasurementOccurrenceScope enterHelper(ExecutableElement helper) =>
      _append('helper:${measurementHelperIdentity(helper)}');

  /// Adds the structural edges for one expanded collection element.
  ///
  /// The iterations of one static loop share their edges, so they share one
  /// occurrence and are told apart by their item identity.
  MeasurementOccurrenceScope enterCollectionOccurrence(
    CollectionSemanticOccurrence occurrence,
  ) {
    var result = this;
    if (!occurrence.isDirectListElement) {
      for (final segment in _sharedStructuralSegments(occurrence)) {
        result = result._append(segment);
      }
    }
    for (final (ordinal, step) in occurrence.identitySourceProvenance.indexed) {
      final element = step.element;
      if (step.kind == CollectionSemanticSourceKind.helper &&
          element is ExecutableElement) {
        result = result.enterHelper(element);
      } else {
        result = result._append('source:${step.kind.name}[$ordinal]');
      }
    }
    return result._withItem(occurrence);
  }

  MeasurementOccurrenceScope _withItem(
    CollectionSemanticOccurrence occurrence,
  ) {
    final templates = [
      for (final step in occurrence.structuralPath)
        if (step.kind == CollectionStructuralOccurrenceKind.loopTemplate)
          step.node,
    ];
    final iterations = [
      for (final step in occurrence.structuralPath)
        if (step.kind == CollectionStructuralOccurrenceKind.loopIteration)
          step.ordinal + 1,
    ];
    final depth = runtimeLoopDepth + templates.length;
    final repeated = repeatedStatically || iterations.isNotEmpty;
    final MeasurementItemIdentity? identity;
    if (repeated && depth > 0) {
      identity = const MeasurementUnavailableItem(
        'nested loops of different kinds cannot tell their items apart',
      );
    } else if (templates.isNotEmpty) {
      identity = depth == 1
          ? _runtimeLoopItem(templates.single)
          : const MeasurementUnavailableItem(
              'it sits inside more than one run-time loop',
            );
    } else if (depth == 0 && iterations.isNotEmpty) {
      identity = MeasurementStaticItem(
        _literalKey(occurrence) ?? iterations.join('.'),
      );
    } else {
      identity = itemIdentity;
    }
    return _copy(
      itemIdentity: identity,
      runtimeLoopDepth: depth,
      repeatedStatically: repeated,
    );
  }

  /// Adds the branch a widget-valued conditional selects.
  MeasurementOccurrenceScope enterConditionalBranch({required bool then}) =>
      _append(then ? 'cond:then' : 'cond:else');

  MeasurementOccurrenceScope _append(String segment) => _copy(
        pathSegments: <String>[...pathSegments, segment],
      );

  MeasurementOccurrenceScope _copy({
    List<String>? pathSegments,
    String? parentStructuralOccurrenceKey,
    MeasurementItemIdentity? itemIdentity,
    int? runtimeLoopDepth,
    bool? repeatedStatically,
  }) =>
      MeasurementOccurrenceScope._(
        sourceRootIdentity: sourceRootIdentity,
        pathSegments: pathSegments ?? this.pathSegments,
        parentStructuralOccurrenceKey:
            parentStructuralOccurrenceKey ?? this.parentStructuralOccurrenceKey,
        itemIdentity: itemIdentity ?? this.itemIdentity,
        runtimeLoopDepth: runtimeLoopDepth ?? this.runtimeLoopDepth,
        repeatedStatically: repeatedStatically ?? this.repeatedStatically,
      );
}

/// Identity of the repeated element a tap sits in.
@immutable
sealed class MeasurementItemIdentity {
  const MeasurementItemIdentity();
}

/// A statically unrolled element: its literal key, or its 1-based position.
final class MeasurementStaticItem extends MeasurementItemIdentity {
  /// Creates a static item.
  const MeasurementStaticItem(this.value);

  /// The literal item value.
  final String value;
}

/// An element of a run-time loop, identified by its host-supplied position.
final class MeasurementLoopItem extends MeasurementItemIdentity {
  /// Creates a loop item for the loop variable [loopIdentifier].
  const MeasurementLoopItem(this.loopIdentifier);

  /// The authored loop variable.
  final String loopIdentifier;
}

/// A repeated element with no item identity.
final class MeasurementUnavailableItem extends MeasurementItemIdentity {
  /// Creates an unavailable item; [reason] completes "no item because ...".
  const MeasurementUnavailableItem(this.reason);

  /// Why the element has no identity.
  final String reason;
}

const Set<String> _kPlainTapSlots = {'onTap', 'onPressed'};

/// A key the iterations of one static loop share, or null for any other
/// element. Consecutive elements with one key take one list position.
String? measurementStaticIterationKey(
  CollectionSemanticOccurrence occurrence,
) =>
    occurrence.structuralPath.any(
      (step) => step.kind == CollectionStructuralOccurrenceKind.loopIteration,
    )
        ? _sharedStructuralSegments(occurrence).join('|')
        : null;

// Iterations of one static loop drop their iteration and iterable ordinals.
Iterable<String> _sharedStructuralSegments(
  CollectionSemanticOccurrence occurrence,
) {
  final steps = occurrence.structuralPath;
  final skipped = <int>{};
  for (final (index, step) in steps.indexed) {
    if (step.kind != CollectionStructuralOccurrenceKind.loopIteration) continue;
    for (var back = 1; back <= step.iterableSteps; back++) {
      skipped.add(index - back);
    }
  }
  return [
    for (final (index, step) in steps.indexed)
      if (!skipped.contains(index))
        step.kind == CollectionStructuralOccurrenceKind.loopIteration
            ? 'collection:${step.kind.name}'
            : 'collection:${step.kind.name}[${step.ordinal}]',
  ];
}

MeasurementItemIdentity _runtimeLoopItem(AstNode node) {
  final parts = node is ForElement ? node.forLoopParts : null;
  if (parts is! ForEachPartsWithDeclaration) {
    return const MeasurementUnavailableItem(
      'the loop does not declare its element',
    );
  }
  final type = parts.iterable.staticType;
  final elementType = type is InterfaceType && type.isDartCoreList
      ? type.typeArguments.single
      : null;
  final shape = elementType == null
      ? null
      : deriveHostDataShape(elementType, root: 'element').shape;
  return shape is HostDataMapShape || shape is HostDataObjectShape
      ? MeasurementLoopItem(parts.loopVariable.name.lexeme)
      : const MeasurementUnavailableItem(
          'its elements are not objects or maps, so they carry no position',
        );
}

String? _literalKey(CollectionSemanticOccurrence occurrence) {
  final widget = occurrence.terminalExpression;
  if (widget is! InstanceCreationExpression) return null;
  for (final argument in widget.argumentList.arguments) {
    if (argument is! NamedArgument || argument.name.lexeme != 'key') continue;
    final key = argument.argumentExpression;
    if (key is! InstanceCreationExpression ||
        key.constructorName.type.name.lexeme != 'ValueKey' ||
        key.argumentList.arguments.length != 1) {
      return null;
    }
    final value = _resolvedString(
      key.argumentList.arguments.single.argumentExpression,
      occurrence.bindings,
      8,
    );
    return value != null && measurementInteractionItemIsValidV1(value)
        ? value
        : null;
  }
  return null;
}

String? _resolvedString(
  Expression expression,
  Map<Element, Expression> bindings,
  int depth,
) {
  if (expression is SimpleStringLiteral) return expression.value;
  if (depth == 0 || expression is! SimpleIdentifier) return null;
  final bound = bindings[expression.element];
  return bound == null ? null : _resolvedString(bound, bindings, depth - 1);
}

/// One exact structural widget occurrence.
@immutable
final class MeasurementWidgetOccurrence {
  const MeasurementWidgetOccurrence._({
    required this.scope,
    required this.structuralOccurrenceKey,
    required this.widgetIdentity,
  });

  /// Scope immediately preceding this widget.
  final MeasurementOccurrenceScope scope;

  /// Stable locator shared with ledger reconciliation.
  final String structuralOccurrenceKey;

  /// Exact resolved widget declaration identity.
  final String widgetIdentity;

  /// Direct parent widget occurrence, absent at the source root.
  String? get parentStructuralOccurrenceKey =>
      scope.parentStructuralOccurrenceKey;

  /// Rebases this occurrence onto [scope] — the same widget, reached through
  /// the helper segments the traversal entered before its slot.
  MeasurementWidgetOccurrence withScope(MeasurementOccurrenceScope scope) =>
      MeasurementWidgetOccurrence._(
        scope: scope,
        structuralOccurrenceKey: structuralOccurrenceKey,
        widgetIdentity: widgetIdentity,
      );

  /// Creates the structural scope for one exact child slot occurrence.
  MeasurementOccurrenceScope child(
    FormalParameterElement slot, {
    required int ordinal,
  }) {
    if (ordinal < 0) {
      throw ArgumentError.value(ordinal, 'ordinal', 'Must not be negative');
    }
    final slotName = _stableElementName(slot, 'widget slot');
    return scope._copy(
      pathSegments: <String>[
        ...scope.pathSegments,
        'child:$widgetIdentity:$widgetIdentity.$slotName[$ordinal]',
      ],
      parentStructuralOccurrenceKey: structuralOccurrenceKey,
    );
  }

  /// Creates a deferred list-child scope for one exact widget-list slot.
  MeasurementWidgetListOccurrence widgetList(FormalParameterElement slot) =>
      MeasurementWidgetListOccurrence._(
        parent: this,
        slot: slot,
        scope: scope,
      );

  /// Enters this custom widget's emitted definition body.
  MeasurementOccurrenceScope enterInlinedBody() => scope._copy(
        pathSegments: <String>[
          ...scope.pathSegments,
          'inline:$widgetIdentity',
          'inlinedBody:$widgetIdentity',
        ],
        parentStructuralOccurrenceKey: structuralOccurrenceKey,
      );

  /// Selects one exact callback slot on this occurrence.
  MeasurementEventOccurrence event(Element eventElement) =>
      MeasurementEventOccurrence._(
        sourceRootIdentity: scope.sourceRootIdentity,
        structuralOccurrenceKey: structuralOccurrenceKey,
        sourceEventIdentity: SourceEventIdentity(
          _stableElementName(eventElement, 'event slot'),
        ),
        widgetPathSegments: <String>[
          ...scope.pathSegments,
          'widget:$widgetIdentity',
        ],
        scope: scope,
      );
}

/// Structural scope awaiting one element of an exact widget-list slot.
@immutable
final class MeasurementWidgetListOccurrence {
  const MeasurementWidgetListOccurrence._({
    required this.parent,
    required this.slot,
    required this.scope,
  });

  /// Widget that declares this list slot.
  final MeasurementWidgetOccurrence parent;

  /// Exact constructor parameter for the list slot.
  final FormalParameterElement slot;

  /// Structural scope preceding the list elements.
  final MeasurementOccurrenceScope scope;

  /// Adds one resolved helper traversed before the list elements.
  MeasurementWidgetListOccurrence enterHelper(ExecutableElement helper) =>
      MeasurementWidgetListOccurrence._(
        parent: parent,
        slot: slot,
        scope: scope.enterHelper(helper),
      );

  /// Adds the branch a list-valued conditional selects.
  MeasurementWidgetListOccurrence enterConditionalBranch({
    required bool then,
  }) =>
      MeasurementWidgetListOccurrence._(
        parent: parent,
        slot: slot,
        scope: scope.enterConditionalBranch(then: then),
      );

  /// Selects one exact element occurrence.
  MeasurementOccurrenceScope element(
    int ordinal, {
    CollectionSemanticOccurrence? collectionOccurrence,
  }) {
    final elementScope = parent.withScope(scope).child(slot, ordinal: ordinal);
    return collectionOccurrence == null
        ? elementScope
        : elementScope.enterCollectionOccurrence(collectionOccurrence);
  }
}

/// One structural widget occurrence plus one exact callback slot.
@immutable
final class MeasurementEventOccurrence {
  const MeasurementEventOccurrence._({
    required this.sourceRootIdentity,
    required this.structuralOccurrenceKey,
    required this.sourceEventIdentity,
    required List<String> widgetPathSegments,
    required MeasurementOccurrenceScope scope,
  })  : _widgetPathSegments = widgetPathSegments,
        _scope = scope;

  /// Exact resolved source owning this event.
  final String sourceRootIdentity;

  /// Stable structural widget occurrence.
  final String structuralOccurrenceKey;

  /// Exact callback slot selected on the widget occurrence.
  final SourceEventIdentity sourceEventIdentity;

  final List<String> _widgetPathSegments;

  final MeasurementOccurrenceScope _scope;

  /// Identity of the repeated element this callback sits in, if any.
  MeasurementItemIdentity? get itemIdentity => _scope.itemIdentity;

  /// Whether every iteration of a static loop emits this same callback.
  bool get repeatedStatically => _scope.repeatedStatically;

  /// The item a plain tap on this callback records, or null.
  MeasurementItemIdentity? get tapItem {
    final identity = itemIdentity;
    return identity is MeasurementUnavailableItem ||
            !_kPlainTapSlots.contains(sourceEventIdentity.value)
        ? null
        : identity;
  }

  /// Scope of the modal sheet builder body this callback opens.
  MeasurementOccurrenceScope sheetBuilder() => _scope._copy(
        pathSegments: <String>[
          ..._widgetPathSegments,
          'sheet:${sourceEventIdentity.value}:builder',
        ],
        parentStructuralOccurrenceKey: structuralOccurrenceKey,
      );

  @override
  bool operator ==(Object other) =>
      other is MeasurementEventOccurrence &&
      other.sourceRootIdentity == sourceRootIdentity &&
      other.structuralOccurrenceKey == structuralOccurrenceKey &&
      other.sourceEventIdentity == sourceEventIdentity;

  @override
  int get hashCode => Object.hash(
        sourceRootIdentity,
        structuralOccurrenceKey,
        sourceEventIdentity,
      );
}

/// Stable identity for one resolved class element.
String measurementClassIdentity(InterfaceElement element) {
  final name = element.name;
  final libraryUri = element.library.identifier;
  if (name == null || name.isEmpty || libraryUri.isEmpty) {
    throw ArgumentError('Resolved class identities must be stable');
  }
  return '$libraryUri#$name';
}

/// Stable identity for one resolved helper element.
String measurementHelperIdentity(ExecutableElement executable) {
  final libraryUri = executable.library.identifier;
  final executableName = executable.name;
  final owner = executable.enclosingElement;
  final ownerName = owner is InstanceElement ? owner.name : null;
  if (libraryUri.isEmpty ||
      executableName == null ||
      executableName.isEmpty ||
      (ownerName != null && ownerName.isEmpty)) {
    throw ArgumentError('Resolved helper identities must be stable');
  }
  return '$libraryUri#${ownerName ?? 'topLevel'}.$executableName';
}

String _stableElementName(Element element, String role) {
  final name = element.name;
  final libraryUri = element.library?.identifier;
  if (name == null ||
      name.isEmpty ||
      libraryUri == null ||
      libraryUri.isEmpty) {
    throw ArgumentError(
      'A resolved measurement $role must have stable identity',
    );
  }
  return name;
}

String _structuralOccurrenceKey(
  String sourceRootIdentity,
  List<String> segments,
) =>
    '$sourceRootIdentity|${segments.join('|')}';
