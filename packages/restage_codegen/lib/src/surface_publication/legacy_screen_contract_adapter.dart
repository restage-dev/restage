// Analyzer-resolved compatibility adapter for deprecated standalone screens.
// ignore_for_file: public_member_api_docs

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/annotation_lookup.dart';
import 'package:restage_codegen/src/helper_registry.dart'
    show libraryUriMatchesOrigin;
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_shared/restage_shared.dart';

const String _restageSdkOrigin = 'package:restage';

@immutable
final class LegacyStandaloneScreenContractInput {
  const LegacyStandaloneScreenContractInput({
    required this.assetId,
    required this.screen,
    required this.surface,
    required this.slug,
    required this.contractVersion,
    required this.capabilities,
  });

  final AssetId assetId;
  final ClassElement screen;
  final Surface surface;
  final String slug;
  final int contractVersion;
  final CapabilityManifest capabilities;

  String get location => '${assetId.path}#${screen.name ?? '<unnamed>'}';
}

@immutable
final class LegacyStandaloneScreenContract {
  const LegacyStandaloneScreenContract({
    required this.input,
    required this.eventSchema,
  });

  final LegacyStandaloneScreenContractInput input;
  final SurfaceScreenEventSchema eventSchema;

  ClassElement get screen => input.screen;
  Surface get surface => input.surface;
  String get slug => input.slug;
  int get contractVersion => input.contractVersion;
  CapabilityManifest get capabilities => input.capabilities;
}

@immutable
final class LegacyStandaloneScreenContractInspection {
  LegacyStandaloneScreenContractInspection({
    required this.contract,
    required List<Issue> issues,
  }) : issues = List.unmodifiable(issues);

  final LegacyStandaloneScreenContract? contract;
  final List<Issue> issues;
}

/// Adapts a roster-admitted deprecated `@ScreenSource` declaration to the
/// strict standalone event facts required by the publication manifest.
///
/// The deprecated static builder remains the sole writer of its descriptor
/// and artifact family. This adapter therefore emits no Dart reference and
/// derives no artifact path.
LegacyStandaloneScreenContractInspection inspectLegacyStandaloneScreenContract(
  LegacyStandaloneScreenContractInput input,
) {
  final issues = <Issue>[];
  final annotation = firstAnnotationFromOriginAny(
    input.screen,
    const {'ScreenSource', 'OnboardingSource'},
    _restageSdkOrigin,
  );
  if (annotation == null ||
      !annotationHasOrigin(annotation, _restageSdkOrigin)) {
    issues.add(
      _issue(
        input,
        IssueCode.unresolvedIdentifier,
        'Legacy standalone publication requires a resolved package:restage '
        '@ScreenSource annotation.',
      ),
    );
    return LegacyStandaloneScreenContractInspection(
      contract: null,
      issues: issues,
    );
  }
  final annotationClass = resolvedAnnotationClass(annotation);
  if (annotationClass?.name != 'ScreenSource') {
    issues.add(
      _issue(
        input,
        IssueCode.unresolvedIdentifier,
        'Legacy screen annotation must resolve to the package:restage '
        'ScreenSource declaration.',
      ),
    );
  }
  final value = annotation.computeConstantValue();
  if (value?.getField('id')?.toStringValue() != input.slug ||
      value?.getField('version')?.toIntValue() != input.contractVersion) {
    issues.add(
      _issue(
        input,
        IssueCode.annotationEvaluationFailed,
        'Legacy @ScreenSource identity and version must match the '
        'roster-normalized publication contract.',
      ),
    );
  }
  if (input.contractVersion < 1) {
    issues.add(
      _issue(
        input,
        IssueCode.annotationEvaluationFailed,
        'Legacy standalone screen contractVersion must be positive.',
      ),
    );
  }

  final events = <SurfaceScreenEvent>[];
  final eventIds = <String>{};
  final fields = input.screen.children
      .whereType<FieldElement>()
      .where(
        (field) => field.isStatic && _isSdkSurfaceEvent(field.type),
      )
      .toList()
    ..sort((left, right) => (left.name ?? '').compareTo(right.name ?? ''));
  for (final field in fields) {
    if (!field.isConst) {
      issues.add(
        _eventIssue(
          input,
          field,
          IssueCode.annotationEvaluationFailed,
          'must be const so its wire ID is stable',
        ),
      );
      continue;
    }
    final id = field.computeConstantValue()?.getField('id')?.toStringValue();
    if (id == null || id.isEmpty) {
      issues.add(
        _eventIssue(
          input,
          field,
          IssueCode.annotationEvaluationFailed,
          'must have a non-empty const ID',
        ),
      );
      continue;
    }
    if (!eventIds.add(id)) {
      issues.add(
        _eventIssue(
          input,
          field,
          IssueCode.duplicateId,
          'duplicates wire ID "$id"',
        ),
      );
      continue;
    }
    final type = field.type as InterfaceType;
    if (type.typeArguments.length != 1) {
      issues.add(
        _eventIssue(
          input,
          field,
          IssueCode.buildMethodTooComplex,
          'must have exactly one resolved type argument',
        ),
      );
      continue;
    }
    final payloadType = type.typeArguments.single;
    final arguments = _eventArguments(
      payloadType,
      input: input,
      field: field,
      issues: issues,
    );
    if (arguments != null) {
      events.add(SurfaceScreenEvent(id: id, arguments: arguments));
    }
  }

  if (issues.isNotEmpty) {
    return LegacyStandaloneScreenContractInspection(
      contract: null,
      issues: issues,
    );
  }
  try {
    return LegacyStandaloneScreenContractInspection(
      contract: LegacyStandaloneScreenContract(
        input: input,
        eventSchema: SurfaceScreenEventSchema(events: events),
      ),
      issues: const [],
    );
  } on FormatException catch (error) {
    return LegacyStandaloneScreenContractInspection(
      contract: null,
      issues: [
        _issue(
          input,
          IssueCode.annotationEvaluationFailed,
          'Invalid legacy standalone screen contract: ${error.message}.',
        ),
      ],
    );
  }
}

SurfaceScreenEventArguments? _eventArguments(
  DartType payloadType, {
  required LegacyStandaloneScreenContractInput input,
  required FieldElement field,
  required List<Issue> issues,
}) {
  if (payloadType is VoidType) {
    return const SurfaceScreenEventNoArguments();
  }
  final shape = _shapeFromType(
    payloadType,
    input: input,
    field: field,
    issues: issues,
  );
  if (shape == null) return null;
  return _isNonNullableStringMap(payloadType)
      ? SurfaceScreenEventObjectArguments(shape)
      : SurfaceScreenEventValueArguments(shape);
}

SurfaceScreenEventShape? _shapeFromType(
  DartType type, {
  required LegacyStandaloneScreenContractInput input,
  required FieldElement field,
  required List<Issue> issues,
}) {
  if (type is DynamicType) {
    _rejectShape(input, field, type, issues, 'dynamic is not supported');
    return null;
  }
  if (type is VoidType) {
    _rejectShape(
      input,
      field,
      type,
      issues,
      'void is legal only as SurfaceEvent<void>',
    );
    return null;
  }
  if (type is! InterfaceType) {
    _rejectShape(
      input,
      field,
      type,
      issues,
      'only the closed scalar/list/string-map algebra is supported',
    );
    return null;
  }
  final element = type.element;
  final isCore = element.library.identifier == 'dart:core';
  if (isCore &&
      element.name == 'Object' &&
      type.typeArguments.isEmpty &&
      type.nullabilitySuffix == NullabilitySuffix.question) {
    return const SurfaceScreenEventScalarShapeV1(
      SurfaceScreenEventScalarKind.jsonValue,
    );
  }
  final shape = _shapeFromInterface(
    type,
    input: input,
    field: field,
    issues: issues,
  );
  if (shape == null) return null;
  if (type.nullabilitySuffix == NullabilitySuffix.question) {
    return SurfaceScreenEventNullableShapeV1(shape);
  }
  if (type.nullabilitySuffix != NullabilitySuffix.none) {
    _rejectShape(
      input,
      field,
      type,
      issues,
      'legacy nullability is not supported',
    );
    return null;
  }
  return shape;
}

SurfaceScreenEventShape? _shapeFromInterface(
  InterfaceType type, {
  required LegacyStandaloneScreenContractInput input,
  required FieldElement field,
  required List<Issue> issues,
}) {
  final element = type.element;
  final isCore = element.library.identifier == 'dart:core';
  final name = element.name;
  if (isCore && type.typeArguments.isEmpty) {
    final scalar = switch (name) {
      'bool' => SurfaceScreenEventScalarKind.boolean,
      'int' => SurfaceScreenEventScalarKind.integer,
      'double' => SurfaceScreenEventScalarKind.doubleValue,
      'String' => SurfaceScreenEventScalarKind.string,
      _ => null,
    };
    if (scalar != null) return SurfaceScreenEventScalarShapeV1(scalar);
  }
  if (isCore && name == 'List') {
    if (type.typeArguments.length != 1) {
      _rejectShape(input, field, type, issues, 'raw List is not supported');
      return null;
    }
    final items = _shapeFromType(
      type.typeArguments.single,
      input: input,
      field: field,
      issues: issues,
    );
    return items == null ? null : SurfaceScreenEventListShapeV1(items);
  }
  if (isCore && name == 'Map') {
    if (type.typeArguments.length != 2 ||
        !_isNonNullableCoreString(type.typeArguments.first)) {
      _rejectShape(
        input,
        field,
        type,
        issues,
        'Map keys must be exactly non-nullable String',
      );
      return null;
    }
    final values = _shapeFromType(
      type.typeArguments.last,
      input: input,
      field: field,
      issues: issues,
    );
    return values == null ? null : SurfaceScreenEventMapShapeV1(values);
  }
  _rejectShape(
    input,
    field,
    type,
    issues,
    'custom and unsupported collection types are not supported',
  );
  return null;
}

void _rejectShape(
  LegacyStandaloneScreenContractInput input,
  FieldElement field,
  DartType type,
  List<Issue> issues,
  String reason,
) {
  issues.add(
    _eventIssue(
      input,
      field,
      IssueCode.buildMethodTooComplex,
      'has unsupported payload type ${type.getDisplayString()}: $reason',
    ),
  );
}

bool _isSdkSurfaceEvent(DartType type) =>
    type is InterfaceType &&
    type.element.name == 'SurfaceEvent' &&
    libraryUriMatchesOrigin(type.element.library.identifier, _restageSdkOrigin);

bool _isNonNullableStringMap(DartType type) =>
    type is InterfaceType &&
    type.element.library.identifier == 'dart:core' &&
    type.element.name == 'Map' &&
    type.nullabilitySuffix == NullabilitySuffix.none &&
    type.typeArguments.length == 2 &&
    _isNonNullableCoreString(type.typeArguments.first);

bool _isNonNullableCoreString(DartType type) =>
    type is InterfaceType &&
    type.element.library.identifier == 'dart:core' &&
    type.element.name == 'String' &&
    type.typeArguments.isEmpty &&
    type.nullabilitySuffix == NullabilitySuffix.none;

Issue _eventIssue(
  LegacyStandaloneScreenContractInput input,
  FieldElement field,
  IssueCode code,
  String detail,
) =>
    _issue(
      input,
      code,
      'Static SurfaceEvent field ${field.name ?? '<unnamed>'} $detail.',
    );

Issue _issue(
  LegacyStandaloneScreenContractInput input,
  IssueCode code,
  String message,
) =>
    Issue(code: code, message: message, location: input.location);
