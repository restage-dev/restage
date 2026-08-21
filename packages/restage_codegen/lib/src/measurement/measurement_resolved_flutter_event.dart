part of 'measurement_resolved_event.dart';

/// Compiler-resolved identity for an ordinary Flutter callback.
///
/// This value is deliberately constructed only from analyzer elements. It does
/// not accept syntactic names, source offsets, display copy, Flutter keys, or
/// runtime widget instances as identity authority.
final class MeasurementResolvedFlutterEvent extends MeasurementResolvedEvent {
  MeasurementResolvedFlutterEvent._({
    required this.widgetLibraryUri,
    required this.widgetClassName,
    required this.eventLibraryUri,
    required this.eventOwnerClassName,
    required this.eventElementName,
    required this.declarationProvenance,
  });

  /// Creates a strict compiler-recognised Flutter event.
  ///
  /// Both elements must resolve to `package:flutter/`, and the callback must
  /// be owned by the supplied widget class. Lookalike names and unresolved
  /// syntax therefore fail closed.
  factory MeasurementResolvedFlutterEvent.fromResolvedElements({
    required InterfaceElement? widgetClass,
    required Element? eventElement,
  }) {
    if (widgetClass == null || eventElement == null) {
      throw ArgumentError(
        'An ordinary measurement event requires resolved widget and event '
        'elements',
      );
    }

    final widgetLibraryUri = widgetClass.library.identifier;
    final eventLibraryUri = eventElement.library?.identifier;
    if (!_isFlutterLibrary(widgetLibraryUri) ||
        !_isFlutterLibrary(eventLibraryUri) ||
        !_belongsToWidgetClass(eventElement, widgetClass)) {
      throw ArgumentError(
        'An ordinary measurement event must resolve to its Flutter widget '
        'and callback origin',
      );
    }

    final widgetClassName = widgetClass.name;
    final eventElementName = eventElement.name;
    final eventOwnerClassName = _enclosingFlutterClassName(eventElement);
    if (widgetClassName == null ||
        widgetClassName.isEmpty ||
        eventElementName == null ||
        eventElementName.isEmpty ||
        eventOwnerClassName == null ||
        eventOwnerClassName.isEmpty) {
      throw ArgumentError(
        'Resolved Flutter widget and event identities must have stable names',
      );
    }

    return MeasurementResolvedFlutterEvent._(
      widgetLibraryUri: widgetLibraryUri,
      widgetClassName: widgetClassName,
      eventLibraryUri: eventLibraryUri!,
      eventOwnerClassName: eventOwnerClassName,
      eventElementName: eventElementName,
      declarationProvenance: MeasurementEventDeclarationProvenance(
        libraryUri: eventLibraryUri,
        className: eventOwnerClassName,
        memberName: eventElementName,
        sourceSelector: SourceEventIdentity(eventElementName),
      ),
    );
  }

  /// Library of the resolved widget declaration.
  final String widgetLibraryUri;

  /// Resolved Flutter widget class name.
  final String widgetClassName;

  /// Library of the resolved callback declaration.
  final String eventLibraryUri;

  /// Resolved class that owns the callback declaration.
  final String eventOwnerClassName;

  /// Resolved callback element name.
  final String eventElementName;

  /// Exact compiler-only declaration provenance for the callback slot.
  @override
  final MeasurementEventDeclarationProvenance declarationProvenance;

  /// Human-inspectable resolved identity used for compiler diagnostics only.
  @override
  String get resolvedSemanticIdentity => '$widgetLibraryUri#$widgetClassName|'
      '$eventLibraryUri#$eventOwnerClassName.$eventElementName';
}

bool _isFlutterLibrary(String? identifier) =>
    identifier != null && identifier.startsWith('package:flutter/');

bool _belongsToWidgetClass(Element eventElement, InterfaceElement widgetClass) {
  final owner = _enclosingFlutterClass(eventElement);
  if (owner == null) return false;
  return owner == widgetClass ||
      widgetClass.allSupertypes.any((type) => type.element == owner);
}

String? _enclosingFlutterClassName(Element element) {
  return _enclosingFlutterClass(element)?.name;
}

InterfaceElement? _enclosingFlutterClass(Element element) {
  Element? cursor = element;
  while (cursor != null) {
    if (cursor is InterfaceElement) return cursor;
    cursor = cursor.enclosingElement;
  }
  return null;
}
