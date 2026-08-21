part of 'measurement_resolved_event.dart';

/// The exact compiler authority that admitted an opaque widget occurrence.
enum MeasurementSourceRootKind {
  /// A compiler-owned native screen source.
  screenSource,

  /// A compiler-owned paywall source.
  paywallSource,

  /// A compiler-owned flow source.
  flowSource,
}

/// Compiler-resolved event slot on one opaque custom-widget occurrence.
///
/// This resolver receives only the statically emitted catalog-factory
/// occurrence. It admits catalog-declared event properties and intentionally
/// never walks the custom widget's private Flutter implementation, derives
/// callback arguments, or reconstructs event names at runtime.
final class MeasurementResolvedOpaqueCustomWidgetEvent
    extends MeasurementResolvedEvent {
  MeasurementResolvedOpaqueCustomWidgetEvent._({
    required this.sourceRootKind,
    required this.sourceRootLibraryUri,
    required this.sourceRootClassName,
    required this.widgetLibraryUri,
    required this.widgetClassName,
    required this.catalogWidgetWireId,
    required this.catalogLibraryNamespace,
    required this.declarationProvenance,
  });

  /// Discovers all explicit static event slots on [occurrence].
  ///
  /// The occurrence must already be in the opaque catalog-factory branch of a
  /// compiler-owned `ScreenSource`, `PaywallSource`, or `FlowSource`. A slot is
  /// admitted only when its resolved constructor parameter exactly joins one
  /// custom catalog event property. Every unresolved, dynamic, ambiguous, or
  /// mismatched construct fails closed.
  static List<MeasurementResolvedOpaqueCustomWidgetEvent> discoverSlots({
    required InterfaceElement? sourceRoot,
    required InstanceCreationExpression? occurrence,
    required Catalog catalog,
  }) {
    if (sourceRoot == null || occurrence == null) {
      throw ArgumentError(
        'An opaque measurement slot requires resolved source and occurrence',
      );
    }
    final sourceRootKind = _resolveSourceRootKind(sourceRoot);
    final constructor = occurrence.constructorName.element;
    if (constructor is! ConstructorElement) {
      throw ArgumentError(
        'An opaque measurement occurrence requires a resolved constructor',
      );
    }
    final widgetClass = constructor.enclosingElement;
    final widgetLibraryUri = widgetClass.library.identifier;
    final widgetClassName = widgetClass.name;
    if (widgetLibraryUri.isEmpty ||
        widgetClassName == null ||
        widgetClassName.isEmpty) {
      throw ArgumentError(
        'An opaque measurement occurrence requires stable widget provenance',
      );
    }

    final constructorName = occurrence.constructorName.name?.name;
    final constructorSuffix = constructorName == null || constructorName.isEmpty
        ? ''
        : '.$constructorName';
    final widgetClassKey =
        '$widgetLibraryUri#$widgetClassName$constructorSuffix';
    final catalogCandidates = catalog.widgets
        .where(
          (widget) =>
              widget.flutterType == widgetClassKey &&
              WidgetLibrary.builtInByNamespace(widget.library.namespace) ==
                  null,
        )
        .toList(growable: false);
    if (catalogCandidates.length != 1) {
      throw ArgumentError(
        'An opaque measurement occurrence must resolve to one exact custom '
        'catalog widget',
      );
    }
    final catalogWidget = catalogCandidates.single;
    final sourceRootLibraryUri = sourceRoot.library.identifier;
    final sourceRootClassName = sourceRoot.name;
    if (sourceRootLibraryUri.isEmpty ||
        sourceRootClassName == null ||
        sourceRootClassName.isEmpty) {
      throw ArgumentError(
        'An opaque measurement source requires stable root provenance',
      );
    }

    final slots = <MeasurementResolvedOpaqueCustomWidgetEvent>[];
    final seenArgumentNames = <String>{};
    for (final argument in occurrence.argumentList.arguments) {
      if (argument is! NamedExpression) {
        throw ArgumentError(
          'An opaque measurement occurrence accepts only static named slots',
        );
      }
      final argumentName = argument.name.label.name;
      if (!seenArgumentNames.add(argumentName)) {
        throw ArgumentError(
          'An opaque measurement occurrence cannot repeat one named slot',
        );
      }
      // Flutter keys identify widget instances at runtime only. They never
      // authorize an event slot or contribute to compiler measurement identity.
      if (argumentName == 'key') continue;

      final parameter = argument.name.label.element;
      if (parameter is! FormalParameterElement ||
          parameter.enclosingElement is! ConstructorElement ||
          parameter.enclosingElement != constructor ||
          parameter.name != argumentName ||
          _enclosingOpaqueClass(parameter) != widgetClass) {
        throw ArgumentError(
          'An opaque measurement slot requires its exact declared constructor '
          'parameter',
        );
      }
      final propertyCandidates = catalogWidget.properties
          .where((property) => property.name == argumentName)
          .toList(growable: false);
      if (propertyCandidates.length != 1) {
        throw ArgumentError(
          'An opaque measurement slot must join one declared catalog property',
        );
      }
      final property = propertyCandidates.single;
      if (property.type != PropertyType.event) continue;

      final staticType = argument.expression.staticType;
      if (staticType == null ||
          staticType is DynamicType ||
          staticType is InvalidType ||
          staticType is! FunctionType) {
        throw ArgumentError(
          'An opaque measurement slot requires a static callback value',
        );
      }

      final eventLibraryUri = parameter.library?.identifier;
      final eventOwnerClassName = _enclosingOpaqueClass(parameter)?.name;
      final eventElementName = parameter.name;
      if (eventLibraryUri == null ||
          eventLibraryUri.isEmpty ||
          eventOwnerClassName == null ||
          eventOwnerClassName.isEmpty ||
          eventElementName == null ||
          eventElementName.isEmpty) {
        throw ArgumentError(
          'An opaque measurement slot requires stable declaration provenance',
        );
      }
      slots.add(
        MeasurementResolvedOpaqueCustomWidgetEvent._(
          sourceRootKind: sourceRootKind,
          sourceRootLibraryUri: sourceRootLibraryUri,
          sourceRootClassName: sourceRootClassName,
          widgetLibraryUri: widgetLibraryUri,
          widgetClassName: widgetClassName,
          catalogWidgetWireId: catalogWidget.wireId,
          catalogLibraryNamespace: catalogWidget.library.namespace,
          declarationProvenance: MeasurementEventDeclarationProvenance(
            libraryUri: eventLibraryUri,
            className: eventOwnerClassName,
            memberName: eventElementName,
            sourceSelector: SourceEventIdentity(eventElementName),
          ),
        ),
      );
    }
    return List.unmodifiable(slots);
  }

  /// Exact compiler authority that contains this occurrence.
  final MeasurementSourceRootKind sourceRootKind;

  /// Declaring library of the compiler-owned source root.
  final String sourceRootLibraryUri;

  /// Compiler-owned source-root class name.
  final String sourceRootClassName;

  /// Resolved library of the opaque widget class.
  final String widgetLibraryUri;

  /// Resolved opaque widget class name.
  final String widgetClassName;

  /// Exact installed custom catalog widget identity.
  final WireId catalogWidgetWireId;

  /// Installed custom catalog library namespace.
  final String catalogLibraryNamespace;

  /// Exact compiler-only declaration provenance for this event slot.
  @override
  final MeasurementEventDeclarationProvenance declarationProvenance;

  /// Human-inspectable compiler identity, outside wire/hash domains.
  @override
  String get resolvedSemanticIdentity => '$widgetLibraryUri#$widgetClassName|'
      '${declarationProvenance.libraryUri}#'
      '${declarationProvenance.className}.${declarationProvenance.memberName}|'
      '$catalogLibraryNamespace:${catalogWidgetWireId.value}';
}

MeasurementSourceRootKind _resolveSourceRootKind(InterfaceElement root) {
  final matches = <MeasurementSourceRootKind>[];
  for (final annotation in root.metadata.annotations) {
    final annotationClass = _annotationClass(annotation);
    if (annotationClass == null) {
      if (_spellsSourceRootAnnotation(annotation.toSource())) {
        throw ArgumentError(
          'A measurement source root annotation must resolve to Restage',
        );
      }
      continue;
    }
    final kind = _sourceRootKinds[annotationClass.name];
    if (kind == null) continue;
    if (annotationClass.library.identifier !=
        _sourceRootOrigins[annotationClass.name]) {
      throw ArgumentError(
        'A measurement source root must resolve to its exact Restage origin',
      );
    }
    matches.add(kind);
  }
  if (matches.length != 1) {
    throw ArgumentError(
      'An opaque measurement occurrence requires one exact compiler source '
      'root',
    );
  }
  return matches.single;
}

const _sourceRootKinds = <String, MeasurementSourceRootKind>{
  'Screen': MeasurementSourceRootKind.screenSource,
  'ScreenSource': MeasurementSourceRootKind.screenSource,
  'Paywall': MeasurementSourceRootKind.paywallSource,
  'PaywallSource': MeasurementSourceRootKind.paywallSource,
  'FlowGraph': MeasurementSourceRootKind.flowSource,
  'FlowSource': MeasurementSourceRootKind.flowSource,
};

const _sourceRootOrigins = <String, String>{
  'Screen': 'package:restage/src/authoring/screen.dart',
  'ScreenSource': 'package:restage/src/authoring/flow_source.dart',
  'Paywall': 'package:restage/src/authoring/paywall_source.dart',
  'PaywallSource': 'package:restage/src/authoring/paywall_source.dart',
  'FlowGraph': 'package:restage/src/authoring/flow_source.dart',
  'FlowSource': 'package:restage/src/authoring/flow_source.dart',
};

InterfaceElement? _annotationClass(ElementAnnotation annotation) {
  final element = annotation.element;
  if (element is ConstructorElement) return element.enclosingElement;
  if (element is PropertyAccessorElement) {
    final type = element.variable.type;
    if (type is InterfaceType) return type.element;
  }
  if (element is FieldElement) {
    final type = element.type;
    if (type is InterfaceType) return type.element;
  }
  final constantType = annotation.computeConstantValue()?.type;
  if (constantType is InterfaceType) return constantType.element;
  return null;
}

bool _spellsSourceRootAnnotation(String source) => _sourceRootKinds.keys.any(
      (name) =>
          source.startsWith('@$name') &&
          (source.length == name.length + 1 ||
              !_isIdentifierPart(source.codeUnitAt(name.length + 1))),
    );

bool _isIdentifierPart(int unit) =>
    (unit >= 0x30 && unit <= 0x39) ||
    (unit >= 0x41 && unit <= 0x5A) ||
    (unit >= 0x61 && unit <= 0x7A) ||
    unit == 0x5F ||
    unit == 0x24;

InterfaceElement? _enclosingOpaqueClass(Element element) {
  Element? cursor = element;
  while (cursor != null) {
    if (cursor is InterfaceElement) return cursor;
    cursor = cursor.enclosingElement;
  }
  return null;
}
