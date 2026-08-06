import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:meta/meta.dart';
import 'package:rfw_catalog_compiler/src/walker/dartdoc.dart';

/// Whether a canonical generative constructor could be selected.
enum StructuredConstructorStatus {
  /// The unnamed constructor, or the sole public named constructor, resolved.
  resolved,

  /// Several public named generative constructors exist and none is canonical.
  ambiguous,

  /// No usable public generative constructor exists.
  unresolved,
}

/// Whether a constructor formal is analyzer-linked to one canonical member.
enum StructuredMemberAssociationStatus {
  /// The analyzer exposes one backing field/property relationship.
  resolved,

  /// More than one candidate association exists.
  ambiguous,

  /// The analyzer exposes no association; equal names are not sufficient.
  unresolved,

  /// Associated source facts contradict the one-member contract.
  conflict,
}

/// State of one occurrence-description fact.
enum StructuredDescriptionFactStatus {
  /// One non-empty description and its provenance resolved.
  present,

  /// No supported source supplied a description.
  absent,

  /// Invalid or contradictory author input was found.
  conflict,
}

/// The source selected by nested-description precedence.
enum StructuredDescriptionSourceKind {
  /// An explicit annotation on the canonical constructor parameter.
  explicitParameter,

  /// An explicit annotation on the analyzer-associated data member.
  explicitMember,

  /// Dartdoc on the analyzer-associated data member.
  memberDartdoc,

  /// Dartdoc on a constructor parameter linked to the same member.
  resolvedParameterDartdoc,
}

/// Stable source coordinates for an occurrence-description diagnostic.
@immutable
final class StructuredSourceAnchor {
  /// Creates stable source coordinates for one description fact.
  const StructuredSourceAnchor({
    required this.libraryUri,
    required this.offset,
    required this.length,
    required this.label,
  });

  /// The URI of the library that owns the source element.
  final String libraryUri;

  /// The canonical source offset of the element declaration.
  final int offset;

  /// The source-name length used by diagnostic consumers.
  final int length;

  /// A human-readable label for the anchored source.
  final String label;

  @override
  bool operator ==(Object other) =>
      other is StructuredSourceAnchor &&
      other.libraryUri == libraryUri &&
      other.offset == offset &&
      other.length == length &&
      other.label == label;

  @override
  int get hashCode => Object.hash(libraryUri, offset, length, label);

  @override
  String toString() => '$libraryUri:$offset:$length ($label)';
}

/// One normalized description, absence, or actionable source conflict.
@immutable
final class StructuredDescriptionFact {
  const StructuredDescriptionFact._({
    required this.status,
    required this.anchors,
    this.text,
    this.source,
    this.message,
  });

  /// Creates a fact representing genuine description absence.
  const StructuredDescriptionFact.absent()
      : this._(
          status: StructuredDescriptionFactStatus.absent,
          anchors: const [],
        );

  /// Creates one present, non-empty description with its provenance.
  StructuredDescriptionFact.present({
    required String text,
    required StructuredDescriptionSourceKind source,
    required StructuredSourceAnchor anchor,
  }) : this._(
          status: StructuredDescriptionFactStatus.present,
          text: text,
          source: source,
          anchors: List.unmodifiable([anchor]),
        );

  /// Creates an actionable conflict with every participating source anchor.
  StructuredDescriptionFact.conflict({
    required String message,
    required List<StructuredSourceAnchor> anchors,
  }) : this._(
          status: StructuredDescriptionFactStatus.conflict,
          message: message,
          anchors: List.unmodifiable(anchors),
        );

  /// Whether this fact is present, absent, or conflicting.
  final StructuredDescriptionFactStatus status;

  /// The normalized non-empty text when [status] is present.
  final String? text;

  /// The selected provenance when [status] is present.
  final StructuredDescriptionSourceKind? source;

  /// Stable source coordinates relevant to this fact.
  final List<StructuredSourceAnchor> anchors;

  /// Actionable diagnostic text when [status] is conflict.
  final String? message;
}

/// Association and orthogonal description fact for one canonical formal.
@immutable
final class StructuredMemberDescription {
  /// Creates association and description facts for one canonical formal.
  const StructuredMemberDescription({
    required this.parameter,
    required this.member,
    required this.association,
    required this.description,
  });

  /// The canonical reconstruction constructor's formal parameter.
  final FormalParameterElement parameter;

  /// The analyzer-associated public data member, when resolved.
  final FieldElement? member;

  /// The association state, independent from [description].
  final StructuredMemberAssociationStatus association;

  /// The occurrence-description fact for this formal/member pair.
  final StructuredDescriptionFact description;
}

/// Shared canonical-constructor/member and description resolution.
@immutable
final class StructuredDescriptionModel {
  /// Creates one shared canonical-constructor description model.
  StructuredDescriptionModel({
    required this.constructorStatus,
    required this.constructor,
    required List<StructuredMemberDescription> members,
    List<StructuredDescriptionFact> conflicts = const [],
  })  : members = List.unmodifiable(members),
        conflicts = List.unmodifiable(conflicts);

  /// Whether canonical constructor selection resolved.
  final StructuredConstructorStatus constructorStatus;

  /// The selected substituted constructor, when unambiguous.
  final ConstructorElement? constructor;

  /// Association and provenance facts for the canonical constructor formals.
  final List<StructuredMemberDescription> members;

  /// Explicit author-input conflicts that both consumers must reject.
  final List<StructuredDescriptionFact> conflicts;

  /// Resolution for [parameter], by analyzer element identity.
  StructuredMemberDescription? forParameter(FormalParameterElement parameter) {
    for (final member in members) {
      if (_sameDeclaration(member.parameter, parameter)) {
        return member;
      }
    }
    return null;
  }

  /// Resolution for [field], by analyzer element identity.
  StructuredMemberDescription? forField(FieldElement field) {
    for (final member in members) {
      if (_sameDeclaration(member.member, field)) {
        return member;
      }
    }
    return null;
  }
}

/// One actionable nested-description conflict.
///
/// Instances are created only by [resolveStructuredDescriptions]. Source
/// anchors identify owner declarations plus their stable metadata ordinals;
/// they do not claim annotation-token ranges.
@immutable
final class StructuredDescriptionConflict {
  StructuredDescriptionConflict._(StructuredDescriptionFact fact)
      : assert(
          fact.status == StructuredDescriptionFactStatus.conflict,
          'Only conflict facts can cross the public facade.',
        ),
        message = fact.message!,
        anchors = List.unmodifiable(
          fact.anchors.map((anchor) => anchor.toString()),
        );

  /// Actionable diagnostic text.
  final String message;

  /// Stable owner-declaration and metadata-ordinal source anchors.
  final List<String> anchors;
}

/// Query-only result of canonical-constructor description resolution.
///
/// The raw association, provenance, and source-fact model stays internal to the
/// compiler. Consumers can inspect the selected constructor, reject conflicts,
/// and query the resolved description for an analyzer occurrence.
@immutable
final class StructuredDescriptionResolution {
  StructuredDescriptionResolution._(
    StructuredDescriptionModel model, {
    required this.definitionDescription,
  })  : constructor = model.constructor,
        conflicts = List.unmodifiable(
          model.conflicts.map(StructuredDescriptionConflict._),
        ),
        _model = model;

  /// The selected substituted constructor, or `null` when unresolved.
  final ConstructorElement? constructor;

  /// Explicit author-input conflicts that consumers must reject.
  final List<StructuredDescriptionConflict> conflicts;

  /// Canonical non-empty Dartdoc for the named structured type, if present.
  ///
  /// This type-definition fact is orthogonal to the occurrence descriptions
  /// queried by [descriptionForParameter] and [descriptionForField].
  final String? definitionDescription;

  final StructuredDescriptionModel _model;

  /// The selected non-empty description for [parameter], if present.
  String? descriptionForParameter(FormalParameterElement parameter) {
    final fact = _model.forParameter(parameter)?.description;
    return fact?.status == StructuredDescriptionFactStatus.present
        ? fact!.text
        : null;
  }

  /// The selected non-empty description for [field], if present.
  String? descriptionForField(FieldElement field) {
    final fact = _model.forField(field)?.description;
    return fact?.status == StructuredDescriptionFactStatus.present
        ? fact!.text
        : null;
  }
}

/// Resolves one canonical generative constructor and nested descriptions.
///
/// Positive association follows an analyzer field-formal link or a super-formal
/// chain whose `superConstructorParameter` traversal terminates at an
/// analyzer-linked field-formal/member. Chains ending at ordinary parameters
/// remain unresolved; name equality never creates an association.
StructuredDescriptionResolution resolveStructuredDescriptions(
  InterfaceType type,
) =>
    StructuredDescriptionResolution._(
      _resolveStructuredDescriptions(type),
      definitionDescription: _resolveDefinitionDescription(type),
    );

String? _resolveDefinitionDescription(InterfaceType type) =>
    stripDartdocSlashes(type.element.documentationComment);

StructuredDescriptionModel _resolveStructuredDescriptions(InterfaceType type) {
  final constructorResolution = _canonicalConstructor(type);
  final constructor = constructorResolution.constructor;
  if (constructor == null) {
    final explicit = _allExplicitAnnotations(type);
    return StructuredDescriptionModel(
      constructorStatus: constructorResolution.status,
      constructor: null,
      members: const [],
      conflicts: explicit.isEmpty
          ? const []
          : [
              StructuredDescriptionFact.conflict(
                message: _unresolvedAssociationMessage(
                  explicit,
                  constructorUnresolved: true,
                ),
                anchors: [for (final item in explicit) item.anchor],
              ),
            ],
    );
  }

  final members = [
    for (final parameter in constructor.formalParameters)
      _resolveMember(parameter),
  ];
  final memberConflicts = [
    for (final member in members)
      if (member.description.status == StructuredDescriptionFactStatus.conflict)
        member.description,
  ];
  final handledExplicitAnchors = <StructuredSourceAnchor>{
    for (final member in members)
      if (member.description.source ==
              StructuredDescriptionSourceKind.explicitParameter ||
          member.description.source ==
              StructuredDescriptionSourceKind.explicitMember ||
          member.description.status == StructuredDescriptionFactStatus.conflict)
        ...member.description.anchors,
  };
  final unassociatedExplicit = [
    for (final item in _allExplicitAnnotations(type))
      if (!handledExplicitAnchors.contains(item.anchor)) item,
  ];
  return StructuredDescriptionModel(
    constructorStatus: StructuredConstructorStatus.resolved,
    constructor: constructor,
    members: members,
    conflicts: [
      ...memberConflicts,
      if (unassociatedExplicit.isNotEmpty)
        StructuredDescriptionFact.conflict(
          message: _unresolvedAssociationMessage(unassociatedExplicit),
          anchors: [for (final item in unassociatedExplicit) item.anchor],
        ),
    ],
  );
}

({StructuredConstructorStatus status, ConstructorElement? constructor})
    _canonicalConstructor(InterfaceType type) {
  final generative = [
    for (final constructor in type.constructors)
      if (!constructor.isFactory &&
          !(constructor.name?.startsWith('_') ?? false))
        constructor,
  ];
  if (generative.isEmpty) {
    return (
      status: StructuredConstructorStatus.unresolved,
      constructor: null,
    );
  }
  for (final constructor in generative) {
    if (_isUnnamed(constructor)) {
      return (
        status: StructuredConstructorStatus.resolved,
        constructor: constructor,
      );
    }
  }
  if (generative.length == 1) {
    return (
      status: StructuredConstructorStatus.resolved,
      constructor: generative.single,
    );
  }
  return (
    status: StructuredConstructorStatus.ambiguous,
    constructor: null,
  );
}

bool _isUnnamed(ConstructorElement constructor) =>
    constructor.name == null ||
    constructor.name!.isEmpty ||
    constructor.name == 'new';

String _unresolvedAssociationMessage(
  List<_ExplicitDescription> annotations, {
  bool constructorUnresolved = false,
}) {
  assert(annotations.isNotEmpty, 'An unresolved diagnostic needs a source.');
  final sites = annotations.map((item) => item.anchor.label).join(', ');
  final identityGap = constructorUnresolved
      ? 'There is no canonical generative constructor and no analyzer identity '
          'link from these sites to one canonical member.'
      : 'There is no analyzer identity link from these sites to one canonical '
          'member.';
  return 'Unresolved RestageDataField annotated site(s): $sites. $identityGap '
      'Use a field-formal (`this.field`), a super-formal chain that terminates '
      'transitively at an analyzer-linked field-formal/member, or a separate '
      'canonical wire DTO.';
}

StructuredMemberDescription _resolveMember(FormalParameterElement parameter) {
  final member = _fieldForParameter(parameter);
  final association = member == null
      ? StructuredMemberAssociationStatus.unresolved
      : StructuredMemberAssociationStatus.resolved;
  final parameterAnnotations = _dataFieldAnnotations(parameter);

  if (association != StructuredMemberAssociationStatus.resolved) {
    final fact = parameterAnnotations.isEmpty
        ? const StructuredDescriptionFact.absent()
        : StructuredDescriptionFact.conflict(
            message: _unresolvedAssociationMessage(parameterAnnotations),
            anchors: [for (final item in parameterAnnotations) item.anchor],
          );
    return StructuredMemberDescription(
      parameter: parameter,
      member: null,
      association: association,
      description: fact,
    );
  }

  final explicit = <_ExplicitDescription>[
    ...parameterAnnotations,
    ..._memberAnnotations(member!),
  ];
  final blank = explicit.where((item) => item.text.trim().isEmpty).toList();
  if (blank.isNotEmpty) {
    return StructuredMemberDescription(
      parameter: parameter,
      member: member,
      association: StructuredMemberAssociationStatus.conflict,
      description: StructuredDescriptionFact.conflict(
        message: 'RestageDataField.description must be non-empty.',
        anchors: [for (final item in explicit) item.anchor],
      ),
    );
  }
  if (explicit.length > 1) {
    return StructuredMemberDescription(
      parameter: parameter,
      member: member,
      association: StructuredMemberAssociationStatus.conflict,
      description: StructuredDescriptionFact.conflict(
        message: 'Keep exactly one RestageDataField annotation for canonical '
            'member "${member.name ?? '<unnamed>'}".',
        anchors: [for (final item in explicit) item.anchor],
      ),
    );
  }
  if (explicit case [final item]) {
    return StructuredMemberDescription(
      parameter: parameter,
      member: member,
      association: association,
      description: StructuredDescriptionFact.present(
        text: item.text.trim(),
        source: parameterAnnotations.contains(item)
            ? StructuredDescriptionSourceKind.explicitParameter
            : StructuredDescriptionSourceKind.explicitMember,
        anchor: item.anchor,
      ),
    );
  }

  final memberDartdoc = stripDartdocSlashes(
    member.documentationComment ?? member.getter?.documentationComment,
  );
  if (memberDartdoc != null && memberDartdoc.isNotEmpty) {
    return StructuredMemberDescription(
      parameter: parameter,
      member: member,
      association: association,
      description: StructuredDescriptionFact.present(
        text: memberDartdoc,
        source: StructuredDescriptionSourceKind.memberDartdoc,
        anchor: _anchor(member, 'member Dartdoc'),
      ),
    );
  }
  final parameterDartdoc = stripDartdocSlashes(parameter.documentationComment);
  if (parameterDartdoc != null && parameterDartdoc.isNotEmpty) {
    return StructuredMemberDescription(
      parameter: parameter,
      member: member,
      association: association,
      description: StructuredDescriptionFact.present(
        text: parameterDartdoc,
        source: StructuredDescriptionSourceKind.resolvedParameterDartdoc,
        anchor: _anchor(parameter, 'constructor-parameter Dartdoc'),
      ),
    );
  }
  return StructuredMemberDescription(
    parameter: parameter,
    member: member,
    association: association,
    description: const StructuredDescriptionFact.absent(),
  );
}

FieldElement? _fieldForParameter(FormalParameterElement parameter) =>
    _fieldForParameterChain(parameter, <Element>{});

FieldElement? _fieldForParameterChain(
  FormalParameterElement parameter,
  Set<Element> visited,
) {
  final declaration = parameter.baseElement;
  if (!visited.add(declaration)) return null;

  final superFormal = parameter is SuperFormalParameterElement
      ? parameter
      : switch (declaration) {
          final SuperFormalParameterElement base => base,
          _ => null,
        };
  if (superFormal != null) {
    final superParameter = superFormal.superConstructorParameter;
    return superParameter == null
        ? null
        : _fieldForParameterChain(superParameter, visited);
  }

  final fieldFormal = parameter is FieldFormalParameterElement
      ? parameter
      : switch (declaration) {
          final FieldFormalParameterElement base => base,
          _ => null,
        };
  if (fieldFormal != null) {
    final field = fieldFormal.field;
    return (field?.isPublic ?? false) ? field : null;
  }
  return null;
}

List<_ExplicitDescription> _memberAnnotations(FieldElement member) {
  final result = <_ExplicitDescription>[
    ..._dataFieldAnnotations(member),
  ];
  final getter = member.getter;
  if (getter != null && getter.isOriginDeclaration) {
    result.addAll(_dataFieldAnnotations(getter));
  }
  return result;
}

List<_ExplicitDescription> _allExplicitAnnotations(InterfaceType type) {
  final result = <_ExplicitDescription>[];
  for (final constructor in type.constructors) {
    for (final parameter in constructor.formalParameters) {
      result.addAll(_dataFieldAnnotations(parameter));
    }
  }
  for (final field in type.element.fields) {
    if (field.isOriginDeclaration) {
      result.addAll(_dataFieldAnnotations(field));
    }
  }
  for (final getter in type.element.getters) {
    if (getter.isOriginDeclaration) {
      result.addAll(_dataFieldAnnotations(getter));
    }
  }
  return result;
}

List<_ExplicitDescription> _dataFieldAnnotations(Element element) {
  final result = <_ExplicitDescription>[];
  final annotations = element.metadata.annotations;
  for (var index = 0; index < annotations.length; index += 1) {
    final annotation = annotations[index];
    final value = annotation.computeConstantValue();
    if (!_isRestageDataField(value)) continue;
    result.add(
      _ExplicitDescription(
        text: value!.getField('description')?.toStringValue() ?? '',
        anchor: _anchor(
          element,
          '${_annotationSiteKind(element)} RestageDataField metadata '
          '#${index + 1}',
        ),
      ),
    );
  }
  return result;
}

String _annotationSiteKind(Element element) => switch (element) {
      FormalParameterElement() => 'constructor parameter',
      GetterElement() => 'getter',
      FieldElement() => 'field',
      _ => 'element',
    };

bool _isRestageDataField(DartObject? value) {
  final type = value?.type;
  if (type is! InterfaceType || type.element.name != 'RestageDataField') {
    return false;
  }
  return type.element.library.identifier ==
      'package:rfw_catalog_schema/src/annotations/restage_data_field.dart';
}

StructuredSourceAnchor _anchor(Element element, String label) {
  final owner = element.baseElement;
  final name = owner.name ?? '<unnamed>';
  return StructuredSourceAnchor(
    libraryUri: owner.library?.identifier ?? '<unknown-library>',
    offset: owner.firstFragment.offset,
    length: name.length,
    label: '$label $name',
  );
}

bool _sameDeclaration(Element? first, Element? second) {
  if (first == null || second == null) return false;
  final firstBase = first.baseElement;
  final secondBase = second.baseElement;
  return identical(firstBase, secondBase) ||
      identical(firstBase.firstFragment, secondBase.firstFragment);
}

final class _ExplicitDescription {
  const _ExplicitDescription({required this.text, required this.anchor});

  final String text;
  final StructuredSourceAnchor anchor;
}
