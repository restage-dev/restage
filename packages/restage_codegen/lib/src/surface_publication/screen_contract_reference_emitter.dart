// Analyzer-resolved standalone screen contracts and generated references.
import 'dart:convert';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/widget_builder_lowering.dart';
import 'package:restage_codegen/src/surface_publication/recorded_layouts.dart';
import 'package:restage_codegen/src/surface_publication/split_widgets.dart';
import 'package:restage_codegen/src/widget_library_registration.dart'
    show widgetLibraryVersionArguments;
import 'package:restage_codegen/src/annotation_lookup.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/emit_utils.dart';
import 'package:restage_codegen/src/helper_registry.dart'
    show libraryUriMatchesOrigin;
import 'package:restage_codegen/src/hoisting.dart';
import 'package:restage_codegen/src/installed_native_call.dart';
import 'package:restage_codegen/src/host_data_shape.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/factory_emitter.dart'
    show
        CustomReconstruction,
        customFactoryValue,
        customFactoryValueIsNullable,
        decoderCallFor;
import 'package:restage_codegen/src/islands/context_reach.dart'
    show isFlutterFrameworkType;
import 'package:restage_codegen/src/islands/island_registration.dart';
import 'package:restage_codegen/src/islands/islands.dart';
import 'package:restage_codegen/src/owning_library_namespace.dart';
import 'package:restage_codegen/src/surface_publication/generated_handle_names.dart';
import 'package:restage_codegen/src/surface_publication/host_data_contract.dart';
import 'package:restage_codegen/src/surface_publication/output_location.dart';
import 'package:restage_codegen/src/surface_vocabulary.dart';
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

/// Resolved authored-widget constructor shared by generated surface mounts.
@immutable
class ResolvedWidgetMountInput {
  /// Creates the resolved constructor input.
  const ResolvedWidgetMountInput({
    required this.assetId,
    required this.screen,
    required this.rootParams,
    required this.constructorParams,
    this.mountConstructorProblem,
    this.plan,
    this.partPath,
    this.hoisted = const [],
    this.firedEvents = const [],
    this.islands = const [],
    this.placedCustomWidgetSites = const [],
    this.split,
    this.buildArguments = const [],
  });

  /// Owning library asset used for diagnostics and part output location.
  final AssetId assetId;

  /// Analyzer identity of the authored widget.
  final ClassElement screen;

  /// Resolved render-data constructor parameters in declaration order.
  final List<RootContextParam> rootParams;

  /// Every unnamed-constructor formal in declaration order.
  final List<RootContextParam> constructorParams;

  /// Why the original constructor cannot be preserved, when unsupported.
  final String? mountConstructorProblem;

  /// Output location authority, or null for the default layout.
  final RestageOutputLocationPlan? plan;

  /// Roster-owned generated part path, when supplied by the aggregate owner.
  final String? partPath;

  /// Values the mount computes for the surface, ordered by key.
  final List<HoistedValue> hoisted;

  /// The `SurfaceEvent` constants the build fires; the contract includes the
  /// ones the screen doesn't declare.
  final List<PropertyInducingElement> firedEvents;

  /// Widget expressions the mount renders from the app.
  final List<Island> islands;

  /// Custom widget constructions the build places by catalog entry.
  final List<AstNode> placedCustomWidgetSites;

  /// How the mount takes over the surface's shell and `State`.
  final MountSplit? split;

  /// The parameters the screen's build takes after its context; the mount
  /// extends the screen's base class and receives the same ones.
  final List<FormalParameterElement> buildArguments;

  /// Everything the mount publishes under the render context.
  SurfaceScreenHostDataSchema get hostDataContract =>
      hostDataContractOf(rootParams, hoisted: hoisted);

  /// The owning library’s single generated Dart part.
  String get generatedPartPath =>
      partPath ??
      (plan ?? RestageOutputLocationPlan.defaults)
          .forLibrary(assetId.path)
          .neutralPartPath;

  /// Compact source location used by diagnostics.
  String get location => '${assetId.path}#${screen.name ?? '<unnamed>'}';
}

/// Analyzer-resolved inputs for one independently published `@Screen`.
@immutable
final class ResolvedStandaloneScreenContractInput
    extends ResolvedWidgetMountInput {
  /// Creates a contract-emission input for a categorized screen.
  const ResolvedStandaloneScreenContractInput({
    required super.assetId,
    required super.screen,
    required this.surface,
    required this.slug,
    required this.contractVersion,
    required this.capabilities,
    required super.rootParams,
    required super.constructorParams,
    super.mountConstructorProblem,
    super.plan,
    super.hoisted,
    super.firedEvents,
    super.islands,
    super.split,
    super.buildArguments,
    this.bundleEntryMetadata,
    this.vocabulary = SurfaceVocabularyReferences.empty,
  });

  /// Canonical product category.
  final Surface surface;

  /// Canonical publication slug.
  final String slug;

  /// Positive app-pinned contract version.
  final int contractVersion;

  /// Capabilities pinned into the generated reference.
  final CapabilityManifest capabilities;

  /// Exact compiled blob and sidecar metadata when bundling is enabled.
  final ResolvedScreenBundleEntryMetadata? bundleEntryMetadata;

  /// The catalog widgets and icon constants this screen renders, named so the
  /// generated reference installs exactly them.
  final SurfaceVocabularyReferences vocabulary;

  /// This input with [bundleEntryMetadata] replaced.
  ///
  /// Everything else is carried over rather than restated, so a late refresh
  /// of the bundle hashes cannot silently drop another resolved field.
  ResolvedStandaloneScreenContractInput withBundleEntryMetadata(
    ResolvedScreenBundleEntryMetadata bundleEntryMetadata,
  ) => ResolvedStandaloneScreenContractInput(
    assetId: assetId,
    screen: screen,
    surface: surface,
    slug: slug,
    contractVersion: contractVersion,
    capabilities: capabilities,
    rootParams: rootParams,
    constructorParams: constructorParams,
    mountConstructorProblem: mountConstructorProblem,
    plan: plan,
    hoisted: hoisted,
    firedEvents: firedEvents,
    islands: islands,
    split: split,
    buildArguments: buildArguments,
    bundleEntryMetadata: bundleEntryMetadata,
    vocabulary: vocabulary,
  );
}

/// Refuses each value [input] hoists when its mount is omitted for [reason].
///
/// [missing] says what was not generated; a screen's mount by default.
///
/// [fix] is a sentence each message ends with; [value] words the message for
/// one value's source text instead.
List<Issue> hoistedWithoutMountIssues(
  ResolvedWidgetMountInput input,
  String reason, {
  String? mount,
  String? fix,
  String Function(String source)? value,
}) => [
  // A build the mount can't record is refused as itself.
  if (input.split?.recordProblem case final problem?)
    problem
  else
    for (final (code, message) in withoutMountMessages(
      hoisted: input.hoisted,
      islands: input.islands,
      split: input.split,
      mount: mount ?? _mountNameOf(input),
      location: input.location,
      reason: reason,
      fix: fix,
      value: value,
    ))
      _issue(input, code, message),
];

/// What a surface without its mount loses: each value it computes, each
/// widget it renders from the app, each wrapper the mount would keep and the
/// State it would hold. [reason] and [fix] say why [mount] wasn't generated.
List<(IssueCode, String)> withoutMountMessages({
  required List<HoistedValue> hoisted,
  required List<Island> islands,
  required MountSplit? split,
  required String mount,
  required String location,
  required String reason,
  String? fix,
  String Function(String source)? value,
}) {
  final because =
      'which needs the generated `$mount`, and Restage didn\'t '
      'generate it because $reason.${fix == null ? '' : ' $fix'}';
  return [
    for (final hoistedValue in hoisted)
      if (hoistedValue.kind != HoistValueKind.itemIndex)
        (
          IssueCode.unrecognizedMethodCall,
          value?.call(readableSource(hoistedValue.label)) ??
              '`${readableSource(hoistedValue.label)}` '
                  '(${hoistedValue.location ?? location}) runs app code, '
                  '$because',
        ),
    for (final (widget, at) in [
      for (final island in islands)
        (readableSource(island.node.toSource()), island.location),
      for (final node in split?.shell ?? const []) (node.widget, node.location),
    ])
      (
        IssueCode.unknownWidget,
        '`$widget` ($at) runs app code, $because',
      ),
    if (split?.state case final state?)
      (
        IssueCode.stateShapeUnsupported,
        "`${state.name}` (${state.location}) holds the screen's state in app "
            'code, $because',
      ),
  ];
}

String _mountNameOf(ResolvedWidgetMountInput input) => generatedSurfaceName(
  input.screen.name ?? '',
  fallback: 'SurfaceScreen',
);

/// Emits a typed paywall mount using the same constructor contract as screens.
///
/// [appWidgetLibraries] returns the app widget registrations the mount
/// installs, given the SDK prefix the part spells.
({
  String? source,
  String? omissionMessage,
  String? omissionReason,
  String? omissionFix,
})
emitPaywallMount(
  ResolvedWidgetMountInput input, {
  required String id,
  FlowDocument? navigationFlow,
  SurfaceVocabularyReferences vocabulary = SurfaceVocabularyReferences.empty,
  String? Function(String sdkPrefix)? appWidgetLibraries,
}) {
  final result = _resolveScreenMount(
    input,
    reservedGeneratedSymbols: const {},
    paywall: true,
  );
  final mount = result.mount;
  if (mount == null) {
    return (
      source: null,
      omissionMessage: result.message,
      omissionReason: result.reason,
      omissionFix: result.fix,
    );
  }
  final librarySource = _withIslandLibrary(
    appWidgetLibraries?.call(mount.sdk),
    mount,
  );
  final buffer = StringBuffer()
    ..writeln(
      emitPlacementDefinition(
        declarationName: input.screen.name!,
        defaultSurfaceArgument: 'id: ${dartStringLiteral(id)}',
        surface: Surface.paywall,
        slug: id,
        hostContract: SurfaceHostContractV1(
          hosting: SurfaceHostingV1(
            contentKind: navigationFlow == null
                ? SurfaceContentKindV1.single
                : SurfaceContentKindV1.flow,
            presentation: SurfacePresentationV1.inline,
          ),
          providedContext: input.hostDataContract,
          handledEvents: SurfaceScreenEventSchema(events: const []),
          islands: islandHostFacet(mount.islands),
          layouts: recordedLayoutsOf(input.split?.recordedBuild),
          flowBoundary: navigationFlow == null
              ? null
              : FlowHostBoundaryV1.fromDocument(
                  navigationFlow,
                  signals: navigationFlow.outbound.customEvents.keys.toSet(),
                ),
        ),
        vocabulary: vocabulary.namesInstallable || librarySource != null
            ? 'const ${emitSurfaceVocabulary(
                vocabulary,
                sdkPrefix: mount.sdk,
                libraries: librarySource,
              )}'
            : null,
        sdkHost: '${mount.sdk}RestagePaywall',
      ),
    );
  _emitScreenMount(
    buffer,
    screenName: input.screen.name!,
    mount: mount,
    eventType: '${mount.sdk}RestageEvent',
    paywallId: id,
    vocabulary: vocabulary,
    appWidgetLibraries: librarySource,
  );
  return (
    source: buffer.toString(),
    omissionMessage: null,
    omissionReason: null,
    omissionFix: null,
  );
}

/// The sentence that tells a step to keep its [input] in a field.
String stepFieldFix(String input, String step) =>
    'Try storing `$input` in a final field of `$step`.';

/// The message for a step value [source] that needs an [input] the step
/// keeps in no field.
String stepUnstoredValue(
  String source,
  String input,
  String step,
  String flow,
) =>
    "`'$source'` needs the app's code to compute. Restage couldn't generate "
    'that code for step `$step` in `$flow`. The step\'s input `$input` '
    "isn't stored in a field. ${stepFieldFix(input, step)}";

/// The function a flow step's mount is generated as.
String stepMountName(String id) => 'restageStepMount\$${_stepIdentifier(id)}';

// [id] as part of a Dart identifier.
String _stepIdentifier(String id) =>
    id.replaceAll(RegExp('[^a-zA-Z0-9_]'), '_');

/// What a step's build messages say was not generated.
String stepMountMissing(String step, String flow) =>
    "The code for step `$step` in `$flow` wasn't generated";

/// The object that keeps a step's islands across versions of its content.
String stepMountOwnerName(String id) =>
    '_restageStepOwner\$${_stepIdentifier(id)}';

/// Emits the mount of the flow step [id] when it renders with the app's code;
/// [unstored] names a constructor input the step keeps in no field.
({
  String? source,
  String? omissionMessage,
  String? omissionReason,
  String? omissionFix,
  String? unstored,
})
emitStepMount(
  ResolvedWidgetMountInput input, {
  required String id,
  required String flow,
  bool ownSurface = false,
}) {
  if (input.hoisted.isEmpty && input.islands.isEmpty) {
    return (
      source: null,
      omissionMessage: null,
      omissionReason: null,
      omissionFix: null,
      unstored: null,
    );
  }
  final missing = stepMountMissing(input.screen.name!, flow);
  final result = _resolveScreenMount(
    input,
    reservedGeneratedSymbols: const {},
    missing: missing,
  );
  final mount = result.mount;
  final unstored = mount == null
      ? null
      : [
          for (final parameter in mount.constructor.values)
            if (parameter.root.field == null &&
                input.screen.lookUpGetter(
                      name: parameter.name,
                      library: input.screen.library,
                    ) ==
                    null)
              parameter.name,
        ].firstOrNull;
  final problem = mount == null
      ? null
      : unstored == null
      ? null
      : "its input $unstored isn't stored in a field";
  if (mount == null || problem != null) {
    return (
      source: null,
      omissionMessage:
          result.message ??
          '$missing because $problem.'
              '${unstored == null ? '' : ' ${stepFieldFix(unstored, input.screen.name!)}'}',
      omissionReason: result.reason ?? problem,
      omissionFix: result.reason != null
          ? result.fix
          : unstored == null
          ? null
          : stepFieldFix(unstored, input.screen.name!),
      unstored: unstored,
    );
  }
  final buffer = StringBuffer();
  _emitScreenMount(
    buffer,
    screenName: input.screen.name!,
    mount: mount,
    eventType: '${mount.sdk}RestageEvent',
    stepId: id,
    flow: flow,
    declaresIslands: !ownSurface,
  );
  return (
    source: buffer.toString(),
    omissionMessage: null,
    omissionReason: null,
    omissionFix: null,
    unstored: null,
  );
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
  }) : _sdkPrefix = sdkPrefix,
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

  /// The generated mount widget's name, or null when the mount is omitted.
  String? get mountName => _mount == null
      ? null
      : generatedSurfaceName(screen.name!, fallback: 'SurfaceScreen');

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

  /// Emits typed events and `SurfaceScreenRef<E>` for the screen.
  /// The aggregate manifest supplies artifact paths. [appWidgetLibraries] maps
  /// the SDK prefix to registrations installed by the reference.
  String emitReferenceDart({
    String? measurementPublicationDraftDigest,
    String? Function(String sdkPrefix)? appWidgetLibraries,
  }) => _emitReferenceDart(
    this,
    measurementPublicationDraftDigest: measurementPublicationDraftDigest,
    appWidgetLibraries: appWidgetLibraries?.call(_sdkPrefix),
  );

  /// The `package:restage` names [emitReferenceDart] writes that the
  /// screen library's SDK import doesn't show, sorted.
  List<String> hiddenSdkNames({
    String? measurementPublicationDraftDigest,
    String? Function(String sdkPrefix)? appWidgetLibraries,
  }) {
    const marker = '\u0007';
    final written = _emitReferenceDart(
      this,
      measurementPublicationDraftDigest: measurementPublicationDraftDigest,
      appWidgetLibraries: appWidgetLibraries?.call(marker),
      sdkOverride: marker,
    );
    return {
      for (final match in RegExp('$marker(\\w+)').allMatches(written))
        if (_prefixForOrigin(screen.library, _restageSdkOrigin, {match[1]!}) !=
            _sdkPrefix)
          match[1]!,
    }.toList()..sort();
  }
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

  final events = _inspectScreenEvents(input, issues);
  final mountResolution = screen.name == null || screen.name!.isEmpty
      ? (mount: null, message: null, reason: null, fix: null)
      : _resolveScreenMount(
          input,
          reservedGeneratedSymbols: _referenceGeneratedTopLevelSymbols(
            screen.name!,
            events,
          ).toSet(),
        );
  if (mountResolution.reason case final reason? when issues.isEmpty) {
    issues.addAll(
      hoistedWithoutMountIssues(input, reason, fix: mountResolution.fix),
    );
  }
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
    hostDataContract = input.hostDataContract;
    contractFingerprint = SurfaceScreenContractFingerprint.hash(
      sourceKind: SurfaceSourceKind.screen,
      payloadKind: SurfacePayloadKind.blob,
      capabilities: input.capabilities,
      eventContractHash: eventContractHash,
      hostDataContractHash: SurfaceScreenHostDataContractHash.hash(
        hostDataContract,
      ),
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
    final message =>
      '$message The screen declares host-supplied inputs; a '
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

/// Inspects typed events for a screen, including neutral flow screens.
///
/// The same resolved type algebra builds standalone event contracts.
({SurfaceScreenEventSchema? schema, List<Issue> issues})
inspectScreenEventContract(ResolvedWidgetMountInput input) {
  final issues = <Issue>[];
  final events = _inspectScreenEvents(input, issues);
  return (
    schema: issues.isEmpty
        ? SurfaceScreenEventSchema(
            events: [for (final event in events) event.schemaEvent],
          )
        : null,
    issues: List.unmodifiable(issues),
  );
}

List<_ResolvedScreenEvent> _inspectScreenEvents(
  ResolvedWidgetMountInput input,
  List<Issue> issues,
) {
  final screen = input.screen;
  final events = <_ResolvedScreenEvent>[];
  final fields =
      screen.children.whereType<FieldElement>().where((field) {
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

  // An event the build fires but the screen doesn't declare joins the
  // contract. One that matches a declared event's ID and payload is that
  // event, under its declared name.
  final fired =
      input.firedEvents.where((field) => !fields.contains(field)).toList()
        ..sort(
          (left, right) =>
              _describedName(left).compareTo(_describedName(right)),
        );
  for (final field in fired) {
    final id = field.computeConstantValue()?.getField('id')?.toStringValue();
    final type = field.type;
    if (id == null ||
        id.isEmpty ||
        type is! InterfaceType ||
        type.typeArguments.length != 1) {
      continue;
    }
    final event = _eventFromType(
      field: field,
      id: id,
      payloadType: type.typeArguments.single,
      input: input,
      issues: issues,
    );
    if (event == null) continue;
    final payload = jsonEncode(event.schemaEvent.toJson());
    if (events.any(
      (known) =>
          known.id == id && jsonEncode(known.schemaEvent.toJson()) == payload,
    )) {
      continue;
    }
    events.add(event);
  }

  _reportDuplicateEventIds(input, events, issues);
  _reportEventNameCollisions(input, events, issues);
  // The issues name each clash; drop the rest so they don't repeat it as a
  // symbol collision.
  final ids = <String>{};
  final names = <String?>{};
  events.retainWhere(
    (event) => ids.add(event.id) & names.add(event.field.name),
  );
  return events;
}

// `Class.field`, or a top-level constant's name, as Dart source spells it.
String _qualifiedName(PropertyInducingElement field) {
  final name = field.name ?? '<unnamed>';
  return switch (field.enclosingElement) {
    InstanceElement(name: final owner) => '${owner ?? '<unnamed>'}.$name',
    _ => name,
  };
}

// How a diagnostic names an event constant: a top-level one with its library.
String _describedName(PropertyInducingElement field, {bool code = true}) {
  final name = code ? '`${_qualifiedName(field)}`' : _qualifiedName(field);
  return field.enclosingElement is InstanceElement
      ? name
      : '$name from ${field.library.uri}';
}

// [name] with its first letter in [upper] or lower case.
String _withInitial(String name, {required bool upper}) => name.isEmpty
    ? name
    : (upper ? name[0].toUpperCase() : name[0].toLowerCase()) +
          name.substring(1);

// Fired events from other classes can share a name; their generated event
// classes would collide.
void _reportEventNameCollisions(
  ResolvedWidgetMountInput input,
  List<_ResolvedScreenEvent> events,
  List<Issue> issues,
) {
  final byName = <String, List<_ResolvedScreenEvent>>{};
  for (final event in events) {
    (byName[event.field.name ?? ''] ??= []).add(event);
  }
  final screen = input.screen.name ?? '<unnamed>';
  for (final entry
      in byName.entries.toList()
        ..sort((left, right) => left.key.compareTo(right.key))) {
    final ids = {for (final event in entry.value) event.id};
    if (ids.length < 2) continue;
    final names = [
      for (final event in entry.value) _describedName(event.field),
    ];
    final foreign = entry.value
        .map((event) => event.field)
        .firstWhere(
          (field) => field.enclosingElement != input.screen,
          orElse: () => entry.value.last.field,
        );
    final String advice;
    if (foreign.enclosingElement case InstanceElement(:final name?)) {
      final suggested =
          _withInitial(name, upper: false) +
          _withInitial(entry.key, upper: true);
      advice =
          'Try declaring '
          '`static const $suggested = ${_qualifiedName(foreign)};` on $screen.';
    } else {
      // A top-level constant is named through a prefixed import, so the
      // alias can't read the screen's own field of the same name.
      final library = foreign.library.uri;
      final prefix = _libraryPrefix(library);
      final suggested = prefix + _withInitial(entry.key, upper: true);
      advice =
          "Try importing '$library' as $prefix and declaring "
          '`static const $suggested = $prefix.${entry.key};` on $screen.';
    }
    issues.add(
      _issue(
        input,
        IssueCode.duplicateId,
        '$screen fires events with different IDs under one name, '
        '${names.join(' and ')}. $advice',
      ),
    );
  }
}

// A lowerCamelCase import prefix for [library], from its file name.
String _libraryPrefix(Uri library) {
  final stem = library.pathSegments.last.replaceFirst(RegExp(r'\.dart$'), '');
  final words = stem.split(RegExp('[^A-Za-z0-9]+')).where((w) => w.isNotEmpty);
  final prefix = [
    for (final (index, word) in words.indexed)
      _withInitial(word, upper: index > 0),
  ].join();
  return prefix.isEmpty || RegExp('^[0-9]').hasMatch(prefix)
      ? 'events'
      : prefix;
}

_ResolvedScreenEvent? _eventFromType({
  required PropertyInducingElement field,
  required String id,
  required DartType payloadType,
  required ResolvedWidgetMountInput input,
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
  required ResolvedWidgetMountInput input,
  required PropertyInducingElement field,
  required List<Issue> issues,
}) {
  void reject(String reason) {
    issues.add(
      _issue(
        input,
        IssueCode.buildMethodTooComplex,
        'SurfaceEvent ${_qualifiedName(field)} has '
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
  required ResolvedWidgetMountInput input,
  required PropertyInducingElement field,
  required List<Issue> issues,
}) {
  void reject(String reason) {
    issues.add(
      _issue(
        input,
        IssueCode.buildMethodTooComplex,
        'SurfaceEvent ${_qualifiedName(field)} has '
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
  ResolvedWidgetMountInput input,
  List<_ResolvedScreenEvent> events,
  List<Issue> issues,
) {
  final byId = <String, List<_ResolvedScreenEvent>>{};
  for (final event in events) {
    (byId[event.id] ??= <_ResolvedScreenEvent>[]).add(event);
  }
  final duplicateIds =
      byId.entries.where((entry) => entry.value.length > 1).toList()
        ..sort((left, right) => left.key.compareTo(right.key));
  for (final entry in duplicateIds) {
    final fields = entry.value
        .map((event) => _describedName(event.field, code: false))
        .join(', ');
    issues.add(
      _issue(
        input,
        IssueCode.duplicateId,
        'Duplicate standalone SurfaceEvent ID "${entry.key}" declared by '
        '$fields. Try giving each event its own ID, or the same payload '
        'type.',
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
        'Standalone declarations would generate colliding symbol $symbol. '
        'Try renaming the declaration that generates it.',
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
  String? reason,
  String? fix,
})
_resolveScreenMount(
  ResolvedWidgetMountInput input, {
  required Set<String> reservedGeneratedSymbols,
  bool paywall = false,
  String? missing,
}) {
  final screen = input.screen;
  final screenName = screen.name!;
  final mountName = generatedSurfaceName(
    screenName,
    fallback: 'SurfaceScreen',
  );
  String? omittedReason;
  String? omittedFix;
  String omitted(String reason, {String? fix}) {
    omittedReason = reason;
    omittedFix = fix;
    return '${missing ?? "`$mountName` wasn't generated"} because $reason.'
        '${fix == null ? '' : ' $fix'}';
  }

  if (input.split?.recordProblem case final problem?) {
    return (
      mount: null,
      message: problem.message,
      reason: problem.message,
      fix: null,
    );
  }
  final namespace = OwningLibraryNamespace(screen.library);
  final sourceNames = _owningLibrarySourceNames(input, namespace);
  for (final value in input.hoisted) {
    final plan = value.nativeCall ?? value.nativeConstant;
    if (plan != null &&
        plan.emissionLibraryIdentity != screen.library.identifier) {
      return (
        mount: null,
        message: omitted(
          'a native expression was planned for a different emission library',
          fix: 'Please report this as a Restage bug.',
        ),
        reason: omittedReason,
        fix: omittedFix,
      );
    }
  }

  final constructorResult = _resolveMountConstructorContract(
    input,
    paywall: paywall,
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
      message: omitted(constructorResult.reason!, fix: constructorResult.fix),
      reason: omittedReason,
      fix: omittedFix,
    );
  }

  final mountSymbols = {
    mountName,
    ...placementDefinitionSymbols(screenName),
  };
  final collision = mountSymbols
      .where(
        (name) =>
            sourceNames.contains(name) ||
            reservedGeneratedSymbols.contains(name),
      )
      .firstOrNull;
  if (collision != null) {
    return (
      mount: null,
      message: omitted(
        '`$collision` already exists in ${input.assetId.path}',
        fix: 'Try renaming `$collision` in ${input.assetId.path}.',
      ),
      reason: omittedReason,
      fix: omittedFix,
    );
  }

  final entrySymbols = paywall
      ? const {
          'RestagePaywall',
          'VariantResolver',
          'RestageEvent',
          'RestagePaywallError',
        }
      : const {
          'RestageScreen',
          'SurfaceScreenResolver',
          'SurfaceScreenUnavailableError',
        };
  // Every name the mount writes through the SDK import is spelled through one
  // import that shows them all; a part can't add an import of its own.
  final islandsDeclared = input.islands.isNotEmpty;
  final sdkMountSymbols = {
    'RestageRecording',
    if (islandsDeclared ||
        paywall && input.split?.recorded != null ||
        (input.split?.recordedBuild?.placesAppWidgets ?? false))
      'RestageIslandScope',
    if (islandsDeclared) ...{
      'RestageWidgetLibraryRegistration',
      'RestageWidgetFactory',
    },
  };
  final entrySdk = namespace.prefixForOrigin(_restageSdkOrigin, entrySymbols);
  final sdk = entrySdk == null
      ? null
      : namespace.prefixForOrigin(_restageSdkOrigin, {
          ...entrySymbols,
          ...sdkMountSymbols,
        });
  final hidden = entrySdk == null || sdk != null
      ? null
      : sdkMountSymbols.firstWhere(
          (name) =>
              namespace.prefixForOrigin(_restageSdkOrigin, {
                ...entrySymbols,
                name,
              }) ==
              null,
          orElse: () => sdkMountSymbols.first,
        );
  if (hidden != null) {
    return (
      mount: null,
      message: omitted(
        '${input.assetId.path} imports `package:restage/restage.dart` with a '
        '`show` or `hide` list that leaves out `$hidden`, which the '
        'generated code uses',
        fix:
            'Try importing `package:restage/restage.dart` without `show` or '
            '`hide`, or adding `$hidden` to its `show` list.',
      ),
      reason: omittedReason,
      fix: omittedFix,
    );
  }
  final needsNativeValues = input.hoisted.any(
    (v) =>
        v.kind == HoistValueKind.textScaler ||
        v.kind == HoistValueKind.nativeBinding,
  );
  final nativeScopePrefix = needsNativeValues
      ? namespace.prefixForOrigin('package:restage_core', {
          'RestageNativeValues',
          if (input.hoisted.any((v) => v.kind == HoistValueKind.nativeBinding))
            'NativeBinding',
          if (input.hoisted.any((v) => v.nativeCall != null))
            'NativeCallAdapter',
        })
      : null;
  final needsNativeBindings = input.hoisted.any(
    (v) => v.kind == HoistValueKind.nativeBinding,
  );
  final nativeContractPrefix = needsNativeBindings
      ? namespace.prefixForOrigin('package:restage_shared', {
          'NativeBindingContract',
          if (input.hoisted.any((v) => v.nativeCall != null)) 'ValueNative',
        })
      : null;
  if (needsNativeValues && nativeScopePrefix == null ||
      needsNativeBindings && nativeContractPrefix == null) {
    return (
      mount: null,
      message: omitted(
        "${input.assetId.path} doesn't import "
        '`package:restage_core/restage_core.dart`',
        fix: 'Try importing it without `show` or `hide`.',
      ),
      reason: omittedReason,
      fix: omittedFix,
    );
  }
  if (sdk == null) {
    return (
      mount: null,
      message: omitted(
        '${input.assetId.path} doesn\'t import '
        '`package:restage/restage.dart` under one prefix',
        fix:
            'Try importing `package:restage/restage.dart` once, without '
            '`show` or `hide`.',
      ),
      reason: omittedReason,
      fix: omittedFix,
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
      if (input.split?.state != null) ...{'State', 'StatefulWidget'},
    },
  );
  if (input.islands.isNotEmpty &&
      _kIslandSdkSymbols.entries.any(
        (entry) => namespace.prefixForOrigin(entry.value, {entry.key}) != sdk,
      )) {
    return (
      mount: null,
      message: omitted(
        '${input.assetId.path} doesn\'t import '
        '`package:restage/restage.dart` under one prefix',
        fix:
            'Try importing `package:restage/restage.dart` once, without '
            '`show` or `hide`.',
      ),
      reason: omittedReason,
      fix: omittedFix,
    );
  }
  if (flutter == null) {
    return (
      mount: null,
      message: omitted(
        "${input.assetId.path} doesn't import Flutter's widgets under one "
        'prefix',
        fix:
            'Try importing `package:flutter/widgets.dart` without `show` or '
            '`hide`.',
      ),
      reason: omittedReason,
      fix: omittedFix,
    );
  }

  // A mount that builds the way its surface does, from the surface's build
  // or from its State moved in, takes the surface's base kind and mixins.
  String? base;
  final buildParameters = <String>[];
  // It needs that kind when the kind builds its own element, when build
  // takes more than a context, or when the lifted State's base needs it.
  final supertype = screen.supertype;
  final ownElement =
      [
        if (supertype != null) supertype,
        ...?supertype?.allSupertypes,
        ...screen.mixins,
      ].any(
        (type) =>
            !_isFrameworkWidgetBase(type.element) &&
            !type.element.library.isInSdk &&
            type.element.library.identifier !=
                'package:flutter/src/widgets/framework.dart' &&
            type.element.getMethod('createElement') != null,
      );
  final mirrors =
      input.buildArguments.isNotEmpty ||
      (input.split?.state != null ||
              !isFlutterFrameworkType(screen, 'StatefulWidget')) &&
          (ownElement || (input.split?.state?.customBase ?? false));
  if (mirrors &&
      supertype != null &&
      !(_isFrameworkWidgetBase(supertype.element) && screen.mixins.isEmpty)) {
    final bases = [supertype, ...screen.mixins];
    final spelled = [for (final type in bases) namespace.typeCode(type)];
    if (spelled.indexOf(null) case final unnamed when unnamed >= 0) {
      final name = bases[unnamed].element.name;
      return (
        mount: null,
        message: omitted(
          "${input.assetId.path} can't name its base class `$name`",
          fix: 'Try importing the library that declares `$name`.',
        ),
        reason: omittedReason,
        fix: omittedFix,
      );
    }
    if (_baseProblem(supertype) case final problem?) {
      final kind = isFlutterFrameworkType(screen, 'StatefulWidget')
          ? 'StatefulWidget'
          : 'StatelessWidget';
      return (
        mount: null,
        message: omitted(problem, fix: 'Try extending `$kind` directly.'),
        reason: omittedReason,
        fix: omittedFix,
      );
    }
    base =
        '${spelled.first}'
        '${spelled.length > 1 ? ' with ${spelled.skip(1).join(', ')}' : ''}';
  }
  if (input.buildArguments.isNotEmpty) {
    for (final argument in input.buildArguments) {
      final type = namespace.typeCode(argument.type);
      if (type == null) {
        return (
          mount: null,
          message: omitted(
            "${input.assetId.path} can't name the type of the build argument "
            '`${argument.name}`',
            fix: 'Try importing the library that declares it.',
          ),
          reason: omittedReason,
          fix: omittedFix,
        );
      }
      buildParameters.add('$type ${argument.name}');
    }
  }

  final prefixCollision = _mountControlNames(
    paywall: paywall,
  ).where(namespace.prefixNames.contains).firstOrNull;
  if (prefixCollision != null) {
    return (
      mount: null,
      message: omitted(
        'the import prefix `$prefixCollision` clashes with a name the '
        'generated `$mountName` uses',
        fix: 'Try renaming the prefix.',
      ),
      reason: omittedReason,
      fix: omittedFix,
    );
  }

  return (
    mount: _ResolvedScreenMount(
      sdk: sdk,
      flutter: flutter,
      reservedNativeNames: {
        ...sourceNames,
        ...reservedGeneratedSymbols,
        'context',
        for (final argument in input.buildArguments) argument.name ?? '',
        for (final owner in [
          screen,
          ...screen.allSupertypes.map((type) => type.element),
        ]) ...[
          for (final field in owner.fields) field.name ?? '',
          for (final method in owner.methods) method.name ?? '',
          for (final getter in owner.getters) getter.name ?? '',
        ],
      },
      constructor: mountConstructor,
      hoisted: input.hoisted,
      islands: input.islands,
      split: input.split,
      nativeContractType: nativeContractPrefix == null
          ? null
          : '${nativeContractPrefix}NativeBindingContract',
      nativeScopeType: nativeScopePrefix == null
          ? null
          : '${nativeScopePrefix}RestageNativeValues',
      base: base,
      buildParameters: buildParameters,
    ),
    message: null,
    reason: null,
    fix: null,
  );
}

({
  _ResolvedMountConstructorContract? constructor,
  String? reason,
  String? fix,
})
_resolveMountConstructorContract(
  ResolvedWidgetMountInput input, {
  required Set<String> reservedNames,
  bool paywall = false,
}) {
  final screen = input.screen;
  if (screen.typeParameters.isNotEmpty) {
    for (final parameter in input.constructorParams) {
      final typeCode = parameter.typeCode ?? '';
      for (final typeParameter in screen.typeParameters) {
        final name = typeParameter.name;
        if (name != null &&
            RegExp(
              '(^|[^A-Za-z0-9_])${RegExp.escape(name)}'
              r'([^A-Za-z0-9_]|$)',
            ).hasMatch(typeCode)) {
          return (
            constructor: null,
            reason: '`${screen.name}` declares the type parameter `$name`',
            fix: 'Try removing the type parameter from `${screen.name}`.',
          );
        }
      }
    }
    final name = screen.typeParameters.first.name ?? '<unnamed>';
    return (
      constructor: null,
      reason: '`${screen.name}` declares the type parameter `$name`',
      fix: 'Try removing the type parameter from `${screen.name}`.',
    );
  }

  final constructor = screen.unnamedConstructor;
  if (constructor == null) {
    return (
      constructor: null,
      reason: '`${screen.name}` has no unnamed constructor',
      fix: 'Try adding an unnamed constructor to `${screen.name}`.',
    );
  }
  if (constructor.isFactory &&
      !_redirectsToGenerativeConstructor(constructor)) {
    return (
      constructor: null,
      reason: "`${screen.name}`'s unnamed constructor is a factory",
      fix: 'Try making it a generative constructor.',
    );
  }
  if (screen.isAbstract && !constructor.isFactory) {
    return (
      constructor: null,
      reason: '`${screen.name}` is abstract',
      fix: 'Try making `${screen.name}` a concrete class.',
    );
  }
  if (input.mountConstructorProblem != null) {
    return (
      constructor: null,
      reason: '`${screen.name}` changes its key before passing it on',
      fix: 'Try passing `key` straight to `super.key`.',
    );
  }

  final controls = _mountControlNames(paywall: paywall);
  final captureNames = <String>{
    ...controls,
    'build',
    for (final parameter in constructor.formalParameters)
      if (parameter.name case final name? when name.isNotEmpty) name,
    for (
      var index = 0;
      index < constructor.formalParameters.length;
      index++
    ) ...['_restageArgument$index', '_restageStored$index'],
  };
  final parameters = <_ResolvedMountParameter>[];
  // The build read [constructorParams] from this constructor, one per formal.
  for (var index = 0; index < input.constructorParams.length; index++) {
    final root = input.constructorParams[index];
    final name = root.name;
    if (controls.contains(name) || isHoistedKey(name)) {
      return (
        constructor: null,
        reason:
            "`${screen.name}`'s constructor parameter `$name` uses a "
            'name the generated code needs',
        fix: 'Try renaming `$name`.',
      );
    }
    if (root.mountDefaultProblem != null) {
      return (
        constructor: null,
        reason:
            "${input.assetId.path} can't name the default value of "
            '`$name`',
        fix: 'Try importing the library that declares it.',
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
        reason: "`${screen.name}`'s required key isn't nullable",
        fix: 'Try declaring it as `Key?`.',
      );
    }
    final implicitSuperKey =
        root.forwardsFlutterKey &&
        root.usesStatelessWidgetSuperFormal &&
        !root.hasExplicitType;
    if ((typeCode == null || typeCode.trim().isEmpty) && !implicitSuperKey) {
      return (
        constructor: null,
        reason: "${input.assetId.path} can't name the type of `$name`",
        fix:
            'Try giving `$name` an explicit type that '
            '${input.assetId.path} imports.',
      );
    }
    _ResolvedMountDefaultBinding? defaultBinding;
    if (root.mountDefaultValueCode case final expressionCode?) {
      if (typeCode == null || typeCode.trim().isEmpty) {
        return (
          constructor: null,
          reason: "${input.assetId.path} can't name the type of `$name`",
          fix:
              'Try giving `$name` an explicit type that '
              '${input.assetId.path} imports.',
        );
      }
      final bindingName = _mountDefaultBindingName(screen.name!, index);
      if (reservedNames.contains(bindingName) ||
          captureNames.contains(bindingName)) {
        return (
          constructor: null,
          reason:
              'the generated default binding $bindingName is already '
              'visible in ${input.assetId.path}',
          fix: 'Please report this as a Restage bug.',
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
        // A field the app's reads promote is read as one; others through a
        // getter, so a null check promotes exactly where it does in the app.
        slotName: !_requiresMountStorage(root)
            ? ''
            : (root.field?.isPromotable ?? false)
            ? '_restageStored$index'
            : '_restageArgument$index',
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
      fix: 'Please report this as a Restage bug.',
    );
  }
  return (
    constructor: _ResolvedMountConstructorContract(parameters),
    reason: null,
    fix: null,
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

String _emitReferenceDart(
  ResolvedStandaloneScreenContract contract, {
  String? measurementPublicationDraftDigest,
  String? appWidgetLibraries,
  // Spells every SDK name with this prefix, unformatted.
  String? sdkOverride,
}) {
  final screenName = contract.screen.name!;
  final screenStem = _pascalIdentifier(screenName, fallback: 'SurfaceScreen');
  final refStem = _lowerCamelIdentifier(screenName, fallback: 'surfaceScreen');
  final eventStem = _eventStem(screenName);
  final eventBase = '${eventStem}Event';
  final eventContractName = '_${refStem}Events';
  final provenanceName = '_${refStem}Provenance';
  final decoderName = '_decodeValidated$eventBase';
  final refName = generatedHandleName(screenName, fallback: 'surfaceScreen');
  final sdk = sdkOverride ?? contract._sdkPrefix;
  final mount = switch (contract._mount) {
    final mount? when sdkOverride != null => mount.withSdk(sdkOverride),
    final mount => mount,
  };
  final sourceFile = _fileName(contract.input.assetId.path);
  final buffer = StringBuffer()
    ..writeln('part of ${dartStringLiteral(sourceFile)};')
    ..writeln();

  if (contract._events.isNotEmpty) {
    buffer
      ..writeln('sealed class $eventBase {')
      ..writeln('  const $eventBase();')
      ..writeln('}')
      ..writeln();
    for (final event in _eventsInSchemaOrder(contract)) {
      final eventClass = _eventClassName(eventStem, event.field.name);
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
      ..writeln('  hash: ${dartStringLiteral(contract.eventContractHash)},')
      ..writeln('  decodeValidated: $decoderName,')
      ..writeln(');')
      ..writeln();
  } else {
    buffer
      ..writeln('final $eventContractName =')
      ..writeln('    const ${sdk}SurfaceScreenEventContract<Never>.none(')
      ..writeln('  hash: ${dartStringLiteral(contract.eventContractHash)},')
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
    ..writeln('  slug: ${dartStringLiteral(contract.slug)},')
    ..writeln('  contractVersion: ${contract.contractVersion},')
    ..writeln(
      '  capabilities: ${_capabilitySource(contract.capabilities, sdk)},',
    )
    ..writeln(
      '  eventSchemaJson: ${dartStringLiteral(
        SurfaceScreenEventSchemaV1Codec.encodeCanonicalJson(
          contract.eventSchema,
        ),
      )},',
    );
  if (!contract.hostDataContract.isEmpty) {
    buffer.writeln(
      '  hostDataSchemaJson: ${dartStringLiteral(
        SurfaceScreenHostDataSchemaV1Codec.encodeCanonicalJson(
          contract.hostDataContract,
        ),
      )},',
    );
  }
  if (bundleLocatorSource != null) {
    buffer.writeln('  bundle: $bundleLocatorSource,');
  }
  // The provenance value is not const, so the vocabulary carries its own
  // keyword; it is emitted only when it names something installable, so the
  // source is always a constructor invocation.
  final libraries = switch (mount) {
    final mount? => _withIslandLibrary(appWidgetLibraries, mount),
    null => appWidgetLibraries,
  };
  if (contract.input.vocabulary.namesInstallable || libraries != null) {
    buffer.writeln(
      '  vocabulary: const ${emitSurfaceVocabulary(
        contract.input.vocabulary,
        sdkPrefix: sdk,
        libraries: libraries,
      )},',
    );
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
      '${dartStringLiteral(measurementPublicationDraftDigest)},',
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
      final eventClass = _eventClassName(eventStem, event.field.name);
      buffer.writeln('    case ${dartStringLiteral(event.id)}:');
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
        '  throw FormatException(${dartStringLiteral(
          'Invalid $screenStem event "\u0000".',
        ).replaceFirst(r'\u0000', r'$name')});',
      )
      ..writeln('}');
  }

  if (mount != null) {
    buffer
      ..writeln()
      ..writeln(
        emitPlacementDefinition(
          declarationName: screenName,
          defaultSurfaceArgument: 'defaultSurface: $refName',
          surface: contract.surface,
          slug: contract.slug,
          screenContractVersion: contract.contractVersion,
          hostContract: SurfaceHostContractV1(
            hosting: const SurfaceHostingV1(
              contentKind: SurfaceContentKindV1.single,
              presentation: SurfacePresentationV1.inline,
            ),
            providedContext: contract.hostDataContract,
            handledEvents: contract.eventSchema,
            islands: islandHostFacet(mount.islands),
            layouts: recordedLayoutsOf(mount.split?.recordedBuild),
          ),
          vocabulary: '$refName.provenance.vocabulary',
          sdkHost: '${mount.sdk}RestageScreen',
        ),
      );
    _emitScreenMount(
      buffer,
      screenName: contract.screen.name!,
      mount: mount,
      eventType: referenceEventType,
    );
  }

  if (sdkOverride != null) return buffer.toString();
  return '${formatGeneratedDart(buffer.toString()).trimRight()}\n';
}

Set<String> _mountControlNames({required bool paywall}) => {
  'onEvent',
  'resolver',
  if (!paywall) 'onUnavailable',
  'loadingBuilder',
  'fallbackBuilder',
  'errorBuilder',
};

void _emitScreenMount(
  StringBuffer out, {
  required String screenName,
  required _ResolvedScreenMount mount,
  required String eventType,
  String? paywallId,
  String? stepId,
  String? flow,
  SurfaceVocabularyReferences vocabulary = SurfaceVocabularyReferences.empty,
  String? appWidgetLibraries,
  bool declaresIslands = true,
}) {
  var buffer = out;
  final mountStart = out.length;
  // A mount runs the build once, recording what the design reads. With
  // nothing to record, the design's fallback is the surface itself.
  final bare = mount.split?.recorded == null;
  final state = mount.split?.state;
  final stateful = state != null;
  // A step mount reads its step's inputs from the widget the app built.
  final step = stepId != null;
  // Every read of the mount's own fields; a lifted State reads them through
  // `widget`.
  String read(String member) => stateful ? 'widget.$member' : member;
  final slots = {
    for (final parameter in mount.constructor.values)
      // A step's input is read from the field the step keeps it in.
      parameter.name: step
          ? '${stateful ? '_restageWidget' : kSurfaceInstance}.'
                '${parameter.root.field?.name ?? parameter.name}'
          : read(parameter.slotName),
  };
  final paywall = paywallId != null;
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
  final errorType = paywall
      ? '${sdk}RestagePaywallError'
      : '${sdk}SurfaceScreenUnavailableError';
  final flutter = mount.flutter;
  final names = {
    ...mount.reservedNativeNames,
    for (final parameter in parameters) ...[
      parameter.name,
      parameter.slotName,
    ],
    for (final binding in constructor.defaultBindings) binding.name,
    ..._mountControlNames(paywall: paywall),
  };
  String allocate(String stem) {
    var name = stem;
    var suffix = 2;
    while (!names.add(name)) {
      name = '$stem${suffix++}';
    }
    return name;
  }

  final islands = mount.islands.isEmpty ? null : mount.islands;
  // A recorded paywall build dispatches its own events through its mount.
  final explicitEvents = paywall && !bare;
  // A split widget the build places keys its wrapper under the mount.
  final placesAppWidgets =
      mount.split?.recordedBuild?.placesAppWidgets ?? false;
  final scoped = islands != null || explicitEvents || placesAppWidgets;
  final content = allocate('restageContent');
  final lead = scoped ? 'final $content = ' : 'return ';
  final owner = step ? allocate(stepMountOwnerName(stepId)) : null;
  // A step with its own surface shares that surface's island declarations.
  if (islands != null && declaresIslands) {
    _writeIslandDeclarations(
      buffer,
      mount,
      step ? flow! : mountName,
      step: step,
    );
  }
  final nativeHoisted = [
    for (final value in mount.hoisted)
      if (value.kind == HoistValueKind.textScaler) value,
  ];
  final nativeBindings = [
    for (final value in mount.hoisted)
      if (value.kind == HoistValueKind.nativeBinding) value,
  ];
  final hasNativeScope = nativeHoisted.isNotEmpty || nativeBindings.isNotEmpty;
  final placementArgument = allocate('restagePlacementId');
  final placementSlot = allocate('_restagePlacementName');
  final namedPlacement =
      optionalPositional.isEmpty &&
      !parameters.any((parameter) => parameter.name == 'placement');
  final provider = placementDefinitionProviderName(screenName);

  // Call contracts are decoded once, not on every build.
  final nativeContracts = <String, String>{};
  for (final value in nativeBindings) {
    final contract = value.nativeContract;
    if (contract?.call == null || nativeContracts.containsKey(value.key)) {
      continue;
    }
    final name = allocate('_restage${mountName}${value.key}Contract');
    nativeContracts[value.key] = name;
    final sharedPrefix = mount.nativeContractType!.replaceFirst(
      RegExp(r'NativeBindingContract$'),
      '',
    );
    buffer.writeln(
      'final $name = ${nativeContractSource(contract!, sharedPrefix)};',
    );
  }
  String contractSource(HoistedValue value, String sharedPrefix) =>
      nativeContracts[value.key] ??
      nativeContractSource(value.nativeContract!, sharedPrefix);

  final nativeFactories = <String, String>{};
  for (final value in nativeBindings) {
    final call = value.nativeCall;
    final constant = value.nativeConstant;
    if (call == null && constant == null) continue;
    final name = allocate('_restage${mountName}${value.key}Native');
    final nativePrefix = mount.nativeScopeType!.replaceFirst(
      RegExp(r'RestageNativeValues$'),
      '',
    );
    final sharedPrefix = mount.nativeContractType!.replaceFirst(
      RegExp(r'NativeBindingContract$'),
      '',
    );
    if (call != null) {
      // An adapter holds no state, so every build installs the same one.
      nativeFactories[value.key] = name;
      buffer.writeln(
        'final ${nativePrefix}NativeCallAdapter $name = '
        '${call.adapterSource(core: nativePrefix, shared: sharedPrefix, declaration: nativeContracts[value.key])};',
      );
      continue;
    }
    nativeFactories[value.key] = '$name()';
    buffer.writeln(
      '${constant!.resultDartType} $name() => ${constant.source};',
    );
  }

  int? stateBodyAt;
  // A step's mount reads the step the app built and the delivered content;
  // a stateful step's mount is a widget that holds the step's State.
  final stepChild = stateful ? 'widget.child' : '_restageChild';
  final stepOriginal = stateful ? 'widget.original' : '_restageOriginal';
  if (step && stateful) {
    final widgetClass = '_restageStepWidget\$${_stepIdentifier(stepId)}';
    slots[kStateWidget] = '_restageWidget';
    slots['restageDidUpdateWidget'] = allocate('_restageDidUpdateWidget');
    if (islands != null) {
      buffer
        ..writeln()
        ..writeln('final $owner = Object();');
    }
    buffer
      ..writeln()
      ..writeln(
        '/// Renders the $stepId step with what the app computes for it.',
      )
      ..writeln(
        '${flutter}Widget ${stepMountName(stepId)}('
        '${flutter}BuildContext context, ${flutter}Widget _restageChild, '
        '${flutter}Widget _restageOriginal) =>',
      )
      ..writeln(
        '    $widgetClass(original: _restageOriginal as $screenName, '
        'child: _restageChild);',
      )
      ..writeln()
      ..writeln('final class $widgetClass extends ${flutter}StatefulWidget {')
      ..writeln(
        '  const $widgetClass({required this.original, '
        'required this.child});',
      )
      ..writeln()
      ..writeln('  final $screenName original;')
      ..writeln()
      ..writeln('  final ${flutter}Widget child;')
      ..writeln()
      ..writeln('  @override')
      ..writeln(
        '  _${widgetClass}State createState() => '
        '_${widgetClass}State();',
      )
      ..writeln('}')
      ..writeln()
      ..writeln(
        'final class _${widgetClass}State '
        '${state.header(widgetClass)} {',
      )
      ..writeln('  // ignore: unused_element')
      ..writeln('  $screenName get _restageWidget => widget.original;');
    for (final member in state.members(widgetClass, (name) => slots[name]!)) {
      // The copied build may call its own copy of a helper member instead.
      buffer
        ..writeln()
        ..writeln('  // ignore: unused_element')
        ..writeln('  $member');
    }
    if (state.updates) {
      buffer
        ..writeln()
        ..writeln('  @override')
        // The State's own didUpdateWidget calls super.
        ..writeln('  // ignore: must_call_super')
        ..writeln('  void didUpdateWidget(covariant $widgetClass oldWidget) =>')
        ..writeln(
          '      ${slots['restageDidUpdateWidget']}'
          '(oldWidget.original, oldWidget);',
        );
    }
    buffer
      ..writeln()
      ..writeln('  @override')
      ..writeln('  ${flutter}Widget build(${flutter}BuildContext context) {');
  } else if (step) {
    if (islands != null) {
      buffer
        ..writeln()
        ..writeln('final $owner = Object();');
    }
    buffer
      ..writeln()
      ..writeln(
        '/// Renders the $stepId step with what the app computes for it.',
      )
      ..writeln(
        '${flutter}Widget ${stepMountName(stepId)}('
        '${flutter}BuildContext context, ${flutter}Widget _restageChild, '
        '${flutter}Widget _restageOriginal) {',
      );
  } else {
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
        'final class $mountName extends '
        '${mount.base ?? (stateful ? '${flutter}StatefulWidget' : '${flutter}StatelessWidget')} {',
      );
    for (final atPlacement in [false, true]) {
      buffer
        ..writeln(
          atPlacement
              ? '  /// Overrides the implicit placement with an explicit name.'
              : '  /// Mounts this surface at its implicit placement by default.',
        )
        ..writeln('  ///')
        ..writeln(
          atPlacement
              ? '  /// Use [$mountName] for the default placement; no name is needed.'
              : '  /// Use this constructor for ordinary mounts; no placement name is needed.',
        );
      buffer.writeln(
        '  const $mountName${atPlacement ? '.atPlacement' : ''}(',
      );
      if (atPlacement) {
        buffer.writeln('    String $placementArgument,');
      }
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
      } else {
        buffer.writeln('    {');
        for (final parameter in named) {
          buffer.writeln('    ${parameter.declarationSource},');
        }
        if (!constructor.hasKeyParameter) {
          buffer.writeln('    super.key,');
        }
        if (!atPlacement && namedPlacement) {
          buffer.writeln('    String? placement,');
        }
      }
      buffer
        ..writeln('    this.onEvent,')
        ..writeln('    this.resolver,');
      if (!paywall) buffer.writeln('    this.onUnavailable,');
      buffer
        ..writeln('    this.loadingBuilder,')
        ..writeln('    this.fallbackBuilder,')
        ..writeln('    this.errorBuilder,');
      buffer.writeln(optionalPositional.isNotEmpty ? '    ]' : '    }');
      final placementValue = atPlacement
          ? placementArgument
          : namedPlacement
          ? 'placement'
          : 'null';
      final initializers = <String>[
        for (final parameter in constructor.parameters.where(
          (parameter) => parameter.requiresStorage,
        ))
          '${parameter.storageName} = ${parameter.name}',
        '$placementSlot = $placementValue',
        if (constructor.explicitSuperKeySource case final source?)
          'super(key: $source)',
        if (optionalPositional.isNotEmpty && !constructor.hasKeyParameter)
          'super(key: key)',
      ];
      buffer.write('  ) : ');
      for (var index = 0; index < initializers.length; index++) {
        if (index > 0) buffer.write('       ');
        buffer
          ..write(initializers[index])
          ..writeln(index == initializers.length - 1 ? ';' : ',');
      }
      buffer.writeln();
    }
    for (final parameter in constructor.parameters.where(
      (parameter) => parameter.requiresStorage,
    )) {
      // A getter keeps an unpromotable field unpromoted, as in the app.
      buffer
        ..writeln()
        ..writeln('  final ${parameter.typeCode} ${parameter.storageName};');
      if (parameter.slotName != parameter.storageName) {
        buffer.writeln(
          '  ${parameter.typeCode} get ${parameter.slotName} => '
          '${parameter.storageName};',
        );
      }
    }
    buffer
      ..writeln('  final String? $placementSlot;')
      ..writeln()
      ..writeln('  final ${flutter}ValueChanged<$eventType>? onEvent;')
      ..writeln()
      ..writeln(
        '  final $sdk${paywall ? 'VariantResolver' : 'SurfaceScreenResolver'}'
        '? resolver;',
      )
      ..writeln();
    if (!paywall) {
      buffer
        ..writeln(
          '  final ${flutter}ValueChanged<$errorType>? onUnavailable;',
        )
        ..writeln();
    }
    buffer
      ..writeln('  final ${flutter}WidgetBuilder? loadingBuilder;')
      ..writeln()
      ..writeln(
        '  final ${flutter}WidgetBuilder? fallbackBuilder;',
      )
      ..writeln()
      ..writeln(
        '  final ${flutter}Widget Function(${flutter}BuildContext, '
        '$errorType)? errorBuilder;',
      );
    if (stateful) {
      buffer
        ..writeln()
        ..writeln('  @override')
        ..writeln('  _${mountName}State createState() => _${mountName}State();')
        ..writeln('}')
        ..writeln()
        ..writeln(
          'final class _${mountName}State '
          '${state.header(mountName)} {',
        );
      slots[kStateWidget] = allocate('_restageWidget');
      slots['restageDidUpdateWidget'] = allocate('_restageDidUpdateWidget');
      stateBodyAt = buffer.length;
      for (final member in state.members(mountName, (name) => slots[name]!)) {
        // The copied build may call its own copy of a helper member instead.
        buffer
          ..writeln()
          ..writeln('  // ignore: unused_element')
          ..writeln('  $member');
      }
    }
    buffer
      ..writeln()
      ..writeln('  @override')
      ..writeln(
        '  ${flutter}Widget build(${[
          '${flutter}BuildContext context',
          ...mount.buildParameters,
        ].join(', ')}) {',
      );
  }
  slots[kRootContext] = 'context';
  final recordStart = out.length;
  // A screen mount installs through the vocabulary its reference carries. A
  // paywall mount names no reference, so it installs here instead.
  if (paywall && (vocabulary.namesInstallable || appWidgetLibraries != null)) {
    buffer.writeln(
      '    const ${emitSurfaceVocabulary(
        vocabulary,
        sdkPrefix: sdk,
        libraries: appWidgetLibraries,
      )}'
      '.addToInstalled();',
    );
  }
  final fallbackArguments = <(_ResolvedMountParameter, String)>[
    for (final parameter in parameters)
      if (parameter.fallbackArgumentSource(read) case final source?)
        (parameter, source),
  ];
  // A stateless surface's own members are read from one instance of it per
  // mount widget, as Flutter keeps the widget across rebuilds, declared at
  // the top of the build once the body reads it.
  final surfaces = allocate('_restageSurfaces');
  final surfaceInstance = step
      ? stateful
            ? null
            : '    final $kSurfaceInstance = _restageOriginal as $screenName;\n'
      : stateful
      ? null
      : '    final $kSurfaceInstance = $surfaces[this] ??= $screenName(${[
          for (final (parameter, source) in fallbackArguments)
            if (!parameter.isKey) parameter.kind == RootContextParamKind.named ? '${parameter.name}: $source' : source,
        ].join(', ')});\n';
  if (surfaceInstance != null) slots[kSurfaceInstance] = kSurfaceInstance;
  // A stored `key` is a local of the whole build, which the fallback widget
  // and the design both read.
  final keyLocal = [
    for (final parameter in parameters)
      if (parameter.isKey &&
          parameter.requiresStorage &&
          parameter.name == 'key' &&
          fallbackArguments.any((entry) => entry.$2 == 'key'))
        '    final key = ${read(parameter.slotName)};\n',
  ].join();
  if (hasNativeScope) {
    buffer.writeln('    $lead${mount.nativeScopeType}(');
    if (nativeHoisted.isNotEmpty) {
      buffer.writeln('      textScalers: _restageRecording.scalers,');
    }
    if (nativeBindings.isNotEmpty) {
      final nativePrefix = mount.nativeScopeType!.replaceFirst(
        RegExp(r'RestageNativeValues$'),
        '',
      );
      final sharedPrefix = mount.nativeContractType!.replaceFirst(
        RegExp(r'NativeBindingContract$'),
        '',
      );
      // What a builder records when it runs later joins the bindings live.
      final contracts = [
        for (final value in nativeBindings)
          if (value.computed)
            '${dartStringLiteral(value.key)} => '
                '${contractSource(value, sharedPrefix)}',
        '_ => throw StateError(key)',
      ].join(', ');
      buffer.writeln(
        '      bindings: _restageRecording.bindings('
        "(key) => switch (key.split('#').first) {$contracts}, {",
      );
      // A borrowed binding is passed as the mount holds it.
      for (final value in nativeBindings) {
        if (value.computed) continue;
        final installed = nativeFactories[value.key];
        buffer.writeln(
          '${dartStringLiteral(value.key)}: '
          '${nativePrefix}NativeBinding('
          'contract: ${contractSource(value, sharedPrefix)}, '
          'value: ${installed ?? _borrowedSource(value.mountSource((name) => slots[name]!))}),',
        );
      }
      buffer.writeln('      }),');
    }
    // Names each native value in debug builds' missing-value messages.
    buffer.writeln(
      "      labels: const bool.fromEnvironment('dart.vm.product') "
      '? const <String, String>{} : const <String, String>{',
    );
    for (final value in [...nativeHoisted, ...nativeBindings]) {
      buffer.writeln(
        '        ${dartStringLiteral(value.key)}: '
        '${dartStringLiteral(value.label)},',
      );
    }
    buffer.writeln('      },');
    buffer.write('      child: ');
  } else {
    buffer.write('    $lead');
  }
  if (step) {
    buffer.writeln('${sdk}RestageStepValues(built: _restageBuilt,');
  } else {
    buffer
      ..writeln(
        paywall ? '${sdk}RestagePaywall(' : '${sdk}RestageScreen<$eventType>(',
      )
      ..writeln(
        paywall
            ? '      id: ${dartStringLiteral(paywallId)},'
            : '      screen: $refName,',
      )
      ..writeln(
        '      placementBinding: '
        '$sdk${paywall ? 'RestagePaywall' : 'RestageScreen'}'
        '.generatedPlacementBinding(',
      )
      ..writeln('        definition: $provider,')
      ..writeln('        name: ${read(placementSlot)},')
      ..writeln('        eventOwner: ${slots[kRootContext]},')
      ..writeln('      ),');
  }
  final hostParameters = constructor.values.where(
    (parameter) => parameter.root.isHostData,
  );
  final hoisted = mount.hoisted;
  if (step && hostParameters.isEmpty && hoisted.isEmpty) {
    buffer.writeln('      values: const <String, Object?>{},');
  }
  if (hostParameters.isNotEmpty || hoisted.isNotEmpty) {
    buffer.writeln('      ${step ? 'values' : 'context'}: <String, Object?>{');
    buffer.writeln('        ..._restageRecording.values,');
    for (final parameter in hostParameters) {
      final source = slots[parameter.name]!;
      final itemValues = [
        for (final value in hoisted)
          if (value.item == parameter.name &&
              !const {
                HoistValueKind.nativeBinding,
                HoistValueKind.itemIndex,
                HoistValueKind.items,
              }.contains(value.kind))
            value,
      ];
      final itemNatives = [
        for (final value in nativeBindings)
          if (value.item == parameter.name) value,
      ];
      final itemIndexes = [
        for (final value in hoisted)
          if (value.item == parameter.name &&
              value.kind == HoistValueKind.itemIndex)
            value,
      ];
      final nestedItems = [
        for (final value in hoisted)
          if (value.item == parameter.name &&
              value.kind == HoistValueKind.items)
            value,
      ];
      buffer.writeln(
        '        ${dartStringLiteral(parameter.name)}: '
        '${_mountHostDataValue(
          parameter.root.hostDataShape!,
          source,
          0,
          itemValues.isEmpty && itemNatives.isEmpty && itemIndexes.isEmpty && nestedItems.isEmpty ? null : _ItemEntries(
                  (item, index) => '..._restageRecording.itemAt('
                      '${dartStringLiteral(parameter.name)}, $index)',
                  indexed: true,
                ),
        )},',
      );
    }
    for (final entry in _nativeContextEntries(nativeHoisted, nativeBindings)) {
      buffer.writeln('        $entry,');
    }
    buffer.writeln('      },');
  }
  if (step) {
    buffer
      ..writeln('      child: $stepChild,')
      ..writeln(!hasNativeScope ? '    );' : '      ),\n    );');
  } else {
    // The widget the build returned is the fallback unless the app passed one.
    buffer.writeln(
      '      fallbackBuilder: ${read('fallbackBuilder')} ?? '
      '((_) => _restageBuilt),\n'
      '      errorBuilder: ${read('errorBuilder')},',
    );
    if (!paywall) {
      buffer.writeln('      onUnavailable: ${read('onUnavailable')},');
    }
    buffer
      ..writeln('      onEvent: ${read('onEvent')},')
      ..writeln('      resolver: ${read('resolver')},')
      ..writeln('      loadingBuilder: ${read('loadingBuilder')},')
      ..writeln(!hasNativeScope ? '    );' : '      ),\n    );');
  }
  if (scoped) {
    // Each island is the one the build recorded at its place.
    buffer
      ..writeln(
        '    return ${sdk}RestageIslandScope('
        'owner: ${owner == null ? slots[kRootContext] : '${sdk}RestageIslandScope.hostOf(${slots[kRootContext]}) ?? $owner'}, '
        '${explicitEvents ? 'explicitEvents: true, ' : ''}builders: {',
      )
      ..writeAll([
        for (final island in islands ?? const <Island>[])
          '      ${dartStringLiteral(island.name)}: (_restageContext, _restageSource) => '
              '_restageRecording.islandAt(${dartStringLiteral(island.name)}, [${[
                for (final (level, _) in island.items.indexed) '_restageSource.v<int>(const <Object>'
                      "['$kPlacementItemsArgument', $level])!",
              ].join(', ')}], _restageContext, _restageSource),\n',
      ])
      ..writeln('    }, child: $content);');
  }
  {
    // The design is built where the copied build returns it, once the build
    // has recorded what it reads.
    final design = out.toString().substring(recordStart);
    final recorded =
        (bare
                ? '() => _restageDesign(${step ? stepOriginal : '$screenName(${[
                          for (final (parameter, source) in fallbackArguments) parameter.kind == RootContextParamKind.named ? '${parameter.name}: $source' : source,
                        ].join(', ')})'})'
                : mount.split!.recordedSource((name) => slots[name]!)!)
            .replaceAllMapped(
              RegExp('\u0002([A-Za-z0-9_\$]+)\\|([A-Za-z0-9_\$]+)\u0002'),
              (match) {
                final island = mount.islands.firstWhere(
                  (island) => island.name == match[1],
                );
                final argument = match[2]!;
                final path = "const <Object>[${dartStringLiteral(argument)}]";
                for (final value in island.slots) {
                  if (value.name == argument) {
                    if (value.builder case final builder?) {
                      return builder.callback(
                        AppValueSlot.bindingName(argument),
                        sdk: mount.sdk,
                      );
                    }
                    return '_restageSource.${value.list ? 'childList' : 'child'}($path)';
                  }
                }
                return decoderCallFor(
                  islandWidgetEntry(
                    island,
                  ).properties.firstWhere((entry) => entry.name == argument),
                  source: '_restageSource',
                  context: '_restageContext',
                  sdk: mount.sdk,
                );
              },
            )
            .replaceAll(kSdkPrefixMarker, mount.sdk);
    final head = out.toString().substring(0, recordStart);
    out
      ..clear()
      ..write(head)
      ..writeln('    // ignore: unused_local_variable')
      ..writeln(
        // The mount's context resolves the events its build records.
        '    final _restageRecording = ${sdk}RestageRecording('
        '${step ? '${scoped ? 'owner: ${sdk}RestageIslandScope.hostOf('
                            '${slots[kRootContext]}) ?? $owner, ' : ''}'
                  'mount: ${slots[kRootContext]}' : 'owner: ${slots[kRootContext]}'});',
      )
      ..write(keyLocal);
    if (surfaceInstance != null &&
        RegExp('\\b$kSurfaceInstance\\b').hasMatch('$design$recorded')) {
      out.write(surfaceInstance);
      if (!step) {
        // The one instance per mount widget.
        final mount = out.toString();
        final at = mount.lastIndexOf('  final String? $placementSlot;\n');
        if (at < 0) throw StateError('The mount declares no placement field.');
        out
          ..clear()
          ..write(mount.substring(0, at))
          ..writeln('  static final $surfaces = Expando<$screenName>();')
          ..write(mount.substring(at));
      }
    }
    out
      ..writeln(
        '    ${flutter}Widget _restageDesign(${flutter}Widget _restageBuilt) {',
      )
      ..write(design)
      ..writeln('    }')
      ..writeln('    return ($recorded)();');
  }
  // A lifted State reads `widget` as an instance of the surface, rebuilt
  // whenever the mount updates.
  final widgetName = slots[kStateWidget];
  if (!step &&
      state != null &&
      stateBodyAt != null &&
      widgetName != null &&
      (state.updates || RegExp('\\b$widgetName\\b').hasMatch(out.toString()))) {
    final surface =
        '$screenName(${[
          for (final (parameter, source) in fallbackArguments)
            if (!parameter.isKey) parameter.kind == RootContextParamKind.named ? '${parameter.name}: $source' : source,
        ].join(', ')})';
    final text = out.toString();
    out
      ..clear()
      ..write(text.substring(0, stateBodyAt))
      ..writeln()
      ..writeln('  late $screenName $widgetName = $surface;')
      ..writeln()
      ..writeln('  @override')
      // The State's own didUpdateWidget calls super.
      ..writeln(state.updates ? '  // ignore: must_call_super' : '')
      ..writeln('  void didUpdateWidget(covariant $mountName oldWidget) {')
      ..writeln(
        state.updates
            ? '    final _restagePrevious = $widgetName;\n'
                  '    $widgetName = $surface;\n'
                  '    ${slots['restageDidUpdateWidget']}(_restagePrevious, oldWidget);'
            : '    super.didUpdateWidget(oldWidget);\n'
                  '    $widgetName = $surface;',
      )
      ..writeln('  }')
      ..write(text.substring(stateBodyAt));
  }
  out.writeln(step && !stateful ? '}' : '  }\n}');
  _dropUnreadStorage(out, mountStart, mount.constructor.parameters);
}

/// Removes each stored argument the mount at [start] of [out] never reads.
void _dropUnreadStorage(
  StringBuffer out,
  int start,
  Iterable<_ResolvedMountParameter> parameters,
) {
  final text = out.toString();
  var mount = text.substring(start);
  for (final parameter in parameters) {
    if (!parameter.requiresStorage || parameter.isKey) continue;
    final slot = parameter.slotName;
    final storage = parameter.storageName;
    final direct = slot == storage;
    // Reads besides its declaration, its getter and its initializers.
    final reads = mount
        .replaceAll('$storage = ', '')
        .replaceAll('final ${parameter.typeCode} $storage;', '');
    if (RegExp('\\b$slot\\b').allMatches(reads).length > (direct ? 0 : 1)) {
      continue;
    }
    mount = mount
        // Both constructors store it.
        .replaceAll('$storage = ${parameter.name},\n       ', '')
        .replaceFirst(
          '\n  final ${parameter.typeCode} $storage;\n'
              '${direct ? '' : '  ${parameter.typeCode} get $slot => $storage;\n'}',
          '',
        );
  }
  out
    ..clear()
    ..write(text.substring(0, start))
    ..write(mount);
}

/// [libraries], a list source or null, with the registration of the mount's
/// own islands, so the mount renders them without an app-wide registration.
String? _withIslandLibrary(String? libraries, _ResolvedScreenMount mount) {
  if (mount.islands.isEmpty) return libraries;
  final islands = islandRegistrationName([
    for (final island in mount.islands) island.name,
  ]);
  return libraries == null ? '[$islands]' : '[...$libraries, $islands]';
}

// What island factories spell through the Restage import, by origin.
const _kIslandSdkSymbols = {
  'DataSource': 'package:rfw',
  'ArgumentDecoders': 'package:rfw',
  'RestageDecoders': 'package:restage_core',
  'RestageValueBinding': 'package:restage_core',
  'RestageIslandScope': _restageSdkOrigin,
  'RestageIslandPlaceholder': _restageSdkOrigin,
  'RestageWidgetFactory': _restageSdkOrigin,
  'RestageWidgetLibraryRegistration': _restageSdkOrigin,
  'WidgetLibrary': 'package:rfw_catalog_schema',
};

/// Each island's factory, which the mount registers, and its mount-free
/// builder, which previews supply to the island scope.
void _writeIslandDeclarations(
  StringBuffer buffer,
  _ResolvedScreenMount mount,
  String mountName, {
  bool step = false,
}) {
  final sdk = mount.sdk;
  final flutter = mount.flutter;
  buffer
    ..writeln()
    ..writeln(
      'const ${islandRegistrationName([for (final island in mount.islands) island.name])} = '
      '${islandLibraryRegistrationSource(mount.islands.first.library, [for (final island in mount.islands) island.name], sdk)};',
    );
  for (final island in mount.islands) {
    buffer
      ..writeln()
      ..writeln(
        islandFactorySource(
          island.name,
          widget: island.widget,
          location: island.location,
          mount: mountName,
          step: step,
          sdk: sdk,
          flutter: flutter,
        ),
      );
    final hole = _islandHole(
      island,
      mount,
      (name) => name == kRootContext ? 'restageContext' : name,
    );
    final preview =
        _owningBuilders(
          island,
          island.previewSource(hole),
          source: 'restageSource',
          context: 'restageContext',
          sdk: sdk,
        ) ??
        '${sdk}RestageIslandPlaceholder(label: '
            '${dartStringLiteral(island.widget)}, children: [${[
              for (final slot in island.slots)
                if (slot.builder == null) '${slot.list ? '...' : ''}${hole(slot.name)}',
            ].join(', ')}])';
    buffer
      ..writeln()
      ..writeln(
        '${flutter}Widget ${islandPreviewName(island)}('
        '${flutter}BuildContext restageContext, '
        '${sdk}DataSource restageSource) =>',
      )
      ..writeln('    $preview;');
  }
}

/// [template], an island's build, owning a binding for each of its app
/// builders.
String? _owningBuilders(
  Island island,
  String? template, {
  required String source,
  required String context,
  required String sdk,
}) {
  final builders = {
    for (final slot in island.slots)
      if (slot.builder case final builder?) slot.name: builder,
  };
  return template == null || builders.isEmpty
      ? template
      : AppValueSlot.owning(
          template,
          builders,
          source: source,
          context: context,
          sdk: sdk,
        );
}

/// How an island's source reads its slot or property [argument] from the
/// payload, falling back to the property as written.
String Function(String argument) _islandHole(
  Island island,
  _ResolvedScreenMount mount,
  String Function(String) slot,
) => (argument) {
  final path = "const <Object>[${dartStringLiteral(argument)}]";
  for (final value in island.slots) {
    if (value.name == argument) {
      if (value.builder case final builder?) {
        return builder.callback(
          AppValueSlot.bindingName(argument),
          sdk: mount.sdk,
        );
      }
      return 'restageSource.${value.list ? 'childList' : 'child'}($path)';
    }
  }
  final property = island.properties.firstWhere(
    (value) => value.name == argument,
  );
  final decoded = decoderCallFor(
    islandWidgetEntry(
      island,
    ).properties.firstWhere((entry) => entry.name == argument),
    source: 'restageSource',
    context: 'restageContext',
    sdk: mount.sdk,
  );
  return property.previewSource(decoded, slot);
};

/// Extra entries the mount adds to one list item, given that item's source.
final class _ItemEntries {
  const _ItemEntries(this.entries, {this.indexed = false, this.wrap});

  /// One item's whole map, given its source and the map; the map itself
  /// when absent.
  final String Function(String item, String map)? wrap;

  /// The entries for one item, given its source and its list position.
  final String Function(String item, String index) entries;

  /// Whether the entries read the item's position.
  final bool indexed;
}

/// The context entries naming each recorded text scaler, and each native
/// binding outside a loop, by its inert reference.
List<String> _nativeContextEntries(
  Iterable<HoistedValue> scalers,
  Iterable<HoistedValue> bindings,
) => [
  for (final value in scalers)
    '${dartStringLiteral(value.key)}: <String, Object?>{'
        '"kind": "native", "key": ${dartStringLiteral(value.key)}}',
  for (final value in bindings)
    if (value.item == null)
      '${dartStringLiteral(value.key)}: '
          '${_nativeReference(value, dartStringLiteral(value.key))}',
];

/// The inert reference a surface reads for a native binding.
String _nativeReference(HoistedValue value, String key) {
  final contract = value.nativeContract!;
  return '<String, Object?>{"kind": "nativeBinding", "key": $key, '
      '"type": ${dartStringLiteral(contract.type)}, '
      '"nullable": ${contract.nullable}}';
}

String _mountHostDataValue(
  HostDataShape shape,
  String source, [
  int depth = 0,
  _ItemEntries? itemEntries,
]) {
  if (!shape.requiresEncoding) return source;
  final nullable = shape.type.nullabilitySuffix == NullabilitySuffix.question;
  if (nullable) {
    final present = 'restagePresent$depth';
    return 'switch ($source) { final $present? => '
        '${_mountNonNullHostDataValue(shape, present, depth, itemEntries)}, '
        'null => null }';
  }
  return _mountNonNullHostDataValue(shape, source, depth, itemEntries);
}

String _mountNonNullHostDataValue(
  HostDataShape shape,
  String source,
  int depth, [
  _ItemEntries? itemEntries,
]) {
  final value = 'restageValue$depth';
  final entry = 'restageEntry$depth';
  return switch (shape) {
    HostDataDateTimeShape() =>
      "<String, Object?>{'microsecondsSinceEpoch': $source.microsecondsSinceEpoch, "
          "'isUtc': $source.isUtc}",
    HostDataObjectShape() => _mountObjectValue(
      shape,
      source,
      depth,
      itemEntries,
    ),
    HostDataListShape(:final elementShape) =>
      itemEntries?.indexed ?? false
          ? '<Object?>[for (final (restageIndex$depth, $value) in $source.indexed) '
                '${_mountHostDataValue(
                  elementShape,
                  value,
                  depth + 1,
                  _ItemEntries((item, _) => itemEntries!.entries(item, 'restageIndex$depth'), wrap: itemEntries?.wrap),
                )}]'
          : '<Object?>[for (final $value in $source) '
                '${_mountHostDataValue(
                  elementShape,
                  value,
                  depth + 1,
                  itemEntries,
                )}]',
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
  int depth, [
  _ItemEntries? itemEntries,
]) {
  String fieldValue(HostDataObjectField field) {
    final value = '$source.${field.wireKey}';
    return '${dartStringLiteral(field.wireKey)}: '
        '${_mountHostDataValue(field.shape, value, depth + 1)}';
  }

  final fields = [
    for (final field in shape.fields) fieldValue(field),
    if (itemEntries != null) itemEntries.entries(source, ''),
  ];
  final map = '<String, Object?>{${fields.join(', ')}}';
  return itemEntries?.wrap?.call(source, map) ?? map;
}

Iterable<_ResolvedScreenEvent> _eventsInSchemaOrder(
  ResolvedStandaloneScreenContract contract,
) sync* {
  for (final schemaEvent in contract.eventSchema.events) {
    yield contract._events.singleWhere((event) => event.id == schemaEvent.id);
  }
}

/// Emits the bundle locator for [contract], or null outside Flutter assets.
/// Paths use the resolved output plan and surface identity. Hashes and lengths
/// come from [ResolvedStandaloneScreenContractInput.bundleEntryMetadata].
/// Throws when a bundled-runtime locator requires missing entry metadata.
String? _resolveBundleLocatorSource(
  ResolvedStandaloneScreenContract contract,
  String sdk,
) {
  final plan = contract.input.plan ?? RestageOutputLocationPlan.defaults;
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
  final sidecarPath =
      metadata.sidecarPath ??
      'assets/$surfaceKey/screens/${contract.slug}.capability.json';
  final buffer = StringBuffer()
    ..writeln('${sdk}SurfaceScreenBundleLocator(')
    ..writeln('  assetKey: ${dartStringLiteral(assetKey)},')
    ..writeln('  packageName: ${dartStringLiteral(assetId.package)},')
    ..writeln('  authoredLibraryPath: ${dartStringLiteral(assetId.path)},')
    ..writeln('  entries: [')
    ..writeln('    ${sdk}SurfaceScreenBundleEntryReference(')
    ..writeln('      logicalPath: ${dartStringLiteral(blobPath)},')
    ..writeln('      role: ${sdk}RestageBundleEntryRole.screenBlob,')
    ..writeln('      byteLength: ${metadata.blobByteLength},')
    ..writeln('      sha256: ${dartStringLiteral(metadata.blobSha256)},')
    ..writeln('    ),')
    ..writeln('    ${sdk}SurfaceScreenBundleEntryReference(')
    ..writeln('      logicalPath: ${dartStringLiteral(sidecarPath)},')
    ..writeln('      role: ${sdk}RestageBundleEntryRole.capabilitySidecar,')
    ..writeln('      byteLength: ${metadata.sidecarByteLength},')
    ..writeln('      sha256: ${dartStringLiteral(metadata.sidecarSha256)},')
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
      ..writeln('      namespace: ${dartStringLiteral(requirement.namespace)},')
      ..writeln('      minVersion: ${requirement.minVersion},');
    if (requirement.minGenerated > 1) {
      buffer.writeln('      minGenerated: ${requirement.minGenerated},');
    }
    buffer.writeln('    ),');
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
  final eventStem = _eventStem(screenName);
  final refStem = _lowerCamelIdentifier(screenName, fallback: 'surfaceScreen');
  final hasEvents = events.isNotEmpty;
  return <String>[
    if (hasEvents) '${eventStem}Event',
    '_${refStem}Events',
    '_${refStem}Provenance',
    if (hasEvents) '_decodeValidated${eventStem}Event',
    generatedHandleName(screenName, fallback: 'surfaceScreen'),
    if (hasEvents)
      for (final event in events) _eventClassName(eventStem, event.field.name),
  ];
}

List<String> _generatedTopLevelSymbols(
  String screenName,
  Iterable<_ResolvedScreenEvent> events,
  _ResolvedScreenMount? mount,
) => [
  ..._referenceGeneratedTopLevelSymbols(screenName, events),
  if (mount != null) ...[
    generatedSurfaceName(screenName, fallback: 'SurfaceScreen'),
    ...placementDefinitionSymbols(screenName),
    for (final binding in mount.constructor.defaultBindings) binding.name,
  ],
];

String _mountDefaultBindingName(String screenName, int ordinal) =>
    '_${_lowerCamelIdentifier(screenName, fallback: 'surfaceScreen')}'
    'MountDefault$ordinal';

/// The stem of a screen's generated event types: `<Class>Surface`.
String _eventStem(String screenName) =>
    '${_pascalIdentifier(screenName, fallback: 'SurfaceScreen')}Surface';

String _eventClassName(String eventStem, String? fieldName) =>
    '$eventStem${_pascalIdentifier(fieldName ?? '', fallback: 'Event')}Event';

Set<String> _owningLibrarySourceNames(
  ResolvedWidgetMountInput input,
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

/// Returns the generated screen part declared by this library.
/// Matches the resolved output path against analyzer fragments. Other generated
/// siblings or paths remain collisions, including in warm builds.
AssetId? _declaredGeneratedPart(
  ResolvedWidgetMountInput input,
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

// Flutter's own StatelessWidget or StatefulWidget.
bool _isFrameworkWidgetBase(InterfaceElement element) =>
    (element.name == 'StatelessWidget' || element.name == 'StatefulWidget') &&
    element.library.identifier == 'package:flutter/src/widgets/framework.dart';

/// Why a mount cannot extend [base] the way its surface does: a constructor
/// that needs more than a key, or members it leaves for the surface to write
/// besides its build.
String? _baseProblem(InterfaceType base) {
  final constructor = base.element.unnamedConstructor;
  if (constructor == null ||
      constructor.isFactory ||
      constructor.formalParameters.any(
        (parameter) => parameter.isRequired && parameter.name != 'key',
      )) {
    return '`${base.element.name}` requires constructor arguments';
  }
  for (final owner in [base, ...base.allSupertypes]) {
    for (final member in [...owner.element.methods, ...owner.element.getters]) {
      final name = member.name ?? '';
      if (!member.isAbstract || name == 'build' || name == 'createState') {
        continue;
      }
      final concrete = member is GetterElement
          ? base.lookUpGetter(name, base.element.library, concrete: true)
          : base.lookUpMethod(name, base.element.library, concrete: true);
      if (concrete == null) {
        return '`${base.element.name}` leaves `$name` without a body';
      }
    }
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
  ResolvedWidgetMountInput input,
  IssueCode code,
  String message,
) => Issue(code: code, message: message, location: input.location);

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
    required this.reservedNativeNames,
    required this.constructor,
    required this.hoisted,
    required this.islands,
    required this.split,
    required this.nativeScopeType,
    required this.nativeContractType,
    required this.base,
    required this.buildParameters,
  });

  final String sdk;
  final String flutter;
  final Set<String> reservedNativeNames;
  final List<HoistedValue> hoisted;

  /// Widget expressions the mount renders from the app.
  final List<Island> islands;

  /// How the mount takes over the surface's shell and `State`.
  final MountSplit? split;
  final String? nativeScopeType;
  final String? nativeContractType;

  /// The screen's base class, when the mount must extend it.
  final String? base;

  /// The build parameters after the context, as `Type name`.
  final List<String> buildParameters;
  final _ResolvedMountConstructorContract constructor;

  /// This mount spelling SDK names with [sdk].
  _ResolvedScreenMount withSdk(String sdk) => _ResolvedScreenMount(
    sdk: sdk,
    flutter: flutter,
    reservedNativeNames: reservedNativeNames,
    constructor: constructor,
    hoisted: hoisted,
    islands: islands,
    split: split,
    nativeScopeType: nativeScopeType,
    nativeContractType: nativeContractType,
    base: base,
    buildParameters: buildParameters,
  );
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
    (parameter) => parameter.kind == RootContextParamKind.optionalPositional,
  );

  bool get requiresKeyType => hasOptionalPositional && !hasKeyParameter;

  /// A non-nullable authored key belongs to the fallback widget alone, so the
  /// mount does not also take it.
  String? get explicitSuperKeySource => parameters
      .where(
        (parameter) =>
            parameter.isKey &&
            parameter.isNullableKey &&
            !parameter.usesStatelessWidgetSuperFormal &&
            !parameter.forwardsAsSuperKey,
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

  /// The field behind [slotName], which reads it through a getter.
  String get storageName =>
      slotName.replaceFirst('_restageArgument', '_restageStored');

  String? get defaultValueCode => defaultBinding?.name;

  String get declarationSource {
    final required = isRequired && kind == RootContextParamKind.named
        ? 'required '
        : '';
    final defaultValue = defaultValueCode;
    final defaultSource = defaultValue == null ? '' : ' = $defaultValue';
    if (isKey && usesStatelessWidgetSuperFormal) {
      final type = root.hasExplicitType ? '$typeCode ' : '';
      return '$required${type}super.$name$defaultSource';
    }
    if (forwardsAsSuperKey) {
      final type = _isFlutterKey(root.type) ? '' : '$typeCode ';
      return '${type}super.key$defaultSource';
    }
    return '$required$typeCode $name$defaultSource';
  }

  /// This parameter's value in the mount's build, read through [read].
  String fallbackSource(String Function(String member) read) {
    // A stored `key` is the build's own local.
    if (isKey && name == 'key' && requiresStorage) return name;
    if (isKey && !requiresStorage) return read(name);
    return read(slotName);
  }

  /// An optional named `key` the mount passes straight to its own super key.
  bool get forwardsAsSuperKey =>
      isKey &&
      isNullableKey &&
      !usesStatelessWidgetSuperFormal &&
      name == 'key' &&
      kind == RootContextParamKind.named &&
      !isRequired;

  /// Whether this key parameter can carry a Flutter key the mount forwards.
  bool get isNullableKey =>
      root.type.nullabilitySuffix == NullabilitySuffix.question;

  /// This parameter's fallback-widget argument, or null to omit it; a key the
  /// mount forwards to `super` never also reaches the fallback widget.
  String? fallbackArgumentSource(String Function(String member) read) {
    if (!isKey || !isNullableKey) return fallbackSource(read);
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

bool _isFlutterKey(DartType type) =>
    type is InterfaceType &&
    type.element.name == 'Key' &&
    libraryUriMatchesOrigin(type.element.library.identifier, _flutterOrigin);

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

  final PropertyInducingElement field;
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

/// Emits the wrapper of [split]; see [emitSplitWidgetWrapper].
({String? source, String? registration, String? omissionMessage})
emitSplitWidget(SplitWidgetInput split) => emitSplitWidgetWrapper(
  split.mount,
  entry: split.entry,
  custom: split.custom,
);

/// Emits the wrapper of the split widget [input] with catalog [entry]: a
/// factory for `<entry>__split` and a widget that holds the widget's State,
/// records its build and renders the delivered body with what it recorded.
({String? source, String? registration, String? omissionMessage})
emitSplitWidgetWrapper(
  ResolvedWidgetMountInput input, {
  required WidgetEntry entry,
  CustomReconstruction? custom,
}) {
  final screenName = input.screen.name!;
  final wrapper = splitFactoryName(entry.name);
  final result = _resolveScreenMount(
    input,
    reservedGeneratedSymbols: const {},
    missing: "`$wrapper` wasn't generated",
  );
  final mount = result.mount;
  final recordedTemplate = mount?.split?.recorded;
  if (mount == null || recordedTemplate == null) {
    return (
      source: null,
      registration: null,
      omissionMessage:
          result.message ??
          "`$wrapper` wasn't generated because `$screenName`'s build can't "
              'be recorded. Please report this as a Restage bug.',
    );
  }
  final sdk = mount.sdk;
  final flutter = mount.flutter;
  final state = mount.split?.state;
  final widgetClass = '_restageWidget\$${_identifierOf(entry.name)}';
  final factory = '_restageBuild\$${_identifierOf(wrapper)}';
  final slots = <String, String>{
    for (final parameter in mount.constructor.values)
      parameter.name: '_restageWidget.${parameter.name}',
    kSurfaceInstance: '_restageWidget',
    kRootContext: 'context',
    kStateWidget: '_restageWidget',
    'restageDidUpdateWidget': '_restageDidUpdateWidget',
  };
  // The widget the delivered design placed, from its arguments.
  String surfaceFrom(String source) =>
      '$screenName(${[
        for (final parameter in mount.constructor.parameters)
          if (!parameter.isKey)
            if (_splitArgument(entry, parameter, source, sdk, custom) case final value) parameter.kind == RootContextParamKind.named ? '${parameter.name}: $value' : value,
      ].join(', ')})';
  final buffer = StringBuffer();
  final islands = mount.islands;
  if (islands.isNotEmpty) {
    _writeIslandDeclarations(buffer, mount, wrapper);
  }
  buffer
    ..writeln()
    // Keyed as the fallback keys its placement, the wrapper keeps its State
    // between the design and the fallback.
    ..writeln(
      '${flutter}Widget $factory(${flutter}BuildContext context, '
      '${sdk}DataSource source) =>',
    )
    ..writeln(
      '    ${sdk}RestageIslandScope.split(context, source, '
      '() => $widgetClass(source: source));',
    )
    ..writeln()
    ..writeln('/// [widget], placed by the app, as the design places it.')
    ..writeln(
      '${flutter}Widget ${splitAppName(entry.name)}($screenName widget) => '
      '$widgetClass.app(widget);',
    )
    ..writeln()
    ..writeln('final class $widgetClass extends ${flutter}StatefulWidget {')
    ..writeln(
      '  const $widgetClass({required ${sdk}DataSource this.source}) '
      ': app = null;',
    )
    ..writeln('  const $widgetClass.app($screenName this.app) : source = null;')
    ..writeln()
    ..writeln('  final ${sdk}DataSource? source;')
    ..writeln('  final $screenName? app;')
    ..writeln()
    ..writeln('  @override')
    ..writeln('  _${widgetClass}State createState() => _${widgetClass}State();')
    ..writeln('}')
    ..writeln()
    ..writeln(
      'final class _${widgetClass}State '
      '${state?.header(widgetClass) ?? 'extends ${flutter}State<$widgetClass>'} {',
    )
    ..writeln(
      '  $screenName get _restageWidget => '
      "widget.app ?? ${surfaceFrom('widget.source!')};",
    );
  for (final member
      in state?.members(widgetClass, (name) => slots[name]!) ??
          const <String>[]) {
    buffer
      ..writeln()
      ..writeln('  // ignore: unused_element')
      ..writeln('  $member');
  }
  if (state?.updates ?? false) {
    buffer
      ..writeln()
      ..writeln('  @override')
      ..writeln('  // ignore: must_call_super')
      ..writeln('  void didUpdateWidget(covariant $widgetClass oldWidget) =>')
      ..writeln(
        '      _restageDidUpdateWidget(oldWidget.app ?? '
        "${surfaceFrom('oldWidget.source!')}, oldWidget);",
      );
  }
  // The build decodes the widget once and reads it from there.
  final buildSlots = <String, String>{
    for (final MapEntry(:key, :value) in slots.entries)
      key: value.replaceFirst(RegExp(r'^_restageWidget\b'), '_restageSurface'),
  };
  final recorded = _withIslandSlots(
    mount.split!.recordedSource((name) => buildSlots[name]!)!,
    mount,
  ).replaceAll(kSdkPrefixMarker, sdk);
  final scope = islands.isEmpty
      ? null
      : '${sdk}RestageIslandScope(owner: context, builders: {${[
          for (final island in islands) '${dartStringLiteral(island.name)}: (_restageContext, _restageSource) => '
                '_restageRecording.islandAt(${dartStringLiteral(island.name)}, [${[
                  for (final (level, _) in island.items.indexed) '_restageSource.v<int>(const <Object>'
                        "['$kPlacementItemsArgument', $level])!",
                ].join(', ')}], _restageContext, _restageSource)',
        ].join(', ')}}, child: ';
  final nativeBindings = [
    for (final value in mount.hoisted)
      if (value.kind == HoistValueKind.nativeBinding && value.computed) value,
  ];
  final scalers = [
    for (final value in mount.hoisted)
      if (value.kind == HoistValueKind.textScaler) value,
  ];
  String? natives;
  if ((nativeBindings.isNotEmpty || scalers.isNotEmpty) &&
      mount.nativeScopeType != null) {
    final scopeType = mount.nativeScopeType!;
    var bindings = '';
    if (nativeBindings.isNotEmpty) {
      final sharedPrefix = mount.nativeContractType!.replaceFirst(
        RegExp(r'NativeBindingContract$'),
        '',
      );
      final contracts = [
        for (final value in nativeBindings)
          '${dartStringLiteral(value.key)} => '
              '${nativeContractSource(value.nativeContract!, sharedPrefix)}',
      ].join(', ');
      bindings =
          'bindings: _restageRecording.bindings((key) => '
          "switch (key.split('#').first) {$contracts, "
          '_ => throw StateError(key)}), ';
    }
    natives =
        '$scopeType(${scalers.isEmpty ? '' : 'textScalers: '
                  '_restageRecording.scalers, '}${bindings}child: ';
  }
  // The body reads each native through its inert reference, as a surface does.
  final topNatives = _nativeContextEntries(scalers, nativeBindings);
  final recordedValues = topNatives.isEmpty
      ? '_restageRecording.values'
      : '{..._restageRecording.values, ${topNatives.join(', ')}}';
  buffer
    ..writeln()
    ..writeln('  @override')
    ..writeln('  ${flutter}Widget build(${flutter}BuildContext context) {')
    ..writeln('    // ignore: unused_local_variable')
    ..writeln(
      '    final _restageRecording = ${sdk}RestageRecording(owner: context);',
    )
    ..writeln('    // ignore: unused_local_variable')
    ..writeln('    final _restageSurface = _restageWidget;')
    // The delivered body renders with what the build recorded; without one
    // the widget is the build's own.
    ..writeln(
      '    ${flutter}Widget _restageDesign(${flutter}Widget _restageBuilt) =>',
    )
    // The body binds below the native scope, so it reads its values.
    ..writeln(
      '        ${natives ?? ''}${scope ?? ''}'
      '${natives == null ? '' : '${flutter}Builder(builder: (context) => '}'
      '${sdk}RestageBuilderBinding.construct((_restageBindings) {',
    )
    ..writeln('          final _restageSource = widget.source;')
    ..writeln('          if (_restageSource == null) return _restageBuilt;')
    ..writeln(
      '          final _restageBody = ${sdk}RestageBuilderBinding.optional('
      '_restageSource, const <Object>[${dartStringLiteral(kSplitWidgetScope)}], '
      'context: context);',
    )
    ..writeln('          if (_restageBody == null) return _restageBuilt;')
    ..writeln('          _restageBindings.add(_restageBody);')
    ..writeln(
      '          return _restageBody.buildNullable(context, const {}, '
      'recorded: $recordedValues) ?? const ${flutter}SizedBox.shrink();',
    )
    ..writeln(
      '        })${scope == null ? '' : ')'}${natives == null ? '' : '))'};',
    )
    ..writeln('    return ($recorded)();')
    ..writeln('  }')
    ..writeln('}');
  // The wrapper registers in the widget's own library, beside its factory.
  final registration = splitRegistrationName(entry.name);
  buffer
    ..writeln()
    ..writeln(
      'const $registration = ${sdk}RestageWidgetLibraryRegistration'
      '.constant(library: ${sdk}WidgetLibrary.custom('
      '${dartStringLiteral(entry.library.namespace)}), '
      '${widgetLibraryVersionArguments().join(' ')} widgets: ['
      '${sdk}RestageWidgetFactory(name: ${dartStringLiteral(wrapper)}, '
      'builder: $factory)]);',
    );
  return (
    source: buffer.toString(),
    registration: registration,
    omissionMessage: null,
  );
}

/// The registration constant of the wrapper of the split widget [name].
String splitRegistrationName(String name) =>
    'restageSplit\$${_identifierOf(name)}';

// A borrowed input read inside an interpolation is written as `{x}`; the
// binding passes the input itself.
String _borrowedSource(String source) =>
    RegExp(r'^\{([^{}:,]+)\}$').firstMatch(source)?.group(1) ?? source;

String _identifierOf(String name) =>
    name.replaceAll(RegExp(r'[^A-Za-z0-9_$]'), '_');

// How the wrapper reads the argument [parameter] the delivered design passed.
String _splitArgument(
  WidgetEntry entry,
  _ResolvedMountParameter parameter,
  String source,
  String sdk,
  CustomReconstruction? custom,
) {
  PropertyEntry? property;
  for (final candidate in entry.properties) {
    if (candidate.name == parameter.name) property = candidate;
  }
  final path = "const <Object>[${dartStringLiteral(parameter.name)}]";
  final nullable = parameter.typeCode.endsWith('?');
  // A custom value decodes as the package's own factory decodes it.
  final reconstructed = property == null
      ? null
      : customFactoryValue(entry, property, custom);
  final read = switch (property?.type) {
    _ when reconstructed != null =>
      '((${sdk}DataSource source) => $reconstructed)($source)',
    PropertyType.widget =>
      '$source.${nullable ? 'optionalChild' : 'child'}($path)',
    PropertyType.widgetList => '$source.childList($path)',
    _ when property != null => decoderCallFor(
      property,
      source: source,
      context: 'context',
      sdk: sdk,
    ),
    _ => 'null',
  };
  // A reconstructed value that can't be null takes no `!`.
  final nonNull =
      reconstructed != null &&
      !customFactoryValueIsNullable(entry, property!, custom);
  return nullable ||
          nonNull ||
          property?.type == PropertyType.widget ||
          property?.type == PropertyType.widgetList
      ? read
      : '($read)!';
}

// [recorded] with each island's slot and property marker read from the
// payload the delivered design passes the island.
String _withIslandSlots(
  String recorded,
  _ResolvedScreenMount mount,
) => recorded.replaceAllMapped(
  RegExp('\u0002([A-Za-z0-9_\$]+)\\|([A-Za-z0-9_\$]+)\u0002'),
  (match) {
    final island = mount.islands.firstWhere(
      (island) => island.name == match[1],
    );
    final argument = match[2]!;
    final path = "const <Object>[${dartStringLiteral(argument)}]";
    for (final value in island.slots) {
      if (value.name == argument) {
        return '_restageSource.${value.list ? 'childList' : 'child'}($path)';
      }
    }
    return decoderCallFor(
      islandWidgetEntry(
        island,
      ).properties.firstWhere((entry) => entry.name == argument),
      source: '_restageSource',
      context: '_restageContext',
      sdk: mount.sdk,
    );
  },
);
