import 'package:analyzer/dart/element/element.dart';
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/collection_unroll.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

/// Structural scope for one statically resolved widget occurrence.
@immutable
final class MeasurementOccurrenceScope {
  const MeasurementOccurrenceScope._({
    required this.sourceRootIdentity,
    required this.pathSegments,
    required this.parentStructuralOccurrenceKey,
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
  MeasurementOccurrenceScope enterCollectionOccurrence(
    CollectionSemanticOccurrence occurrence,
  ) {
    var result = this;
    if (!occurrence.isDirectListElement) {
      for (final step in occurrence.structuralPath) {
        result =
            result._append('collection:${step.kind.name}[${step.ordinal}]');
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
    return result;
  }

  MeasurementOccurrenceScope _append(String segment) =>
      MeasurementOccurrenceScope._(
        sourceRootIdentity: sourceRootIdentity,
        pathSegments: <String>[...pathSegments, segment],
        parentStructuralOccurrenceKey: parentStructuralOccurrenceKey,
      );
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
    return MeasurementOccurrenceScope._(
      sourceRootIdentity: scope.sourceRootIdentity,
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
  MeasurementOccurrenceScope enterInlinedBody() => MeasurementOccurrenceScope._(
        sourceRootIdentity: scope.sourceRootIdentity,
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
  });

  /// Exact resolved source owning this event.
  final String sourceRootIdentity;

  /// Stable structural widget occurrence.
  final String structuralOccurrenceKey;

  /// Exact callback slot selected on the widget occurrence.
  final SourceEventIdentity sourceEventIdentity;

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
  final ownerName = owner is InterfaceElement ? owner.name : null;
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
