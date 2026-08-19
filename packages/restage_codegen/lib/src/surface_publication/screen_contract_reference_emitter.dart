// Analyzer-resolved standalone screen contracts and generated references.

import 'dart:convert';

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/annotation_lookup.dart';
import 'package:restage_codegen/src/emit_utils.dart';
import 'package:restage_codegen/src/helper_registry.dart'
    show libraryUriMatchesOrigin;
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_shared/restage_shared.dart';

const String _restageSdkOrigin = 'package:restage';

/// Analyzer-resolved inputs for one independently published `@Screen`.
///
/// The package aggregate builder owns roster admission and artifact assembly.
/// This seam deliberately retains the resolved [screen] identity so event
/// discovery never falls back to Dart names or generated descriptors.
@immutable
final class ResolvedStandaloneScreenContractInput {
  /// Creates a contract-emission input for one categorized screen.
  const ResolvedStandaloneScreenContractInput({
    required this.assetId,
    required this.screen,
    required this.surface,
    required this.slug,
    required this.contractVersion,
    required this.capabilities,
  });

  /// Owning library asset, retained only for diagnostics and generated part
  /// placement. It is never emitted into a standalone reference.
  final AssetId assetId;

  /// Resolved annotated screen class identity.
  final ClassElement screen;

  /// Canonical category of this independently published screen.
  final Surface surface;

  /// Canonical publication slug.
  final String slug;

  /// Positive app-pinned standalone contract version.
  final int contractVersion;

  /// Render capabilities pinned into the generated reference and fingerprint.
  final CapabilityManifest capabilities;

  /// Compact source location used by diagnostics.
  String get location => '${assetId.path}#${screen.name ?? '<unnamed>'}';
}

/// Successful or rejected inspection of one standalone-screen contract.
@immutable
final class StandaloneScreenContractInspection {
  /// Creates an inspection result.
  StandaloneScreenContractInspection({
    required this.contract,
    required List<Issue> issues,
  }) : issues = List.unmodifiable(issues);

  /// The resolved contract when all analyzer and schema checks passed.
  final ResolvedStandaloneScreenContract? contract;

  /// Fail-loud diagnostics for invalid source or contract data.
  final List<Issue> issues;

  /// Whether the input is safe for aggregate publication assembly.
  bool get isValid => contract != null && issues.isEmpty;
}

/// One validated standalone-screen contract ready for later aggregate emission.
@immutable
final class ResolvedStandaloneScreenContract {
  ResolvedStandaloneScreenContract._({
    required this.input,
    required this.eventSchema,
    required this.eventContractHash,
    required this.contractFingerprint,
    required String sdkPrefix,
    required List<_ResolvedScreenEvent> events,
  })  : _sdkPrefix = sdkPrefix,
        _events = List.unmodifiable(events);

  /// Original resolved authoring input.
  final ResolvedStandaloneScreenContractInput input;

  /// Complete independently validated event accepted set for the manifest.
  final SurfaceScreenEventSchemaV1 eventSchema;

  /// Hash produced only by the shared event-contract encoder.
  final String eventContractHash;

  /// Immutable contract-family fingerprint produced by the shared encoder.
  final String contractFingerprint;

  final String _sdkPrefix;
  final List<_ResolvedScreenEvent> _events;

  /// Resolved annotated screen class identity.
  ClassElement get screen => input.screen;

  /// Generated publication category.
  Surface get surface => input.surface;

  /// Generated publication slug.
  String get slug => input.slug;

  /// Generated app-pinned contract version.
  int get contractVersion => input.contractVersion;

  /// Generated render capabilities.
  CapabilityManifest get capabilities => input.capabilities;

  /// Emits the deterministic Dart part containing the typed event contract and
  /// `SurfaceScreenRef<E>` for this screen.
  ///
  /// The output contains no authoritative artifact path. A later aggregate
  /// owner emits the manifest entry that selects the verified artifact closure.
  String emitReferenceDart() => _emitReferenceDart(this);
}

/// Inspects one analyzer-resolved categorized `@Screen` declaration.
///
/// This function is intentionally synchronous: all analyzer work required by
/// this emitter is already represented by
/// [ResolvedStandaloneScreenContractInput].
/// A package aggregate builder can call it after roster/front-end admission and
/// before it writes any generated output family.
StandaloneScreenContractInspection inspectStandaloneScreenContract(
  ResolvedStandaloneScreenContractInput input,
) {
  final issues = <Issue>[];
  final screen = input.screen;
  final annotation = firstAnnotationFromOriginAny(
    screen,
    const {'Screen'},
    _restageSdkOrigin,
  );
  if (annotation == null ||
      !annotationHasOrigin(annotation, _restageSdkOrigin)) {
    issues.add(
      _issue(
        input,
        IssueCode.unresolvedIdentifier,
        'Standalone publication requires a resolved package:restage '
        '@Screen annotation.',
      ),
    );
    return StandaloneScreenContractInspection(contract: null, issues: issues);
  }

  final annotationValue = annotation.computeConstantValue();
  final declaredSurface =
      _surfaceFromValue(annotationValue?.getField('surface'));
  if (declaredSurface == null) {
    issues.add(
      _issue(
        input,
        IssueCode.annotationEvaluationFailed,
        'Independently published @Screen declarations require a resolved '
        'surface: Surface.<category>.',
      ),
    );
  } else if (declaredSurface != input.surface) {
    issues.add(
      _issue(
        input,
        IssueCode.annotationEvaluationFailed,
        '@Screen.surface (${declaredSurface.wireName}) does not match the '
        'normalized publication surface (${input.surface.wireName}).',
      ),
    );
  }
  final declaredId = annotationValue?.getField('id');
  final explicitId = declaredId == null || declaredId.isNull
      ? null
      : declaredId.toStringValue();
  final effectiveSlug = explicitId ?? _fileStem(input.assetId.path);
  if (effectiveSlug != input.slug) {
    issues.add(
      _issue(
        input,
        IssueCode.annotationEvaluationFailed,
        '@Screen identity ($effectiveSlug) does not match the normalized '
        'publication slug (${input.slug}).',
      ),
    );
  }
  final annotationVersion = annotationValue?.getField('version')?.toIntValue();
  if (annotationVersion == null || annotationVersion != input.contractVersion) {
    issues.add(
      _issue(
        input,
        IssueCode.annotationEvaluationFailed,
        '@Screen.version must match the normalized positive contractVersion.',
      ),
    );
  }
  if (!_isSupportedFlutterWidget(screen)) {
    issues.add(
      _issue(
        input,
        IssueCode.unsupportedBaseClass,
        '@Screen ${screen.name ?? '<unnamed>'} must resolve to a Flutter '
        'StatelessWidget or StatefulWidget.',
      ),
    );
  }
  if (!_validSlug(input.slug)) {
    issues.add(
      _issue(
        input,
        IssueCode.annotationEvaluationFailed,
        'Standalone screen slug must be non-empty, trimmed, and NUL-free.',
      ),
    );
  }
  if (input.contractVersion < 1) {
    issues.add(
      _issue(
        input,
        IssueCode.annotationEvaluationFailed,
        'Standalone screen contractVersion must be positive.',
      ),
    );
  }

  final sdkPrefix = _sdkPrefixFor(screen.library);
  if (sdkPrefix == null) {
    issues.add(
      _issue(
        input,
        IssueCode.analyzerResolutionFailed,
        'The owning library must import package:restage with one namespace '
        'that exposes Surface, SurfaceScreenRef, SurfaceScreenEventContract, '
        'CapabilityManifest, and LibraryRequirement for generated code.',
      ),
    );
  }

  final events = <_ResolvedScreenEvent>[];
  final fields = screen.children.whereType<FieldElement>().where((field) {
    return field.isStatic;
  }).toList()
    ..sort((left, right) => (left.name ?? '').compareTo(right.name ?? ''));
  for (final field in fields) {
    final type = field.type;
    if (!_hasSurfaceEventName(type)) continue;
    if (!_isSdkSurfaceEvent(type)) {
      issues.add(
        _issue(
          input,
          IssueCode.unresolvedIdentifier,
          'Static field ${field.name ?? '<unnamed>'} looks like a '
          'SurfaceEvent but does not resolve to package:restage '
          'SurfaceEvent<T>.',
        ),
      );
      continue;
    }
    if (!field.isConst) {
      issues.add(
        _issue(
          input,
          IssueCode.annotationEvaluationFailed,
          'Static SurfaceEvent field ${field.name ?? '<unnamed>'} must be '
          'const so its wire ID is stable.',
        ),
      );
      continue;
    }
    final value = field.computeConstantValue();
    final id = value?.getField('id')?.toStringValue();
    if (id == null || id.isEmpty) {
      issues.add(
        _issue(
          input,
          IssueCode.annotationEvaluationFailed,
          'Static SurfaceEvent field ${field.name ?? '<unnamed>'} must have '
          'a non-empty const ID.',
        ),
      );
      continue;
    }
    final eventType = type as InterfaceType;
    if (eventType.typeArguments.length != 1) {
      issues.add(
        _issue(
          input,
          IssueCode.buildMethodTooComplex,
          'Static SurfaceEvent field ${field.name ?? '<unnamed>'} must have '
          'exactly one resolved type argument.',
        ),
      );
      continue;
    }
    final payloadType = eventType.typeArguments.single;
    final event = _eventFromType(
      field: field,
      id: id,
      payloadType: payloadType,
      input: input,
      issues: issues,
    );
    if (event != null) events.add(event);
  }

  _reportDuplicateEventIds(input, events, issues);
  _reportGeneratedSymbolCollisions(input, events, issues);
  if (issues.isNotEmpty) {
    return StandaloneScreenContractInspection(contract: null, issues: issues);
  }

  final SurfaceScreenEventSchemaV1 schema;
  final String eventContractHash;
  final String contractFingerprint;
  try {
    schema = SurfaceScreenEventSchemaV1(
      events: [for (final event in events) event.schemaEvent],
    );
    eventContractHash = SurfaceScreenEventContractHashV1.hash(schema);
    contractFingerprint = SurfaceScreenContractFingerprintV1.hash(
      sourceKind: SurfaceSourceKind.screen,
      payloadKind: SurfacePayloadKind.blob,
      capabilities: input.capabilities,
      eventContractHash: eventContractHash,
    );
  } on FormatException catch (error) {
    issues.add(
      _issue(
        input,
        IssueCode.annotationEvaluationFailed,
        'Invalid standalone screen contract: ${error.message}.',
      ),
    );
    return StandaloneScreenContractInspection(contract: null, issues: issues);
  }

  return StandaloneScreenContractInspection(
    contract: ResolvedStandaloneScreenContract._(
      input: input,
      eventSchema: schema,
      eventContractHash: eventContractHash,
      contractFingerprint: contractFingerprint,
      sdkPrefix: sdkPrefix!,
      events: events,
    ),
    issues: issues,
  );
}

_ResolvedScreenEvent? _eventFromType({
  required FieldElement field,
  required String id,
  required DartType payloadType,
  required ResolvedStandaloneScreenContractInput input,
  required List<Issue> issues,
}) {
  if (payloadType is VoidType) {
    return _ResolvedScreenEvent(
      field: field,
      id: id,
      arguments: const SurfaceScreenEventNoArgumentsV1(),
      dartShape: null,
    );
  }
  final shape = _shapeFromType(
    payloadType,
    input: input,
    field: field,
    issues: issues,
  );
  if (shape == null) return null;
  final isObject = _isNonNullableStringMap(payloadType);
  return _ResolvedScreenEvent(
    field: field,
    id: id,
    arguments: isObject
        ? SurfaceScreenEventObjectArgumentsV1(shape.schemaShape)
        : SurfaceScreenEventValueArgumentsV1(shape.schemaShape),
    dartShape: shape,
  );
}

_DartEventShape? _shapeFromType(
  DartType type, {
  required ResolvedStandaloneScreenContractInput input,
  required FieldElement field,
  required List<Issue> issues,
}) {
  void reject(String reason) {
    issues.add(
      _issue(
        input,
        IssueCode.buildMethodTooComplex,
        'Static SurfaceEvent field ${field.name ?? '<unnamed>'} has '
        'unsupported payload type ${type.getDisplayString()}: $reason.',
      ),
    );
  }

  if (type is DynamicType) {
    reject('dynamic is not part of the standalone event algebra');
    return null;
  }
  if (type is VoidType) {
    reject('void is legal only as SurfaceEvent<void>');
    return null;
  }
  if (type is! InterfaceType) {
    reject('only the closed scalar/list/string-map algebra is supported');
    return null;
  }

  final element = type.element;
  final isCore = element.library.identifier == 'dart:core';
  final name = element.name;
  if (isCore &&
      name == 'Object' &&
      type.typeArguments.isEmpty &&
      type.nullabilitySuffix == NullabilitySuffix.question) {
    return const _ScalarDartEventShape(
      dartType: 'Object?',
      scalar: SurfaceScreenEventScalarKindV1.jsonValue,
    );
  }
  if (type.nullabilitySuffix == NullabilitySuffix.question) {
    final value = _shapeFromInterface(
      type,
      input: input,
      field: field,
      issues: issues,
    );
    return value == null ? null : _NullableDartEventShape(value);
  }
  if (type.nullabilitySuffix != NullabilitySuffix.none) {
    reject('legacy nullability is not supported');
    return null;
  }

  return _shapeFromInterface(
    type,
    input: input,
    field: field,
    issues: issues,
  );
}

_DartEventShape? _shapeFromInterface(
  InterfaceType type, {
  required ResolvedStandaloneScreenContractInput input,
  required FieldElement field,
  required List<Issue> issues,
}) {
  void reject(String reason) {
    issues.add(
      _issue(
        input,
        IssueCode.buildMethodTooComplex,
        'Static SurfaceEvent field ${field.name ?? '<unnamed>'} has '
        'unsupported payload type ${type.getDisplayString()}: $reason.',
      ),
    );
  }

  final element = type.element;
  final isCore = element.library.identifier == 'dart:core';
  final name = element.name;

  if (isCore && type.typeArguments.isEmpty) {
    final scalar = switch (name) {
      'bool' => SurfaceScreenEventScalarKindV1.boolean,
      'int' => SurfaceScreenEventScalarKindV1.integer,
      'double' => SurfaceScreenEventScalarKindV1.doubleValue,
      'String' => SurfaceScreenEventScalarKindV1.string,
      _ => null,
    };
    if (scalar != null) {
      return _ScalarDartEventShape(dartType: name!, scalar: scalar);
    }
  }

  if (isCore && name == 'List') {
    if (type.typeArguments.length != 1) {
      reject('raw List collections are not supported');
      return null;
    }
    final items = _shapeFromType(
      type.typeArguments.single,
      input: input,
      field: field,
      issues: issues,
    );
    return items == null ? null : _ListDartEventShape(items);
  }
  if (isCore && name == 'Map') {
    if (type.typeArguments.length != 2) {
      reject('raw Map collections are not supported');
      return null;
    }
    if (!_isNonNullableCoreString(type.typeArguments.first)) {
      reject('Map keys must be exactly non-nullable String');
      return null;
    }
    final values = _shapeFromType(
      type.typeArguments.last,
      input: input,
      field: field,
      issues: issues,
    );
    return values == null ? null : _MapDartEventShape(values);
  }

  reject('custom and unsupported collection types are not supported');
  return null;
}

void _reportDuplicateEventIds(
  ResolvedStandaloneScreenContractInput input,
  List<_ResolvedScreenEvent> events,
  List<Issue> issues,
) {
  final byId = <String, List<_ResolvedScreenEvent>>{};
  for (final event in events) {
    (byId[event.id] ??= <_ResolvedScreenEvent>[]).add(event);
  }
  final duplicateIds = byId.entries
      .where((entry) => entry.value.length > 1)
      .toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  for (final entry in duplicateIds) {
    final fields =
        entry.value.map((event) => event.field.name ?? '<unnamed>').join(', ');
    issues.add(
      _issue(
        input,
        IssueCode.duplicateId,
        'Duplicate standalone SurfaceEvent ID "${entry.key}" declared by '
        '$fields.',
      ),
    );
  }
}

void _reportGeneratedSymbolCollisions(
  ResolvedStandaloneScreenContractInput input,
  List<_ResolvedScreenEvent> events,
  List<Issue> issues,
) {
  final screenName = input.screen.name;
  if (screenName == null || screenName.isEmpty) {
    issues.add(
      _issue(
        input,
        IssueCode.generatedSymbolCollision,
        'Standalone screen declarations require a stable Dart class name.',
      ),
    );
    return;
  }
  final symbols = _generatedSymbols(screenName, events);
  final duplicateGenerated = <String>{};
  final seen = <String>{};
  for (final symbol in symbols) {
    if (!seen.add(symbol)) duplicateGenerated.add(symbol);
  }
  for (final symbol in duplicateGenerated.toList()..sort()) {
    issues.add(
      _issue(
        input,
        IssueCode.generatedSymbolCollision,
        'Standalone event fields would generate colliding symbol $symbol.',
      ),
    );
  }

  final existing = _topLevelNames(input.screen.library);
  for (final symbol in symbols.toSet().toList()..sort()) {
    if (!existing.contains(symbol)) continue;
    issues.add(
      _issue(
        input,
        IssueCode.generatedSymbolCollision,
        'Generated standalone screen symbol $symbol already exists in '
        '${input.assetId.path}.',
      ),
    );
  }
}

String _emitReferenceDart(ResolvedStandaloneScreenContract contract) {
  final screenName = contract.screen.name!;
  final screenStem = _pascalIdentifier(screenName, fallback: 'SurfaceScreen');
  final refStem = _lowerCamelIdentifier(screenName, fallback: 'surfaceScreen');
  final eventBase = '${screenStem}Event';
  final eventContractName = '_${refStem}Events';
  final decoderName = '_decodeValidated$eventBase';
  final refName = '${refStem}Ref';
  final sdk = contract._sdkPrefix;
  final sourceFile = _fileName(contract.input.assetId.path);
  final buffer = StringBuffer()
    ..writeln('part of ${_dartString(sourceFile)};')
    ..writeln();

  if (contract._events.isNotEmpty) {
    buffer
      ..writeln('sealed class $eventBase {')
      ..writeln('  const $eventBase();')
      ..writeln('}')
      ..writeln();
    for (final event in _eventsInSchemaOrder(contract)) {
      final eventClass = _eventClassName(screenStem, event.field.name);
      buffer.writeln('final class $eventClass extends $eventBase {');
      final shape = event.dartShape;
      if (shape == null) {
        buffer.writeln('  const $eventClass();');
      } else {
        final parameter = event.arguments is SurfaceScreenEventObjectArgumentsV1
            ? 'arguments'
            : 'value';
        buffer
          ..writeln('  const $eventClass(this.$parameter);')
          ..writeln()
          ..writeln('  final ${shape.dartType} $parameter;');
      }
      buffer
        ..writeln('}')
        ..writeln();
    }
    buffer
      ..writeln('final $eventContractName =')
      ..writeln('    ${sdk}SurfaceScreenEventContract<$eventBase>.generated(')
      ..writeln('  hash: ${_dartString(contract.eventContractHash)},')
      ..writeln('  decodeValidated: $decoderName,')
      ..writeln(');')
      ..writeln();
  } else {
    buffer
      ..writeln('final $eventContractName =')
      ..writeln('    const ${sdk}SurfaceScreenEventContract<Never>.none(')
      ..writeln('  hash: ${_dartString(contract.eventContractHash)},')
      ..writeln(');')
      ..writeln();
  }

  final referenceEventType = contract._events.isEmpty ? 'Never' : eventBase;
  buffer
    ..writeln(
      'final $refName = ${sdk}SurfaceScreenRef<$referenceEventType>.generated(',
    )
    ..writeln('  slug: ${_dartString(contract.slug)},')
    ..writeln('  contractVersion: ${contract.contractVersion},')
    ..writeln(
      '  capabilities: ${_capabilitySource(contract.capabilities, sdk)},',
    )
    ..writeln('  surface: ${sdk}Surface.${contract.surface.name},')
    ..writeln(
      '  contractFingerprint: ${_dartString(contract.contractFingerprint)},',
    )
    ..writeln('  eventContract: $eventContractName,')
    ..writeln(');');

  if (contract._events.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('$eventBase $decoderName(')
      ..writeln('  String name,')
      ..writeln('  Map<String, Object?> arguments,')
      ..writeln(') {')
      ..writeln('  switch (name) {');
    for (final event in _eventsInSchemaOrder(contract)) {
      final eventClass = _eventClassName(screenStem, event.field.name);
      buffer.writeln('    case ${_dartString(event.id)}:');
      if (event.dartShape == null) {
        buffer.writeln('      return const $eventClass();');
      } else {
        final source = event.arguments is SurfaceScreenEventObjectArgumentsV1
            ? 'arguments'
            : "arguments['value']";
        buffer.writeln(
          '      return $eventClass(${event.dartShape!.decode(source)});',
        );
      }
    }
    buffer
      ..writeln('  }')
      ..writeln(
        '  throw FormatException(${_dartString('Invalid $screenStem event "')}'
        ' + name + ${_dartString('".')} );',
      )
      ..writeln('}');
  }

  return '${formatGeneratedDart(buffer.toString()).trimRight()}\n';
}

Iterable<_ResolvedScreenEvent> _eventsInSchemaOrder(
  ResolvedStandaloneScreenContract contract,
) sync* {
  for (final schemaEvent in contract.eventSchema.events) {
    yield contract._events.singleWhere((event) => event.id == schemaEvent.id);
  }
}

String _capabilitySource(CapabilityManifest capabilities, String sdk) {
  final buffer = StringBuffer()
    ..writeln('${sdk}CapabilityManifest(')
    ..writeln('  builtInFloor: ${capabilities.builtInFloor},')
    ..writeln('  requiredLibraries: const [');
  for (final requirement in capabilities.requiredLibraries) {
    buffer
      ..writeln('    ${sdk}LibraryRequirement(')
      ..writeln('      namespace: ${_dartString(requirement.namespace)},')
      ..writeln('      minVersion: ${requirement.minVersion},')
      ..writeln('    ),');
  }
  buffer
    ..writeln('  ],')
    ..write(')');
  return buffer.toString();
}

List<String> _generatedSymbols(
  String screenName,
  Iterable<_ResolvedScreenEvent> events,
) {
  final screenStem = _pascalIdentifier(screenName, fallback: 'SurfaceScreen');
  final refStem = _lowerCamelIdentifier(screenName, fallback: 'surfaceScreen');
  return <String>[
    '${screenStem}Event',
    '_${refStem}Events',
    '_decodeValidated${screenStem}Event',
    '${refStem}Ref',
    for (final event in events) _eventClassName(screenStem, event.field.name),
  ];
}

String _eventClassName(String screenStem, String? fieldName) =>
    '$screenStem${_pascalIdentifier(fieldName ?? '', fallback: 'Event')}Event';

Set<String> _topLevelNames(LibraryElement library) {
  final names = <String>{};
  for (final element in <Iterable<Element>>[
    library.classes,
    library.enums,
    library.mixins,
    library.extensions,
    library.extensionTypes,
    library.typeAliases,
    library.topLevelFunctions,
    library.topLevelVariables,
    library.getters,
    library.setters,
  ]) {
    for (final item in element) {
      final name = item.name;
      if (name != null && name.isNotEmpty) names.add(name);
      final lookup = item.lookupName;
      if (lookup != null && lookup.isNotEmpty) names.add(lookup);
    }
  }
  return names;
}

String? _sdkPrefixFor(LibraryElement library) {
  final candidates = <String>[];
  const symbols = <String>{
    'Surface',
    'SurfaceScreenRef',
    'SurfaceScreenEventContract',
    'CapabilityManifest',
    'LibraryRequirement',
  };
  for (final import in library.firstFragment.libraryImports) {
    final imported = import.importedLibrary;
    if (imported == null ||
        !libraryUriMatchesOrigin(imported.identifier, _restageSdkOrigin)) {
      continue;
    }
    final prefix = import.prefix?.name;
    final visible = symbols.every((symbol) {
      final lookup = prefix == null ? symbol : '$prefix.$symbol';
      return import.namespace.get2(lookup) != null;
    });
    if (visible) candidates.add(prefix == null ? '' : '$prefix.');
  }
  if (candidates.isEmpty) return null;
  candidates.sort((left, right) {
    if (left.isEmpty) return -1;
    if (right.isEmpty) return 1;
    return left.compareTo(right);
  });
  return candidates.first;
}

Surface? _surfaceFromValue(DartObject? value) {
  if (value == null || value.isNull) return null;
  final wireName = value.getField('wireName')?.toStringValue();
  if (wireName == null) return null;
  for (final surface in Surface.values) {
    if (surface.wireName == wireName) return surface;
  }
  return null;
}

bool _isSupportedFlutterWidget(ClassElement element) {
  for (var current = element.supertype; current != null;) {
    final superElement = current.element;
    if ((superElement.name == 'StatelessWidget' ||
            superElement.name == 'StatefulWidget') &&
        superElement.library.identifier.startsWith('package:flutter/')) {
      return true;
    }
    current = superElement.supertype;
  }
  return false;
}

bool _hasSurfaceEventName(DartType type) =>
    type is InterfaceType && type.element.name == 'SurfaceEvent';

bool _isSdkSurfaceEvent(DartType type) =>
    type is InterfaceType &&
    type.element.name == 'SurfaceEvent' &&
    libraryUriMatchesOrigin(type.element.library.identifier, _restageSdkOrigin);

bool _isNonNullableStringMap(DartType type) {
  if (type is! InterfaceType ||
      type.element.library.identifier != 'dart:core' ||
      type.element.name != 'Map' ||
      type.nullabilitySuffix != NullabilitySuffix.none ||
      type.typeArguments.length != 2) {
    return false;
  }
  return _isNonNullableCoreString(type.typeArguments.first);
}

bool _isNonNullableCoreString(DartType type) =>
    type is InterfaceType &&
    type.element.library.identifier == 'dart:core' &&
    type.element.name == 'String' &&
    type.typeArguments.isEmpty &&
    type.nullabilitySuffix == NullabilitySuffix.none;

bool _validSlug(String value) =>
    value.isNotEmpty && value.trim() == value && !value.contains('\u0000');

Issue _issue(
  ResolvedStandaloneScreenContractInput input,
  IssueCode code,
  String message,
) =>
    Issue(code: code, message: message, location: input.location);

String _fileName(String path) {
  final slash = path.lastIndexOf('/');
  return slash == -1 ? path : path.substring(slash + 1);
}

String _fileStem(String path) {
  final fileName = _fileName(path);
  return fileName.endsWith('.dart')
      ? fileName.substring(0, fileName.length - '.dart'.length)
      : fileName;
}

String _dartString(String value) => jsonEncode(value).replaceAll(r'$', r'\$');

String _pascalIdentifier(String value, {required String fallback}) {
  final words = value
      .replaceFirst(RegExp('^_+'), '')
      .split('_')
      .where((word) => word.isNotEmpty);
  final result = words
      .map(
        (word) => '${word.substring(0, 1).toUpperCase()}${word.substring(1)}',
      )
      .join();
  return result.isEmpty ? fallback : result;
}

String _lowerCamelIdentifier(String value, {required String fallback}) {
  final pascal = _pascalIdentifier(value, fallback: fallback);
  return '${pascal.substring(0, 1).toLowerCase()}${pascal.substring(1)}';
}

@immutable
final class _ResolvedScreenEvent {
  const _ResolvedScreenEvent({
    required this.field,
    required this.id,
    required this.arguments,
    required this.dartShape,
  });

  final FieldElement field;
  final String id;
  final SurfaceScreenEventArgumentsV1 arguments;
  final _DartEventShape? dartShape;

  SurfaceScreenEventV1 get schemaEvent => SurfaceScreenEventV1(
        id: id,
        arguments: arguments,
      );
}

sealed class _DartEventShape {
  const _DartEventShape();

  String get dartType;
  SurfaceScreenEventShapeV1 get schemaShape;
  String decode(String source);
}

final class _ScalarDartEventShape extends _DartEventShape {
  const _ScalarDartEventShape({
    required this.dartType,
    required this.scalar,
  });

  @override
  final String dartType;
  final SurfaceScreenEventScalarKindV1 scalar;

  @override
  SurfaceScreenEventShapeV1 get schemaShape =>
      SurfaceScreenEventScalarShapeV1(scalar);

  @override
  String decode(String source) =>
      scalar == SurfaceScreenEventScalarKindV1.jsonValue
          ? source
          : '$source as $dartType';
}

final class _NullableDartEventShape extends _DartEventShape {
  const _NullableDartEventShape(this.value);

  final _DartEventShape value;

  @override
  String get dartType => '${value.dartType}?';

  @override
  SurfaceScreenEventShapeV1 get schemaShape =>
      SurfaceScreenEventNullableShapeV1(value.schemaShape);

  @override
  String decode(String source) =>
      '$source == null ? null : ${value.decode(source)}';
}

final class _ListDartEventShape extends _DartEventShape {
  const _ListDartEventShape(this.items);

  final _DartEventShape items;

  @override
  String get dartType => 'List<${items.dartType}>';

  @override
  SurfaceScreenEventShapeV1 get schemaShape =>
      SurfaceScreenEventListShapeV1(items.schemaShape);

  @override
  String decode(String source) => <String>[
        'List<${items.dartType}>.unmodifiable(',
        '($source as List<Object?>).map((item) => ${items.decode('item')}),',
        ')',
      ].join();
}

final class _MapDartEventShape extends _DartEventShape {
  const _MapDartEventShape(this.values);

  final _DartEventShape values;

  @override
  String get dartType => 'Map<String, ${values.dartType}>';

  @override
  SurfaceScreenEventShapeV1 get schemaShape =>
      SurfaceScreenEventMapShapeV1(values.schemaShape);

  @override
  String decode(String source) => <String>[
        'Map<String, ${values.dartType}>.unmodifiable(',
        '($source as Map<Object?, Object?>).map(',
        '(key, mapValue) => MapEntry<String, ${values.dartType}>(',
        'key as String, ${values.decode('mapValue')}),',
        '),',
        ')',
      ].join();
}
