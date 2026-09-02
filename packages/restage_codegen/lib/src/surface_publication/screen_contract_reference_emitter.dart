// Analyzer-resolved standalone screen contracts and generated references.

import 'dart:convert';

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/annotation_lookup.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/emit_utils.dart';
import 'package:restage_codegen/src/helper_registry.dart'
    show libraryUriMatchesOrigin;
import 'package:restage_codegen/src/host_data_shape.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/owning_library_namespace.dart';
import 'package:restage_codegen/src/surface_publication/generated_handle_names.dart';
import 'package:restage_codegen/src/surface_publication/host_data_contract.dart';
import 'package:restage_codegen/src/surface_publication/output_placement.dart';
import 'package:restage_shared/restage_shared.dart';

const String _restageSdkOrigin = 'package:restage';
const String _flutterOrigin = 'package:flutter';

/// Hash and length of the exact bytes a screen's compiled blob and capability
/// sidecar contribute to its authored library's `.rsbundle`.
///
/// Populated only by the caller that already holds those exact bytes in
/// memory (the same objects that become the bundle entries), so the sha256
/// values here are guaranteed byte-identical to what `RestageBundleCodec`
/// records — never a second, independent serialization of the same content.
@immutable
final class ResolvedScreenBundleEntryMetadata {
  /// Creates the bundle-entry metadata pair for one screen.
  const ResolvedScreenBundleEntryMetadata({
    required this.blobSha256,
    required this.blobByteLength,
    required this.sidecarSha256,
    required this.sidecarByteLength,
    this.blobPath,
    this.sidecarPath,
  });

  /// `sha256:<hex>` of the exact compiled screen blob bytes.
  final String blobSha256;

  /// Byte length of the exact compiled screen blob.
  final int blobByteLength;

  /// Logical path of the exact compiled screen blob when known.
  final String? blobPath;

  /// `sha256:<hex>` of the exact capability sidecar bytes.
  final String sidecarSha256;

  /// Byte length of the exact capability sidecar.
  final int sidecarByteLength;

  /// Logical path of the exact capability sidecar when known.
  final String? sidecarPath;
}

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
    required this.rootParams,
    List<RootContextParam>? constructorParams,
    this.mountConstructorProblem,
    this.plan,
    this.bundleEntryMetadata,
  }) : constructorParams = constructorParams ?? rootParams;

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

  /// Placement authority for this library's generated part, or `null` for
  /// the default layout.
  final RestageOutputPlacementPlan? plan;

  /// This screen's exact compiled blob/sidecar bundle-entry hashes and
  /// lengths, or `null` when the caller has none to offer.
  ///
  /// Required only when [plan] resolves `bundled_runtime: true` — see
  /// [_emitReferenceDart], which fails loudly rather than silently omitting
  /// the bundle locator a bundled-runtime package must always carry.
  final ResolvedScreenBundleEntryMetadata? bundleEntryMetadata;

  /// The package-relative path of this library's one generated Dart part.
  String get generatedPartPath => (plan ?? RestageOutputPlacementPlan.defaults)
      .forLibrary(assetId.path)
      .neutralPartPath;

  /// Render capabilities pinned into the generated reference and fingerprint.
  final CapabilityManifest capabilities;

  /// Resolved unnamed-constructor parameters in declaration order.
  final List<RootContextParam> rootParams;

  /// Every resolved unnamed-constructor formal in declaration order.
  final List<RootContextParam> constructorParams;

  /// Why the selected constructor cannot preserve its key value in a mount.
  final String? mountConstructorProblem;

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
    required this.hostDataContract,
    required String sdkPrefix,
    required List<_ResolvedScreenEvent> events,
    required _ResolvedScreenMount? mount,
    required this.mountOmissionMessage,
  })  : _sdkPrefix = sdkPrefix,
        _events = List.unmodifiable(events),
        _mount = mount;

  /// Original resolved authoring input.
  final ResolvedStandaloneScreenContractInput input;

  /// Complete independently validated event accepted set for the manifest.
  final SurfaceScreenEventSchema eventSchema;

  /// Hash produced only by the shared event-contract encoder.
  final String eventContractHash;

  /// Immutable contract-family fingerprint produced by the shared encoder.
  final String contractFingerprint;

  /// Host-supplied inputs this screen declares, empty when it declares none.
  final SurfaceScreenHostDataSchema hostDataContract;

  final String _sdkPrefix;
  final List<_ResolvedScreenEvent> _events;
  final _ResolvedScreenMount? _mount;

  /// Non-blocking explanation when the generated mount is unavailable.
  final String? mountOmissionMessage;

  /// Exact top-level declarations emitted for this screen.
  Set<String> get generatedTopLevelSymbols => Set.unmodifiable(
        _generatedTopLevelSymbols(
          screen.name!,
          _events,
          _mount,
        ),
      );

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
  String emitReferenceDart({
    String? measurementPublicationDraftDigest,
  }) =>
      _emitReferenceDart(
        this,
        measurementPublicationDraftDigest: measurementPublicationDraftDigest,
      );
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
  final declaredSurface = _surfaceFromValue(
    annotationValue?.getField('surface'),
  );
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
  final mountResolution = screen.name == null || screen.name!.isEmpty
      ? (mount: null, message: null)
      : _resolveScreenMount(
          input,
          reservedGeneratedSymbols: _referenceGeneratedTopLevelSymbols(
            screen.name!,
            events,
          ).toSet(),
        );
  _reportGeneratedSymbolCollisions(
    input,
    _generatedTopLevelSymbols(
      screen.name ?? '',
      events,
      mountResolution.mount,
    ),
    issues,
  );
  if (issues.isNotEmpty) {
    return StandaloneScreenContractInspection(contract: null, issues: issues);
  }

  final SurfaceScreenEventSchema schema;
  final String eventContractHash;
  final String contractFingerprint;
  final SurfaceScreenHostDataSchema hostDataContract;
  try {
    schema = SurfaceScreenEventSchema(
      events: [for (final event in events) event.schemaEvent],
    );
    eventContractHash = SurfaceScreenEventContractHash.hash(schema);
    hostDataContract = hostDataContractOf(input.rootParams);
    contractFingerprint = SurfaceScreenContractFingerprint.hash(
      sourceKind: SurfaceSourceKind.screen,
      payloadKind: SurfacePayloadKind.blob,
      capabilities: input.capabilities,
      eventContractHash: eventContractHash,
      hostDataContractHash:
          SurfaceScreenHostDataContractHash.hash(hostDataContract),
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

  final mountOmissionMessage = switch (mountResolution.message) {
    null => null,
    final message when hostDataContract.isEmpty => message,
    // Without the generated mount, the declared host data reaches the screen
    // only when a hand-written host supplies it through its render context.
    final message => '$message The screen declares host-supplied inputs; a '
        'host mounting it directly must supply them through its render '
        'context.',
  };

  return StandaloneScreenContractInspection(
    contract: ResolvedStandaloneScreenContract._(
      input: input,
      eventSchema: schema,
      eventContractHash: eventContractHash,
      contractFingerprint: contractFingerprint,
      hostDataContract: hostDataContract,
      sdkPrefix: sdkPrefix!,
      events: events,
      mount: mountResolution.mount,
      mountOmissionMessage: mountOmissionMessage,
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
      arguments: const SurfaceScreenEventNoArguments(),
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
        ? SurfaceScreenEventObjectArguments(shape.schemaShape)
        : SurfaceScreenEventValueArguments(shape.schemaShape),
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
      scalar: SurfaceScreenEventScalarKind.jsonValue,
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
      'bool' => SurfaceScreenEventScalarKind.boolean,
      'int' => SurfaceScreenEventScalarKind.integer,
      'double' => SurfaceScreenEventScalarKind.doubleValue,
      'String' => SurfaceScreenEventScalarKind.string,
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
  List<String> symbols,
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
        'Standalone declarations would generate colliding symbol $symbol.',
      ),
    );
  }

  final existing = _owningLibrarySourceNames(
    input,
    OwningLibraryNamespace(input.screen.library),
  );
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

({
  _ResolvedScreenMount? mount,
  String? message,
}) _resolveScreenMount(
  ResolvedStandaloneScreenContractInput input, {
  required Set<String> reservedGeneratedSymbols,
}) {
  final screen = input.screen;
  final screenName = screen.name!;
  final mountName = generatedSurfaceName(
    screenName,
    fallback: 'SurfaceScreen',
  );
  String omitted(String reason) =>
      'Generated screen mount $mountName was omitted because $reason.';

  final namespace = OwningLibraryNamespace(screen.library);
  final sourceNames = _owningLibrarySourceNames(input, namespace);

  final constructorResult = _resolveMountConstructorContract(
    input,
    reservedNames: {
      ...sourceNames,
      ...reservedGeneratedSymbols,
      mountName,
    },
  );
  final mountConstructor = constructorResult.constructor;
  if (mountConstructor == null) {
    return (
      mount: null,
      message: omitted(constructorResult.reason!),
    );
  }

  if (sourceNames.contains(mountName) ||
      reservedGeneratedSymbols.contains(mountName)) {
    return (
      mount: null,
      message: omitted('$mountName already exists in ${input.assetId.path}'),
    );
  }

  final sdk = namespace.prefixForOrigin(
    _restageSdkOrigin,
    const {
      'RestageScreen',
      'SurfaceScreenUnavailablePolicy',
      'SurfaceScreenResolver',
      'SurfaceScreenUnavailableError',
    },
  );
  if (sdk == null) {
    return (
      mount: null,
      message: omitted(
        'the owning library does not expose the required Restage widget '
        'symbols in one namespace',
      ),
    );
  }

  final flutter = namespace.prefixForOrigin(
    _flutterOrigin,
    {
      'StatelessWidget',
      'Widget',
      'BuildContext',
      'ValueChanged',
      'WidgetBuilder',
      if (mountConstructor.requiresKeyType) 'Key',
    },
  );
  if (flutter == null) {
    return (
      mount: null,
      message: omitted(
        'the owning library does not expose the required Flutter widget '
        'symbols in one namespace',
      ),
    );
  }

  return (
    mount: _ResolvedScreenMount(
      sdk: sdk,
      flutter: flutter,
      constructor: mountConstructor,
    ),
    message: null,
  );
}

({
  _ResolvedMountConstructorContract? constructor,
  String? reason,
}) _resolveMountConstructorContract(
  ResolvedStandaloneScreenContractInput input, {
  required Set<String> reservedNames,
}) {
  final screen = input.screen;
  if (screen.typeParameters.isNotEmpty) {
    for (final parameter in input.constructorParams) {
      final typeCode = parameter.typeCode ?? '';
      for (final typeParameter in screen.typeParameters) {
        final name = typeParameter.name;
        if (name != null &&
            RegExp('(^|[^A-Za-z0-9_])${RegExp.escape(name)}'
                    r'([^A-Za-z0-9_]|$)')
                .hasMatch(typeCode)) {
          return (
            constructor: null,
            reason: '${_dartString(parameter.name)} depends on the screen type '
                'parameter ${_dartString(name)}',
          );
        }
      }
    }
    final name = screen.typeParameters.first.name ?? '<unnamed>';
    return (
      constructor: null,
      reason: '${screen.name} declares the screen type parameter '
          '${_dartString(name)}',
    );
  }

  final constructor = screen.unnamedConstructor;
  if (constructor == null) {
    return (
      constructor: null,
      reason: '${screen.name} has no unnamed constructor',
    );
  }
  if (constructor.isFactory &&
      !_redirectsToGenerativeConstructor(constructor)) {
    return (
      constructor: null,
      reason: '${screen.name} has a non-redirecting unnamed factory',
    );
  }
  if (screen.isAbstract && !constructor.isFactory) {
    return (
      constructor: null,
      reason: '${screen.name} cannot be constructed',
    );
  }
  if (input.mountConstructorProblem case final problem?) {
    return (constructor: null, reason: problem);
  }

  const controls = {
    'onEvent',
    'resolver',
    'onUnavailable',
    'loadingBuilder',
  };
  final captureNames = <String>{
    ...controls,
    'build',
    for (final parameter in constructor.formalParameters)
      if (parameter.name case final name? when name.isNotEmpty) name,
    for (var index = 0; index < constructor.formalParameters.length; index++)
      '_restageArgument$index',
  };
  final parameters = <_ResolvedMountParameter>[];
  if (constructor.formalParameters.length != input.constructorParams.length) {
    return (
      constructor: null,
      reason: 'its constructor description is unavailable',
    );
  }
  for (var index = 0; index < constructor.formalParameters.length; index++) {
    final formal = constructor.formalParameters[index];
    final name = formal.name;
    if (name == null || name.isEmpty) {
      return (
        constructor: null,
        reason: 'its constructor description is unavailable',
      );
    }
    final kind = _mountParameterKind(formal);
    final root = input.constructorParams[index];
    if (root.name != name || root.kind != kind) {
      return (
        constructor: null,
        reason: 'its constructor description is unavailable',
      );
    }
    if (controls.contains(name)) {
      return (
        constructor: null,
        reason: '${screen.name} declares the reserved constructor parameter '
            '${_dartString(name)}',
      );
    }
    if (root.mountDefaultProblem != null) {
      return (
        constructor: null,
        reason: 'the default for ${_dartString(name)} has no visible spelling',
      );
    }
    final typeCode = root.typeCode;
    if (root.forwardsFlutterKey &&
        root.usesStatelessWidgetSuperFormal &&
        root.hasExplicitType &&
        !(typeCode?.trimRight().endsWith('?') ?? true) &&
        (root.isRequired ||
            root.kind == RootContextParamKind.requiredPositional ||
            root.kind == RootContextParamKind.optionalPositional)) {
      return (
        constructor: null,
        reason: 'its required non-nullable key cannot reach both the surface '
            'and its fallback widget; declare the key type as nullable',
      );
    }
    final implicitSuperKey = root.forwardsFlutterKey &&
        root.usesStatelessWidgetSuperFormal &&
        !root.hasExplicitType;
    if ((typeCode == null || typeCode.trim().isEmpty) && !implicitSuperKey) {
      return (
        constructor: null,
        reason: '${_dartString(name)} has no reusable Dart type spelling',
      );
    }
    _ResolvedMountDefaultBinding? defaultBinding;
    if (root.mountDefaultValueCode case final expressionCode?) {
      if (typeCode == null || typeCode.trim().isEmpty) {
        return (
          constructor: null,
          reason: 'the default for ${_dartString(name)} has no reusable Dart '
              'type spelling',
        );
      }
      final bindingName = _mountDefaultBindingName(screen.name!, index);
      if (reservedNames.contains(bindingName) ||
          captureNames.contains(bindingName)) {
        return (
          constructor: null,
          reason: 'the generated default binding $bindingName is already '
              'visible in ${input.assetId.path}',
        );
      }
      reservedNames.add(bindingName);
      defaultBinding = _ResolvedMountDefaultBinding(
        name: bindingName,
        typeCode: typeCode,
        expressionCode: expressionCode,
      );
    }
    parameters.add(
      _ResolvedMountParameter.value(
        root: root,
        typeCode: typeCode ?? '',
        slotName: _requiresMountStorage(root) ? '_restageArgument$index' : '',
        defaultBinding: defaultBinding,
      ),
    );
  }
  final values = parameters
      .where((parameter) => !parameter.isKey)
      .map((parameter) => parameter.root)
      .toList(growable: false);
  if (values.length != input.rootParams.length ||
      !values.indexed.every(
        (entry) => identical(entry.$2, input.rootParams[entry.$1]),
      )) {
    return (
      constructor: null,
      reason: 'its constructor description is unavailable',
    );
  }
  return (
    constructor: _ResolvedMountConstructorContract(parameters),
    reason: null,
  );
}

bool _redirectsToGenerativeConstructor(ConstructorElement constructor) {
  final seen = Set<ConstructorElement>.identity();
  var current = constructor;
  while (current.isFactory) {
    if (!seen.add(current.baseElement)) return false;
    final redirected = current.redirectedConstructor;
    if (redirected == null) return false;
    current = redirected;
  }
  return true;
}

RootContextParamKind _mountParameterKind(FormalParameterElement parameter) =>
    parameter.isOptionalPositional
        ? RootContextParamKind.optionalPositional
        : parameter.isNamed
            ? RootContextParamKind.named
            : RootContextParamKind.requiredPositional;

String _emitReferenceDart(
  ResolvedStandaloneScreenContract contract, {
  String? measurementPublicationDraftDigest,
}) {
  final screenName = contract.screen.name!;
  final screenStem = _pascalIdentifier(screenName, fallback: 'SurfaceScreen');
  final refStem = _lowerCamelIdentifier(screenName, fallback: 'surfaceScreen');
  final eventBase = '${screenStem}Event';
  final eventContractName = '_${refStem}Events';
  final provenanceName = '_${refStem}Provenance';
  final decoderName = '_decodeValidated$eventBase';
  final refName = generatedHandleName(screenName, fallback: 'surfaceScreen');
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
        final parameter = event.arguments is SurfaceScreenEventObjectArguments
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
  final referenceConstructor = measurementPublicationDraftDigest == null
      ? '${sdk}SurfaceScreenRef<$referenceEventType>.generated'
      : '${sdk}SurfaceScreenRef<$referenceEventType>'
          '.generatedWithMeasurementPublicationDraftDigest';

  // The event schema is emitted in its canonical encoded form rather than as a
  // Dart literal tree, so the value the runtime hashes is byte-identical to
  // the one this build hashed. The runtime derives the contract fingerprint
  // and event hash from it, which is why neither is emitted here: a divergence
  // between the two encoders must fail closed, and it cannot do that if the
  // generated code simply restates what the build computed.
  final bundleLocatorSource = _resolveBundleLocatorSource(contract, sdk);
  buffer
    ..writeln(
      'final $provenanceName = '
      '${sdk}SurfaceScreenRuntimeProvenance.generated(',
    )
    ..writeln('  surface: ${sdk}Surface.${contract.surface.name},')
    ..writeln('  slug: ${_dartString(contract.slug)},')
    ..writeln('  contractVersion: ${contract.contractVersion},')
    ..writeln(
      '  capabilities: ${_capabilitySource(contract.capabilities, sdk)},',
    )
    ..writeln(
      '  eventSchemaJson: ${_dartString(
        SurfaceScreenEventSchemaV1Codec.encodeCanonicalJson(
          contract.eventSchema,
        ),
      )},',
    );
  if (!contract.hostDataContract.isEmpty) {
    buffer.writeln(
      '  hostDataSchemaJson: ${_dartString(
        SurfaceScreenHostDataSchemaV1Codec.encodeCanonicalJson(
          contract.hostDataContract,
        ),
      )},',
    );
  }
  if (bundleLocatorSource != null) {
    buffer.writeln('  bundle: $bundleLocatorSource,');
  }
  buffer
    ..writeln(');')
    ..writeln()
    ..writeln(
      'final $refName = $referenceConstructor(',
    )
    ..writeln('  provenance: $provenanceName,')
    ..writeln('  eventContract: $eventContractName,');
  if (measurementPublicationDraftDigest != null) {
    buffer.writeln(
      '  measurementPublicationDraftDigest: '
      '${_dartString(measurementPublicationDraftDigest)},',
    );
  }
  buffer.writeln(');');

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
        final source = event.arguments is SurfaceScreenEventObjectArguments
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

  final mount = contract._mount;
  if (mount != null) {
    _emitScreenMount(
      buffer,
      contract: contract,
      mount: mount,
      eventType: referenceEventType,
    );
  }

  return '${formatGeneratedDart(buffer.toString()).trimRight()}\n';
}

void _emitScreenMount(
  StringBuffer buffer, {
  required ResolvedStandaloneScreenContract contract,
  required _ResolvedScreenMount mount,
  required String eventType,
}) {
  final screenName = contract.screen.name!;
  final mountName = generatedSurfaceName(
    screenName,
    fallback: 'SurfaceScreen',
  );
  final refName = generatedHandleName(
    screenName,
    fallback: 'surfaceScreen',
  );
  final constructor = mount.constructor;
  final parameters = constructor.parameters;
  final requiredPositional = parameters.where(
    (parameter) => parameter.kind == RootContextParamKind.requiredPositional,
  );
  final optionalPositional = parameters.where(
    (parameter) => parameter.kind == RootContextParamKind.optionalPositional,
  );
  final named = parameters.where(
    (parameter) => parameter.kind == RootContextParamKind.named,
  );
  final sdk = mount.sdk;
  final flutter = mount.flutter;

  for (final binding in constructor.defaultBindings) {
    buffer
      ..writeln()
      ..writeln(
        'const ${binding.typeCode} ${binding.name} = '
        '${binding.expressionCode};',
      );
  }
  buffer
    ..writeln()
    ..writeln(
      'final class $mountName extends ${flutter}StatelessWidget {',
    )
    ..writeln('  const $mountName(');
  for (final parameter in requiredPositional) {
    buffer.writeln('    ${parameter.declarationSource},');
  }
  if (optionalPositional.isNotEmpty) {
    buffer.writeln('    [');
    for (final parameter in optionalPositional) {
      buffer.writeln('    ${parameter.declarationSource},');
    }
    if (!constructor.hasKeyParameter) {
      buffer.writeln('    ${flutter}Key? key,');
    }
    buffer
      ..writeln('    this.onEvent,')
      ..writeln('    this.resolver,')
      ..writeln(
        '    this.onUnavailable,',
      )
      ..writeln('    this.loadingBuilder,')
      ..writeln('    ]');
  } else {
    buffer.writeln('    {');
    for (final parameter in named) {
      buffer.writeln('    ${parameter.declarationSource},');
    }
    if (!constructor.hasKeyParameter) {
      buffer.writeln('    super.key,');
    }
    buffer
      ..writeln('    this.onEvent,')
      ..writeln('    this.resolver,')
      ..writeln('    this.onUnavailable,')
      ..writeln('    this.loadingBuilder,')
      ..writeln('    }');
  }
  final initializers = <String>[
    for (final parameter in constructor.parameters.where(
      (parameter) => parameter.requiresStorage,
    ))
      '${parameter.slotName} = ${parameter.name}',
    if (constructor.explicitSuperKeySource case final source?)
      'super(key: $source)',
    if (optionalPositional.isNotEmpty && !constructor.hasKeyParameter)
      'super(key: key)',
  ];
  if (initializers.isEmpty) {
    buffer.writeln('  );');
  } else {
    buffer.write('  ) : ');
    for (var index = 0; index < initializers.length; index++) {
      if (index > 0) buffer.write('       ');
      buffer
        ..write(initializers[index])
        ..writeln(index == initializers.length - 1 ? ';' : ',');
    }
  }
  for (final parameter in constructor.parameters.where(
    (parameter) => parameter.requiresStorage,
  )) {
    buffer
      ..writeln()
      ..writeln('  final ${parameter.typeCode} ${parameter.slotName};');
  }
  buffer
    ..writeln()
    ..writeln('  final ${flutter}ValueChanged<$eventType>? onEvent;')
    ..writeln()
    ..writeln('  final ${sdk}SurfaceScreenResolver? resolver;')
    ..writeln()
    ..writeln(
      '  final ${flutter}ValueChanged<${sdk}SurfaceScreenUnavailableError>? '
      'onUnavailable;',
    )
    ..writeln()
    ..writeln('  final ${flutter}WidgetBuilder? loadingBuilder;')
    ..writeln()
    ..writeln('  @override')
    ..writeln(
      '  ${flutter}Widget build(${flutter}BuildContext context) {',
    );
  final fallbackArguments = <(_ResolvedMountParameter, String)>[
    for (final parameter in parameters)
      if (parameter.fallbackArgumentSource case final source?)
        (parameter, source),
  ];
  for (final parameter in parameters) {
    if (parameter.isKey &&
        parameter.requiresStorage &&
        parameter.name == 'key' &&
        fallbackArguments.any((entry) => entry.$2 == 'key')) {
      buffer.writeln('    final key = this.${parameter.slotName};');
    }
  }
  buffer
    ..writeln('    return ${sdk}RestageScreen<$eventType>(')
    ..writeln('      screen: $refName,');
  final hostParameters =
      constructor.values.where((parameter) => parameter.root.isHostData);
  if (hostParameters.isNotEmpty) {
    buffer.writeln('      context: <String, Object?>{');
    for (final parameter in hostParameters) {
      final source = 'this.${parameter.slotName}';
      buffer.writeln(
        '        ${_dartString(parameter.name)}: '
        '${_mountHostDataValue(parameter.root.hostDataShape!, source)},',
      );
    }
    buffer.writeln('      },');
  }
  buffer
    ..writeln(
      '      unavailable: ${sdk}SurfaceScreenUnavailablePolicy.fallback(',
    )
    ..writeln('        builder: (context, error) => $screenName(');
  for (final (parameter, source) in fallbackArguments) {
    buffer.writeln(
      parameter.kind == RootContextParamKind.named
          ? '          ${parameter.name}: $source,'
          : '          $source,',
    );
  }
  buffer
    ..writeln('        ),')
    ..writeln('      ),')
    ..writeln('      onEvent: onEvent,')
    ..writeln('      resolver: resolver,')
    ..writeln('      onUnavailable: onUnavailable,')
    ..writeln('      loadingBuilder: loadingBuilder,')
    ..writeln('    );')
    ..writeln('  }')
    ..writeln('}');
}

String _mountHostDataValue(
  HostDataShape shape,
  String source, [
  int depth = 0,
]) {
  if (!shape.requiresEncoding) return source;
  final nullable = shape.type.nullabilitySuffix == NullabilitySuffix.question;
  if (nullable) {
    final present = '_restagePresent$depth';
    return 'switch ($source) { final $present? => '
        '${_mountNonNullHostDataValue(shape, present, depth)}, '
        'null => null }';
  }
  return _mountNonNullHostDataValue(shape, source, depth);
}

String _mountNonNullHostDataValue(
  HostDataShape shape,
  String source,
  int depth,
) {
  final value = '_restageValue$depth';
  final entry = '_restageEntry$depth';
  return switch (shape) {
    HostDataObjectShape() => _mountObjectValue(shape, source, depth),
    HostDataListShape(:final elementShape) =>
      '<Object?>[for (final $value in $source) '
          '${_mountHostDataValue(elementShape, value, depth + 1)}]',
    HostDataMapShape(:final valueShape) =>
      '<String, Object?>{for (final $entry in $source.entries) '
          '$entry.key: '
          '${_mountHostDataValue(valueShape, '$entry.value', depth + 1)}}',
    HostDataScalarShape() => source,
  };
}

String _mountObjectValue(
  HostDataObjectShape shape,
  String source,
  int depth,
) {
  final fields = shape.fields.map((field) {
    final value = '$source.${field.wireKey}';
    return '${_dartString(field.wireKey)}: '
        '${_mountHostDataValue(field.shape, value, depth + 1)}';
  });
  return '<String, Object?>{${fields.join(', ')}}';
}

Iterable<_ResolvedScreenEvent> _eventsInSchemaOrder(
  ResolvedStandaloneScreenContract contract,
) sync* {
  for (final schemaEvent in contract.eventSchema.events) {
    yield contract._events.singleWhere((event) => event.id == schemaEvent.id);
  }
}

/// The `bundle: ...` argument source for [contract]'s generated reference, or
/// `null` when this package's resolved placement does not route `.rsbundle`
/// files into Flutter assets.
///
/// The asset key and logical entry paths are deterministic functions of data
/// [contract] already carries (its resolved [RestageOutputPlacementPlan] and
/// its own `surface`/`slug`), computed here rather than duplicated from the
/// roster's canonical-publication claim formula. The entry hashes and lengths
/// come only from [ResolvedStandaloneScreenContractInput.bundleEntryMetadata]
/// — never recomputed here — because those must be byte-identical to what the
/// outputs builder records for the same bytes, and the only way to guarantee
/// that is for both to trace back to one hash of one set of bytes.
///
/// A `bundled_runtime: true` package must never emit a reference with a
/// silently omitted locator: throws if the resolved placement calls for one
/// and [ResolvedStandaloneScreenContractInput.bundleEntryMetadata] is absent.
String? _resolveBundleLocatorSource(
  ResolvedStandaloneScreenContract contract,
  String sdk,
) {
  final plan = contract.input.plan ?? RestageOutputPlacementPlan.defaults;
  if (!plan.bundledRuntime) return null;
  final metadata = contract.input.bundleEntryMetadata;
  if (metadata == null) {
    throw StateError(
      'Screen ${contract.slug} (${contract.input.location}) has no bundle '
      'entry metadata, but this package resolves bundled_runtime: true. A '
      'bundled-runtime package must never emit a generated reference with a '
      'silently omitted bundle locator.',
    );
  }
  final assetId = contract.input.assetId;
  final assetKey = plan.forLibrary(assetId.path).bundlePath;
  final surfaceKey = contract.surface.wireName;
  final blobPath =
      metadata.blobPath ?? 'assets/$surfaceKey/screens/${contract.slug}.rfw';
  final sidecarPath = metadata.sidecarPath ??
      'assets/$surfaceKey/screens/${contract.slug}.capability.json';
  final buffer = StringBuffer()
    ..writeln('${sdk}SurfaceScreenBundleLocator(')
    ..writeln('  assetKey: ${_dartString(assetKey)},')
    ..writeln('  packageName: ${_dartString(assetId.package)},')
    ..writeln('  authoredLibraryPath: ${_dartString(assetId.path)},')
    ..writeln('  entries: [')
    ..writeln('    ${sdk}SurfaceScreenBundleEntryReference(')
    ..writeln('      logicalPath: ${_dartString(blobPath)},')
    ..writeln('      role: ${sdk}RestageBundleEntryRole.screenBlob,')
    ..writeln('      byteLength: ${metadata.blobByteLength},')
    ..writeln('      sha256: ${_dartString(metadata.blobSha256)},')
    ..writeln('    ),')
    ..writeln('    ${sdk}SurfaceScreenBundleEntryReference(')
    ..writeln('      logicalPath: ${_dartString(sidecarPath)},')
    ..writeln('      role: ${sdk}RestageBundleEntryRole.capabilitySidecar,')
    ..writeln('      byteLength: ${metadata.sidecarByteLength},')
    ..writeln('      sha256: ${_dartString(metadata.sidecarSha256)},')
    ..writeln('    ),')
    ..writeln('  ],')
    ..write(')');
  return buffer.toString();
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

List<String> _referenceGeneratedTopLevelSymbols(
  String screenName,
  Iterable<_ResolvedScreenEvent> events,
) {
  final screenStem = _pascalIdentifier(screenName, fallback: 'SurfaceScreen');
  final refStem = _lowerCamelIdentifier(screenName, fallback: 'surfaceScreen');
  final hasEvents = events.isNotEmpty;
  return <String>[
    if (hasEvents) '${screenStem}Event',
    '_${refStem}Events',
    '_${refStem}Provenance',
    if (hasEvents) '_decodeValidated${screenStem}Event',
    generatedHandleName(screenName, fallback: 'surfaceScreen'),
    if (hasEvents)
      for (final event in events) _eventClassName(screenStem, event.field.name),
  ];
}

List<String> _generatedTopLevelSymbols(
  String screenName,
  Iterable<_ResolvedScreenEvent> events,
  _ResolvedScreenMount? mount,
) =>
    [
      ..._referenceGeneratedTopLevelSymbols(screenName, events),
      if (mount != null) ...[
        generatedSurfaceName(screenName, fallback: 'SurfaceScreen'),
        for (final binding in mount.constructor.defaultBindings) binding.name,
      ],
    ];

String _mountDefaultBindingName(String screenName, int ordinal) =>
    '_${_lowerCamelIdentifier(screenName, fallback: 'surfaceScreen')}'
    'MountDefault$ordinal';

String _eventClassName(String screenStem, String? fieldName) =>
    '$screenStem${_pascalIdentifier(fieldName ?? '', fallback: 'Event')}Event';

Set<String> _owningLibrarySourceNames(
  ResolvedStandaloneScreenContractInput input,
  OwningLibraryNamespace namespace,
) {
  final library = input.screen.library;
  final generatedPart = _declaredGeneratedPart(input);
  bool fromGeneratedPart(Element element) =>
      generatedPart != null && _elementAssetId(element) == generatedPart;
  final names = <String>{
    ...namespace.prefixNames,
    ...namespace.unprefixedImportNames,
    ...namespace.publicNamespaceNames(exclude: fromGeneratedPart),
  };
  for (final item in _topLevelElements(library)) {
    if (fromGeneratedPart(item)) continue;
    final name = item.name;
    if (name != null && name.isNotEmpty) names.add(name);
    final lookup = item.lookupName;
    if (lookup != null && lookup.isNotEmpty) names.add(lookup);
  }
  return names;
}

Iterable<Element> _topLevelElements(LibraryElement library) sync* {
  for (final elements in <Iterable<Element>>[
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
    yield* elements;
  }
}

/// Returns the one generated screen part that this library actually declares.
///
/// The part path comes from the resolved placement plan, then is matched back
/// against the library's analyzer fragments. This keeps the warm-build escape
/// hatch exact: another `.g.dart` sibling, or a generated-looking file from a
/// different package/path, remains a real collision.
AssetId? _declaredGeneratedPart(
  ResolvedStandaloneScreenContractInput input,
) {
  if (!input.assetId.path.endsWith('.dart')) return null;
  final expected = AssetId(
    input.assetId.package,
    input.generatedPartPath,
  );
  for (final fragment in input.screen.library.fragments) {
    if (_assetIdForUri(fragment.source.uri) == expected) return expected;
  }
  return null;
}

AssetId? _elementAssetId(Element element) =>
    _assetIdForUri(element.firstFragment.libraryFragment?.source.uri);

AssetId? _assetIdForUri(Uri? uri) {
  if (uri == null) return null;
  try {
    return AssetId.resolve(uri);
  } on Object {
    // Analyzer-only file URIs do not carry a stable package-relative identity.
    return null;
  }
}

String? _sdkPrefixFor(LibraryElement library) {
  return _prefixForOrigin(
    library,
    _restageSdkOrigin,
    const {
      'Surface',
      'SurfaceScreenRef',
      'SurfaceScreenEventContract',
      'CapabilityManifest',
      'LibraryRequirement',
    },
  );
}

String? _prefixForOrigin(
  LibraryElement library,
  String origin,
  Set<String> symbols,
) {
  final candidates = <String>[];
  for (final import in library.firstFragment.libraryImports) {
    final imported = import.importedLibrary;
    if (imported == null ||
        !libraryUriMatchesOrigin(imported.identifier, origin)) {
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

// Both name derivations live in generated_handle_names.dart so the screen and
// flow frontends spell one rule. These aliases keep the call sites unchanged.
const String Function(String, {required String fallback}) _pascalIdentifier =
    pascalIdentifier;
const String Function(String, {required String fallback})
    _lowerCamelIdentifier = lowerCamelIdentifier;

final class _ResolvedScreenMount {
  const _ResolvedScreenMount({
    required this.sdk,
    required this.flutter,
    required this.constructor,
  });

  final String sdk;
  final String flutter;
  final _ResolvedMountConstructorContract constructor;
}

final class _ResolvedMountConstructorContract {
  _ResolvedMountConstructorContract(List<_ResolvedMountParameter> parameters)
      : parameters = List.unmodifiable(parameters);

  final List<_ResolvedMountParameter> parameters;

  Iterable<_ResolvedMountDefaultBinding> get defaultBindings =>
      parameters.map((parameter) => parameter.defaultBinding).nonNulls;

  Iterable<_ResolvedMountParameter> get values =>
      parameters.where((parameter) => !parameter.isKey);

  bool get hasKeyParameter => parameters.any(
        (parameter) => parameter.isKey || parameter.name == 'key',
      );

  bool get hasOptionalPositional => parameters.any(
        (parameter) =>
            parameter.kind == RootContextParamKind.optionalPositional,
      );

  bool get requiresKeyType => hasOptionalPositional && !hasKeyParameter;

  /// A non-nullable authored key belongs to the fallback widget alone, so the
  /// mount does not also take it.
  String? get explicitSuperKeySource => parameters
      .where(
        (parameter) =>
            parameter.isKey &&
            parameter.isNullableKey &&
            !parameter.usesStatelessWidgetSuperFormal,
      )
      .firstOrNull
      ?.name;
}

final class _ResolvedMountParameter {
  _ResolvedMountParameter.value({
    required this.root,
    required this.typeCode,
    required this.slotName,
    required this.defaultBinding,
  });

  final RootContextParam root;
  final String typeCode;
  final String slotName;
  final _ResolvedMountDefaultBinding? defaultBinding;

  String get name => root.name;
  RootContextParamKind get kind => root.kind;
  bool get isRequired => root.isRequired;
  bool get isKey => root.forwardsFlutterKey;
  bool get usesStatelessWidgetSuperFormal =>
      root.usesStatelessWidgetSuperFormal;
  bool get requiresStorage => slotName.isNotEmpty;

  String? get defaultValueCode => defaultBinding?.name;

  String get declarationSource {
    final required =
        isRequired && kind == RootContextParamKind.named ? 'required ' : '';
    final defaultValue = defaultValueCode;
    final defaultSource = defaultValue == null ? '' : ' = $defaultValue';
    if (isKey && usesStatelessWidgetSuperFormal) {
      final type = root.hasExplicitType ? '$typeCode ' : '';
      return '$required${type}super.$name$defaultSource';
    }
    return '$required$typeCode $name$defaultSource';
  }

  String get fallbackSource {
    if (isKey && (!requiresStorage || name == 'key')) return name;
    return 'this.$slotName';
  }

  /// Whether this key parameter can carry a Flutter key the mount forwards.
  bool get isNullableKey =>
      root.type.nullabilitySuffix == NullabilitySuffix.question;

  /// This parameter's fallback-widget argument, or null to omit it; a key the
  /// mount forwards to `super` never also reaches the fallback widget.
  String? get fallbackArgumentSource {
    if (!isKey || !isNullableKey) return fallbackSource;
    if (kind == RootContextParamKind.named && !isRequired) return null;
    return 'null';
  }
}

@immutable
final class _ResolvedMountDefaultBinding {
  const _ResolvedMountDefaultBinding({
    required this.name,
    required this.typeCode,
    required this.expressionCode,
  });

  final String name;
  final String typeCode;
  final String expressionCode;
}

bool _requiresMountStorage(RootContextParam parameter) {
  if (!parameter.forwardsFlutterKey) return true;
  // Only a key routed to the fallback widget alone needs a slot.
  if (parameter.type.nullabilitySuffix == NullabilitySuffix.question) {
    return false;
  }
  if (!parameter.usesStatelessWidgetSuperFormal) return true;
  if (parameter.name != 'key') return true;
  final type = parameter.type;
  return type is! InterfaceType ||
      type.element.name != 'Key' ||
      !libraryUriMatchesOrigin(
        type.element.library.identifier,
        _flutterOrigin,
      );
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
  final SurfaceScreenEventArguments arguments;
  final _DartEventShape? dartShape;

  SurfaceScreenEvent get schemaEvent => SurfaceScreenEvent(
        id: id,
        arguments: arguments,
      );
}

sealed class _DartEventShape {
  const _DartEventShape();

  String get dartType;
  SurfaceScreenEventShape get schemaShape;
  String decode(String source);
}

final class _ScalarDartEventShape extends _DartEventShape {
  const _ScalarDartEventShape({
    required this.dartType,
    required this.scalar,
  });

  @override
  final String dartType;
  final SurfaceScreenEventScalarKind scalar;

  @override
  SurfaceScreenEventShape get schemaShape =>
      SurfaceScreenEventScalarShapeV1(scalar);

  @override
  String decode(String source) =>
      scalar == SurfaceScreenEventScalarKind.jsonValue
          ? source
          : '$source as $dartType';
}

final class _NullableDartEventShape extends _DartEventShape {
  const _NullableDartEventShape(this.value);

  final _DartEventShape value;

  @override
  String get dartType => '${value.dartType}?';

  @override
  SurfaceScreenEventShape get schemaShape =>
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
  SurfaceScreenEventShape get schemaShape =>
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
  SurfaceScreenEventShape get schemaShape =>
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
