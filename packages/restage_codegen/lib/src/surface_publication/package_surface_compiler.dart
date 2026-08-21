// Deterministic package-level assembly for canonical Restage publications.
//
// This is intentionally a pure seam. The aggregate build owner supplies
// analyzer-resolved declarations, roster-owned output paths, and already
// rendered bytes; this module neither scans directories nor chooses a source
// artifact path from a human-authored Dart reference.
// ignore_for_file: public_member_api_docs

import 'dart:convert';
import 'dart:typed_data';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart' show AssetId;
import 'package:crypto/crypto.dart' as crypto;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:restage_codegen/src/emit_utils.dart';
import 'package:restage_codegen/src/helper_registry.dart'
    show libraryUriMatchesOrigin;
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_codegen/src/measurement/measurement_publication_planner.dart';
import 'package:restage_codegen/src/measurement/measurement_rfw_route_composer.dart';
import 'package:restage_codegen/src/measurement/measurement_route_emission.dart';
import 'package:restage_codegen/src/neutral_part_directive.dart';
import 'package:restage_codegen/src/onboarding/flow_definition_frontend.dart';
import 'package:restage_codegen/src/restage_source_roster.dart';
import 'package:restage_codegen/src/surface_publication/generated_handle_names.dart';
import 'package:restage_codegen/src/surface_publication/legacy_screen_contract_adapter.dart';
import 'package:restage_codegen/src/surface_publication/manifest_assembler.dart';
import 'package:restage_codegen/src/surface_publication/paywall_artifact_adapter.dart';
import 'package:restage_codegen/src/surface_publication/screen_contract_reference_emitter.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

const String _restageSdkOrigin = 'package:restage';

/// Bytes produced for one analyzer-resolved ordinary screen or paywall.
///
/// The aggregate owner supplies this only after the source compiler has
/// completed its RFW translation. Identity, version, source kind, output
/// paths, and category are deliberately recovered from [RestageSourceRoster]
/// rather than duplicated here.
@immutable
final class CompiledSurfaceArtifact {
  CompiledSurfaceArtifact({
    required this.declaration,
    required List<int> blob,
    required List<int> capabilitySidecar,
    required this.flowArtifactPath,
    this.flowScreenId,
    this.paywallFacts,
    List<int>? rfwText,
    List<int>? navigationPlan,
  })  : _blob = Uint8List.fromList(blob),
        _capabilitySidecar = Uint8List.fromList(capabilitySidecar),
        _rfwText = rfwText == null ? null : Uint8List.fromList(rfwText),
        _navigationPlan =
            navigationPlan == null ? null : Uint8List.fromList(navigationPlan);

  /// Bridges the C2c-owned paywall adapter into the category-neutral package
  /// compiler without letting this module derive any paywall sibling path.
  factory CompiledSurfaceArtifact.fromPaywallAdapter({
    required ClassElement declaration,
    required PaywallArtifactFacts facts,
    required String flowArtifactPath,
    List<int>? rfwText,
    List<int>? navigationPlan,
  }) =>
      CompiledSurfaceArtifact(
        declaration: declaration,
        blob: facts.adapter.blob.bytes,
        capabilitySidecar: facts.adapter.capabilitySidecar.bytes,
        flowArtifactPath: flowArtifactPath,
        flowScreenId: facts.adapter.id,
        paywallFacts: facts,
        rfwText: rfwText,
        navigationPlan: navigationPlan,
      );

  /// The resolved authored `@Screen` or `@Paywall` class.
  final ClassElement declaration;

  final Uint8List _blob;
  final Uint8List _capabilitySidecar;
  final Uint8List? _rfwText;
  final Uint8List? _navigationPlan;

  /// The delivery-local path preserved in a [ScreenArtifact] inside a flow.
  ///
  /// It is source-compiler output, not a value selected by a human-authored
  /// generated reference. It remains distinct from the roster-owned package
  /// path carried by the manifest.
  final String flowArtifactPath;

  /// The screen ID used only when this source is an embedded paywall adapter.
  /// Ordinary screens use their roster-owned effective ID.
  final String? flowScreenId;

  /// Complete specialized paywall family when this artifact is an adapter.
  final PaywallArtifactFacts? paywallFacts;

  Uint8List get blob => Uint8List.fromList(_blob);

  Uint8List get capabilitySidecar => Uint8List.fromList(_capabilitySidecar);

  Uint8List? get rfwText {
    final text = _rfwText;
    return text == null ? null : Uint8List.fromList(text);
  }

  Uint8List? get navigationPlan {
    final plan = _navigationPlan;
    return plan == null ? null : Uint8List.fromList(plan);
  }

  String get declarationIdentity =>
      '${declaration.library.identifier}#${declaration.name ?? '<unnamed>'}';
}

/// Aggregate inputs consumed by [compilePackageSurfacePublications].
@immutable
final class PackageSurfaceCompilationInput {
  PackageSurfaceCompilationInput({
    required this.roster,
    required Iterable<NormalizedFlowSource> flows,
    required Iterable<CompiledSurfaceArtifact> renderedSources,
    required Iterable<ResolvedStandaloneScreenContract> standaloneScreens,
    Iterable<LegacyStandaloneScreenContract> legacyStandaloneScreens = const [],
    Iterable<CompiledFlowArtifact> precompiledFlows = const [],
    Map<String, MeasurementPublicationRoutePlanV1>
        measurementRoutePlansByPublicationKey = const {},
    Map<String, String> generatedSourceCarrierDraftDigestsByPublicationKey =
        const {},
  })  : flows = List.unmodifiable(flows),
        renderedSources = List.unmodifiable(renderedSources),
        standaloneScreens = List.unmodifiable(standaloneScreens),
        legacyStandaloneScreens = List.unmodifiable(legacyStandaloneScreens),
        precompiledFlows = List.unmodifiable(precompiledFlows),
        measurementRoutePlansByPublicationKey = Map.unmodifiable(
          measurementRoutePlansByPublicationKey,
        ),
        generatedSourceCarrierDraftDigestsByPublicationKey = Map.unmodifiable(
          generatedSourceCarrierDraftDigestsByPublicationKey,
        );

  /// Canonical package source/output ownership record.
  final RestageSourceRoster roster;

  /// Flattened flow definitions accepted by the analyzer frontend.
  final List<NormalizedFlowSource> flows;

  /// Complete rendered source artifacts. Paywall adapters use the same value
  /// type; this compiler does not manufacture paywall-specific outputs.
  final List<CompiledSurfaceArtifact> renderedSources;

  /// Categorized ordinary-screen contracts produced by C1.
  final List<ResolvedStandaloneScreenContract> standaloneScreens;

  /// Deprecated standalone-screen contracts adapted without claiming a new
  /// generated reference or a second artifact writer.
  final List<LegacyStandaloneScreenContract> legacyStandaloneScreens;

  /// Exact documents emitted by the proven class-shaped/legacy frontend.
  final List<CompiledFlowArtifact> precompiledFlows;

  /// Carrier-independent route plans keyed by exact publication selector.
  final Map<String, MeasurementPublicationRoutePlanV1>
      measurementRoutePlansByPublicationKey;

  /// Final draft digests the compiler attaches only to generated source
  /// descriptors after exact Measurement artifact finalization.
  ///
  /// The aggregate validates every supplied value against the final draft it
  /// just built. This is generated-only output, not a manifest field or an
  /// authoring input.
  final Map<String, String> generatedSourceCarrierDraftDigestsByPublicationKey;
}

@immutable
final class CompiledFlowArtifact {
  CompiledFlowArtifact({
    required this.declaration,
    required List<int> flowDocumentBytes,
    this.generatedPart,
  }) : flowDocumentBytes = Uint8List.fromList(flowDocumentBytes);

  final Element declaration;
  final Uint8List flowDocumentBytes;
  final String? generatedPart;

  String get declarationIdentity =>
      '${declaration.library?.identifier ?? '<unknown>'}#'
      '${declaration.name ?? '<unnamed>'}';
}

/// A complete, write-ready aggregate bundle.
///
/// The package owner writes [outputFiles], [generatedParts], and [manifestJson]
/// atomically only after [PackageSurfaceCompilationResult.isValid] is true.
@immutable
final class PackageSurfaceCompilationBundle {
  PackageSurfaceCompilationBundle({
    required this.manifest,
    required Map<String, List<int>> outputFiles,
    required Map<String, String> generatedParts,
    required Set<String> aggregateOwnedOutputPaths,
    required Map<String, String> artifactLibraryPaths,
    Iterable<MeasurementCompilerPublication> measurementPublications = const [],
  })  : _outputFiles = _freezeFileMap(outputFiles),
        _aggregateOwnedOutputPaths = Set.unmodifiable(
          aggregateOwnedOutputPaths,
        ),
        _artifactLibraryPaths = Map.unmodifiable(
          Map.of(artifactLibraryPaths),
        ),
        generatedParts = Map.unmodifiable(Map.of(generatedParts)),
        measurementPublications = List.unmodifiable(measurementPublications),
        manifestJson = SurfacePublicationManifestV1Codec.encodeCanonicalJson(
          manifest,
        );

  /// Strict shared DTO used by publication and delivery consumers.
  final SurfacePublicationManifest manifest;

  /// Canonical manifest bytes as UTF-8 text.
  final String manifestJson;

  final Map<String, Uint8List> _outputFiles;
  final Set<String> _aggregateOwnedOutputPaths;
  final Map<String, String> _artifactLibraryPaths;

  /// Roster-owned binary/text artifact families, excluding the fixed manifest
  /// output that the aggregate owner owns.
  Map<String, Uint8List> get outputFiles => _copyFileMap(_outputFiles);

  /// Outputs physically owned by the aggregate dynamic writer.
  Map<String, Uint8List> get aggregateOwnedOutputFiles => Map.unmodifiable({
        for (final entry in _outputFiles.entries)
          if (_aggregateOwnedOutputPaths.contains(entry.key))
            entry.key: Uint8List.fromList(entry.value),
      });

  /// The exact strict closure selected by [manifest].
  ///
  /// This is the safe handoff to the outputs builder, which owns dynamic
  /// publication. Screen text
  /// remains available through [outputFiles], but cannot accidentally enter a
  /// manifest closure because it is not a delivery artifact role.
  Map<String, Uint8List> get manifestFiles {
    final result = <String, Uint8List>{};
    for (final entry in manifest.publications) {
      for (final artifact in entry.artifacts) {
        final bytes = _outputFiles[artifact.path];
        if (bytes == null) {
          throw StateError(
            'Compiled output is missing manifest artifact ${artifact.path}.',
          );
        }
        result[artifact.path] = Uint8List.fromList(bytes);
      }
    }
    return Map.unmodifiable(result);
  }

  Map<String, Uint8List> get aggregateOwnedManifestFiles => Map.unmodifiable({
        for (final entry in manifestFiles.entries)
          if (_aggregateOwnedOutputPaths.contains(entry.key))
            entry.key: Uint8List.fromList(entry.value),
      });

  Map<String, Uint8List> get borrowedManifestFiles => Map.unmodifiable({
        for (final entry in manifestFiles.entries)
          if (!_aggregateOwnedOutputPaths.contains(entry.key))
            entry.key: Uint8List.fromList(entry.value),
      });

  /// The authored Dart library path that produced each output file this
  /// compiler wrote, sorted by logical path.
  ///
  /// Covers every path in [outputFiles] — manifest-closure artifacts and
  /// ancillary output (`.rfwtxt`, `.navplan.json`) alike — because
  /// [_putFile] records the owning library at the same choke point it writes
  /// the bytes, for every write, regardless of manifest-closure membership.
  /// Never re-inferred from filenames or from a sibling path's own
  /// attribution. Every output file must resolve to exactly one owning
  /// library, or this throws rather than defaulting silently.
  Map<String, String> get artifactLibraryPaths {
    final paths = _outputFiles.keys.toList()..sort();
    final result = <String, String>{};
    for (final path in paths) {
      final libraryPath = _artifactLibraryPaths[path];
      if (libraryPath == null) {
        throw StateError(
          'Output file $path has no authored-library attribution.',
        );
      }
      result[path] = libraryPath;
    }
    return Map.unmodifiable(result);
  }

  /// Roster-owned Dart parts, grouped so multiple declarations in one library
  /// become exactly one generated part.
  final Map<String, String> generatedParts;

  /// Final target-neutral Measurement drafts produced from exact final bytes.
  final List<MeasurementCompilerPublication> measurementPublications;
}

/// Result of a fail-closed package compilation attempt.
@immutable
final class PackageSurfaceCompilationResult {
  PackageSurfaceCompilationResult({
    required this.bundle,
    required List<Issue> issues,
  }) : issues = List.unmodifiable(issues);

  /// Non-null only when every output family and manifest closure validated.
  final PackageSurfaceCompilationBundle? bundle;

  /// Deterministic diagnostics suitable for the aggregate build owner.
  final List<Issue> issues;

  bool get isValid => bundle != null && issues.isEmpty;
}

/// Exact per-flow outputs for compatibility production entrypoints.
@immutable
final class CanonicalFlowArtifactCompilation {
  CanonicalFlowArtifactCompilation({
    required List<int> flowDocumentBytes,
    required this.generatedPart,
  }) : flowDocumentBytes = Uint8List.fromList(flowDocumentBytes);

  final Uint8List flowDocumentBytes;
  final String generatedPart;
}

/// Fail-closed result from [compileCanonicalFlowArtifact].
@immutable
final class CanonicalFlowArtifactCompilationResult {
  CanonicalFlowArtifactCompilationResult({
    required this.compilation,
    required List<Issue> issues,
  }) : issues = List.unmodifiable(issues);

  final CanonicalFlowArtifactCompilation? compilation;
  final List<Issue> issues;

  bool get isValid => compilation != null && issues.isEmpty;
}

/// Compiles one normalized flattened flow using exact, already hash-bound
/// screen artifacts. This is the per-source bridge to the same document and
/// reference emitters used by the aggregate package compiler.
CanonicalFlowArtifactCompilationResult compileCanonicalFlowArtifact({
  required NormalizedFlowSource flow,
  required RestageSourceDeclaration source,
  required Map<String, ScreenArtifact> screenArtifacts,
  Map<NormalizedFlowIdentity, List<int>> childFlowDocuments = const {},
  Set<NormalizedFlowIdentity>? declarationBoundChildFlowIdentities,
}) {
  final issues = <Issue>[];
  final graph = flow.graph;
  if (graph == null || !flow.isCanonical) {
    _addIssue(
      issues,
      code: IssueCode.unsupportedFlowRuntimeFeature,
      message: 'Canonical per-source compilation requires a normalized '
          'FlowDefinition graph.',
      location: source.span.location,
    );
    return CanonicalFlowArtifactCompilationResult(
      compilation: null,
      issues: issues,
    );
  }
  if (source.kind != RestageRosterSourceKind.flow ||
      source.declarationIdentity != flow.declarationIdentity ||
      source.effectiveId != flow.id ||
      source.surface != flow.surface ||
      source.version != flow.version ||
      source.minClient != flow.minClient ||
      source.delivery != flow.delivery) {
    _addIssue(
      issues,
      code: IssueCode.annotationEvaluationFailed,
      message: 'Normalized flow ${flow.id} does not match its roster-owned '
          'source facts.',
      location: source.span.location,
    );
    return CanonicalFlowArtifactCompilationResult(
      compilation: null,
      issues: issues,
    );
  }

  final expectedIds = graph.screens.keys.toSet();
  if (screenArtifacts.keys.toSet().difference(expectedIds).isNotEmpty ||
      expectedIds.difference(screenArtifacts.keys.toSet()).isNotEmpty) {
    _addIssue(
      issues,
      code: IssueCode.missingScreenDescriptor,
      message: 'Flow ${flow.id} requires the exact complete screen artifact '
          'set ${expectedIds.toList()..sort()}.',
      location: source.span.location,
    );
    return CanonicalFlowArtifactCompilationResult(
      compilation: null,
      issues: issues,
    );
  }

  try {
    final resolvedGraph = _withResolvedSubflowHashes(
      graph,
      childFlowDocuments,
      flow: flow,
      source: source,
      issues: issues,
      declarationBoundChildFlowIdentities: declarationBoundChildFlowIdentities,
    );
    if (resolvedGraph == null) {
      return CanonicalFlowArtifactCompilationResult(
        compilation: null,
        issues: issues,
      );
    }
    final effectiveGraph = _withEffectiveScreenFloor(
      resolvedGraph,
      screenArtifacts.values,
    );
    final document = effectiveGraph.toDocument(screenArtifacts);
    FlowDocumentValidation.checkValid(document);
    final documentBytes = FlowDocumentCodec.encodeCanonicalJson(document);
    final declarationName = flow.declaration.name;
    final library = flow.declaration.library;
    if (declarationName == null || declarationName.isEmpty || library == null) {
      throw StateError('Flow declaration has no stable analyzer identity.');
    }
    final flowStem = _pascalIdentifier(
      declarationName,
      fallback: 'SurfaceFlow',
    );
    final refName =
        generatedHandleName(declarationName, fallback: 'surfaceFlow');
    final resultName = '${flowStem}Result';
    final decoderName = '_decode${flowStem}Result';
    final seedName = '${flowStem}Seed';
    final claimedSymbols = <String, String>{};
    for (final symbol in <String>{
      refName,
      decoderName,
      if (flow.delivery == FlowDeliveryMode.typed) resultName,
      if (resolvedGraph.flowState.values.any((state) => state.hostSeedable))
        seedName,
      if (resolvedGraph.actions.isNotEmpty) '${flowStem}Actions',
    }) {
      _claimGeneratedSymbol(
        claimedSymbols,
        source: source,
        library: library,
        symbol: symbol,
        issues: issues,
      );
    }
    final sdkPrefix = _sdkPrefixFor(
      library,
      const {'SurfaceFlowRef', 'Surface', 'FlowDeliveryMode', 'FlowSeed'},
    );
    if (sdkPrefix == null) {
      _addIssue(
        issues,
        code: IssueCode.analyzerResolutionFailed,
        message: 'The flow library must import package:restage with a '
            'namespace that exposes the generated reference types.',
        location: source.span.location,
      );
    }
    final reference = sdkPrefix == null
        ? null
        : _emitFlowReference(
            refName: refName,
            resultName: resultName,
            decoderName: decoderName,
            seedName: seedName,
            graph: effectiveGraph,
            flow: flow,
            sdkPrefix: sdkPrefix,
            source: source,
            issues: issues,
          );
    if (issues.isNotEmpty || reference == null) {
      return CanonicalFlowArtifactCompilationResult(
        compilation: null,
        issues: issues,
      );
    }
    final partPath = _requiredOutputPathAny(
      source,
      roles: kGeneratedPartRoles,
      issues: issues,
    );
    if (partPath == null) {
      return CanonicalFlowArtifactCompilationResult(
        compilation: null,
        issues: issues,
      );
    }
    final generatedPart = formatGeneratedDart(
      '${_partOfHeader(partPath: partPath, libraryPath: source.libraryPath)}'
      '\n\n$reference\n',
    );
    return CanonicalFlowArtifactCompilationResult(
      compilation: CanonicalFlowArtifactCompilation(
        flowDocumentBytes: documentBytes,
        generatedPart: generatedPart,
      ),
      issues: const [],
    );
  } on Object catch (error) {
    _addIssue(
      issues,
      code: IssueCode.unsupportedFlowRuntimeFeature,
      message: 'Could not compile canonical flow ${flow.id}: $error',
      location: source.span.location,
    );
    return CanonicalFlowArtifactCompilationResult(
      compilation: null,
      issues: issues,
    );
  }
}

NormalizedFlowGraph _withEffectiveScreenFloor(
  NormalizedFlowGraph graph,
  Iterable<ScreenArtifact> artifacts,
) {
  var effectiveFloor = graph.minClient;
  for (final artifact in artifacts) {
    if (artifact.minClient > effectiveFloor) {
      effectiveFloor = artifact.minClient;
    }
  }
  return _withMinimumClientFloor(graph, effectiveFloor);
}

NormalizedFlowGraph _withMinimumClientFloor(
  NormalizedFlowGraph graph,
  int minimumClientFloor,
) {
  if (minimumClientFloor <= graph.minClient) return graph;
  return NormalizedFlowGraph(
    flow: graph.flow,
    version: graph.version,
    minClient: minimumClientFloor,
    delivery: graph.delivery,
    initial: graph.initial,
    states: graph.states,
    flowState: graph.flowState,
    outbound: graph.outbound,
    actions: graph.actions,
    screens: graph.screens,
    childFlows: graph.childFlows,
  );
}

NormalizedFlowGraph? _withResolvedSubflowHashes(
  NormalizedFlowGraph graph,
  Map<NormalizedFlowIdentity, List<int>> childFlowDocuments, {
  required NormalizedFlowSource flow,
  required RestageSourceDeclaration source,
  required List<Issue> issues,
  required Set<NormalizedFlowIdentity>? declarationBoundChildFlowIdentities,
}) {
  final states = <String, FlowState>{};
  for (final entry in graph.states.entries) {
    final state = entry.value;
    if (state is! SubFlowState) {
      states[entry.key] = state;
      continue;
    }
    final childIdentity = NormalizedFlowIdentity(
      surface: flow.surface,
      id: state.flow,
    );
    final childReference = graph.childFlows[childIdentity];
    if (childReference == null) {
      _addIssue(
        issues,
        code: IssueCode.missingScreenDescriptor,
        message: 'Flow ${flow.id} requires analyzer-resolved child flow '
            'identity ${childIdentity.surface.wireName}/${childIdentity.id}.',
        location: source.span.location,
      );
      continue;
    }
    final childBytes = childFlowDocuments[childIdentity];
    if (childBytes == null) {
      _addIssue(
        issues,
        code: IssueCode.missingScreenDescriptor,
        message: 'Flow ${flow.id} requires hash-bound child flow '
            '${state.flow}.',
        location: source.span.location,
      );
      continue;
    }
    final child = FlowDocumentCodec.decodeJson(utf8.decode(childBytes));
    final materializeEffectiveFloor =
        declarationBoundChildFlowIdentities?.contains(childIdentity) ??
            _referencesAnalyzerFlowDeclaration(flow, childReference);
    final childFloorMatches = materializeEffectiveFloor
        ? child.minClient >= childReference.minClient
        : child.minClient == childReference.minClient;
    if (child.flow != childReference.identity.id ||
        child.version != childReference.version ||
        !childFloorMatches ||
        state.version != childReference.version ||
        state.minClient != childReference.minClient) {
      _addIssue(
        issues,
        code: IssueCode.annotationEvaluationFailed,
        message: 'Child flow ${state.flow} does not match its declared '
            'version or minimum client.',
        location: source.span.location,
      );
      continue;
    }
    states[entry.key] = SubFlowState(
      flow: state.flow,
      version: state.version,
      schemaVersion: child.schemaVersion,
      minClient: materializeEffectiveFloor ? child.minClient : state.minClient,
      contentHash: FlowContentHash.compute(childBytes),
      input: state.input,
      onComplete: state.onComplete,
      defaultBranch: state.defaultBranch,
      subFlowUnavailable: state.subFlowUnavailable,
    );
  }
  if (issues.isNotEmpty) return null;
  return NormalizedFlowGraph(
    flow: graph.flow,
    version: graph.version,
    minClient: graph.minClient,
    delivery: graph.delivery,
    initial: graph.initial,
    states: states,
    flowState: graph.flowState,
    outbound: graph.outbound,
    actions: graph.actions,
    screens: graph.screens,
    childFlows: graph.childFlows,
  );
}

bool _referencesAnalyzerFlowDeclaration(
  NormalizedFlowSource parent,
  NormalizedChildFlowReference child,
) {
  final parentLibrary = parent.declaration.library;
  if (parentLibrary == null) return false;
  final declaration = _referencedElementByIdentity(
    parentLibrary,
    child.declarationIdentity,
  );
  if (declaration is ClassElement) return true;
  if (declaration is! TopLevelVariableElement) return false;
  return !_isSurfaceFlowReferenceType(declaration.type);
}

Element? _referencedElementByIdentity(
  LibraryElement parentLibrary,
  String identity,
) {
  final separator = identity.lastIndexOf('#');
  if (separator <= 0 || separator == identity.length - 1) return null;
  final libraryIdentity = identity.substring(0, separator);
  final name = identity.substring(separator + 1);

  Element? matchingElement(LibraryElement library) {
    for (final candidates in <Iterable<Element>>[
      library.classes,
      library.topLevelVariables,
    ]) {
      for (final candidate in candidates) {
        if (candidate.name == name &&
            candidate.library?.identifier == libraryIdentity) {
          return candidate;
        }
      }
    }
    return null;
  }

  if (parentLibrary.identifier == libraryIdentity) {
    return matchingElement(parentLibrary);
  }
  for (final import in parentLibrary.firstFragment.libraryImports) {
    final imported = import.importedLibrary;
    if (imported == null) continue;
    final direct = matchingElement(imported);
    if (direct != null) return direct;
    final prefix = import.prefix?.name;
    final lookup = prefix == null ? name : '$prefix.$name';
    final visible = import.namespace.get2(lookup);
    if (visible?.library?.identifier == libraryIdentity) return visible;
  }
  return null;
}

bool _isSurfaceFlowReferenceType(DartType type) {
  final alias = type.alias;
  if (alias != null &&
      alias.element.name == 'OnboardingFlowRef' &&
      libraryUriMatchesOrigin(
        alias.element.library.identifier,
        _restageSdkOrigin,
      )) {
    return true;
  }
  return type is InterfaceType &&
      type.element.name == 'SurfaceFlowRef' &&
      libraryUriMatchesOrigin(
        type.element.library.identifier,
        _restageSdkOrigin,
      );
}

/// Assembles canonical flow documents, generated references, and one strict
/// package publication manifest.
///
/// This function is side-effect free. In particular, a bad path, missing
/// sidecar, source mismatch, or invalid shared DTO returns no partial bundle;
/// callers must not write any family from an invalid result.
PackageSurfaceCompilationResult compilePackageSurfacePublications(
  PackageSurfaceCompilationInput input,
) {
  final issues = <Issue>[...input.roster.issues];
  if (issues.isNotEmpty) {
    return _invalidResult(issues);
  }

  final sourcesByIdentity = <String, RestageSourceDeclaration>{};
  for (final source in input.roster.declarations) {
    final existing = sourcesByIdentity[source.declarationIdentity];
    if (existing != null) {
      _addIssue(
        issues,
        code: IssueCode.duplicateId,
        message: 'The source roster contains duplicate declaration identity '
            '${source.declarationIdentity}.',
        location: source.span.location,
      );
      continue;
    }
    sourcesByIdentity[source.declarationIdentity] = source;
  }
  if (issues.isNotEmpty) return _invalidResult(issues);

  final outputFiles = <String, Uint8List>{};
  final aggregateOwnedOutputPaths = <String>{};
  final artifactLibraryPaths = <String, String>{};
  final artifactsByIdentity = <String, List<_ResolvedArtifact>>{};
  final paywallsByIdentity = <String, PaywallArtifactFacts>{};
  final partFragments = <String, _PartAccumulator>{};
  final pendingStandaloneParts = <_PendingStandalonePart>[];
  final pendingCompatibilityScreenParts = <_PendingCompatibilityScreenPart>[];
  final pendingFlowParts = <_PendingFlowPart>[];
  final claimedSymbols = <String, String>{};

  for (final suppliedRendered in input.renderedSources) {
    final identity = suppliedRendered.declarationIdentity;
    final source = sourcesByIdentity[identity];
    if (source == null) {
      _addIssue(
        issues,
        code: IssueCode.unresolvedIdentifier,
        message: 'Rendered source '
            '${suppliedRendered.declaration.name ?? '<unnamed>'} '
            'is absent from the canonical source roster.',
        location: identity,
      );
      continue;
    }

    if (source.kind != RestageRosterSourceKind.screen &&
        source.kind != RestageRosterSourceKind.paywall) {
      _addIssue(
        issues,
        code: IssueCode.annotationEvaluationFailed,
        message: 'Only screen or paywall roster declarations may supply '
            'rendered source bytes.',
        location: source.span.location,
      );
      continue;
    }
    final rendered = suppliedRendered;
    if (artifactsByIdentity.containsKey(identity)) {
      _addIssue(
        issues,
        code: IssueCode.duplicateId,
        message: 'More than one rendered artifact was supplied for $identity.',
        location: source.span.location,
      );
      continue;
    }
    if (!_isDeliveryArtifactPath(rendered.flowArtifactPath)) {
      _addIssue(
        issues,
        code: IssueCode.annotationEvaluationFailed,
        message: 'Flow artifact path "${rendered.flowArtifactPath}" must be '
            'a canonical relative path.',
        location: source.span.location,
      );
      continue;
    }

    final isPaywallAdapter = source.kind == RestageRosterSourceKind.paywall &&
        rendered.paywallFacts != null;
    final blobPaths = _outputPaths(
      source,
      roles: isPaywallAdapter
          ? const {'flow-screen-blob', 'flow-screen-binary'}
          : const {'screen-blob', 'binary'},
    );
    final sidecarPaths = _outputPaths(
      source,
      roles: isPaywallAdapter
          ? const {
              'flow-screen-capability-sidecar',
              'flow-screen-capability',
            }
          : const {'capability-sidecar', 'capability'},
    );
    final textPaths = isPaywallAdapter
        ? const <String>[]
        : _outputPaths(
            source,
            roles: const {'screen-text', 'text'},
          );
    if (blobPaths.length != sidecarPaths.length ||
        (blobPaths.isEmpty &&
            !(source.kind == RestageRosterSourceKind.screen &&
                source.surface == null))) {
      _addIssue(
        issues,
        code: IssueCode.missingScreenDescriptor,
        message: 'Rendered source ${source.effectiveId} requires matching '
            'roster-owned blob and capability-sidecar output claims.',
        location: source.span.location,
      );
      continue;
    }
    final text = rendered.rfwText;
    if (textPaths.isNotEmpty && text == null) {
      _addIssue(
        issues,
        code: IssueCode.missingScreenDescriptor,
        message: 'Rendered source ${source.effectiveId} is missing its '
            'roster-owned screen-text artifact.',
        location: source.span.location,
      );
      continue;
    }

    final sidecar = _decodeSidecar(
      rendered.capabilitySidecar,
      rendered.blob,
      source: source,
      issues: issues,
    );
    if (sidecar == null) continue;

    final artifacts = <_ResolvedArtifact>[];
    for (final blobPath in blobPaths) {
      final surface = _artifactSurfaceFromPath(
        blobPath,
        source: source,
        flowReferences: [
          for (final flow in input.flows)
            if (flow.graph case final graph?)
              for (final reference in graph.screens.values)
                if (reference.declarationIdentity == identity) reference,
        ],
        issues: issues,
      );
      final sidecarPath = _matchingSidecarPath(
        blobPath,
        sidecarPaths,
        source: source,
        issues: issues,
      );
      if (surface == null || sidecarPath == null) continue;
      _putOutputFile(
        outputFiles,
        path: blobPath,
        bytes: rendered.blob,
        source: source,
        issues: issues,
        libraryPaths: artifactLibraryPaths,
      );
      _putOutputFile(
        outputFiles,
        path: sidecarPath,
        bytes: rendered.capabilitySidecar,
        source: source,
        issues: issues,
        libraryPaths: artifactLibraryPaths,
      );
      if (source.isCanonical) {
        aggregateOwnedOutputPaths
          ..add(blobPath)
          ..add(sidecarPath);
      }
      artifacts.add(
        _ResolvedArtifact(
          rendered: rendered,
          source: source,
          surface: surface,
          blobPath: blobPath,
          sidecarPath: sidecarPath,
          sidecar: sidecar,
        ),
      );
    }
    if (text != null) {
      for (final textPath in textPaths) {
        _putOutputFile(
          outputFiles,
          path: textPath,
          bytes: text,
          source: source,
          issues: issues,
          libraryPaths: artifactLibraryPaths,
        );
        // Inspection text is carried for every frontend, not only the
        // canonical one. It is not a delivery artifact — it never enters a
        // manifest closure — so carrying it changes no producer and no
        // delivered byte; it only means a deprecated library's bundle holds
        // its rfw text like every other library's does.
        aggregateOwnedOutputPaths.add(textPath);
      }
    }
    artifactsByIdentity[identity] = List.unmodifiable(artifacts);
    if (rendered.paywallFacts case final facts?) {
      paywallsByIdentity[identity] = facts;
      final paywallText = rendered.rfwText;
      if (paywallText != null) {
        for (final path in _outputPaths(
          source,
          roles: const {'screen-text', 'text'},
        )) {
          _putOutputFile(
            outputFiles,
            path: path,
            bytes: paywallText,
            source: source,
            issues: issues,
            libraryPaths: artifactLibraryPaths,
          );
          if (source.isCanonical) aggregateOwnedOutputPaths.add(path);
        }
      }
      final navigationPlan = rendered.navigationPlan;
      if (navigationPlan != null) {
        for (final path in _outputPaths(
          source,
          roles: const {'navigation-plan'},
        )) {
          _putOutputFile(
            outputFiles,
            path: path,
            bytes: navigationPlan,
            source: source,
            issues: issues,
            libraryPaths: artifactLibraryPaths,
          );
          if (source.isCanonical) aggregateOwnedOutputPaths.add(path);
        }
      }
    }

    // Only category-neutral screens receive a generated flow reference. A
    // categorized screen receives the C1 SurfaceScreenRef when it is exposed
    // as an independently published source.
    if (source.kind == RestageRosterSourceKind.screen &&
        source.surface == null) {
      final partPath = _requiredOutputPath(
        source,
        role: 'screen-descriptor',
        issues: issues,
      );
      if (partPath == null) continue;
      final className = rendered.declaration.name;
      if (className == null || className.isEmpty) {
        _addIssue(
          issues,
          code: IssueCode.generatedSymbolCollision,
          message: 'A generated neutral screen reference requires a named '
              'screen class.',
          location: source.span.location,
        );
        continue;
      }
      final screenStem = _pascalIdentifier(
        className,
        fallback: 'SurfaceScreen',
      );
      final descriptor = '${screenStem}Descriptor';
      final refName = generatedHandleName(className, fallback: 'surfaceScreen');
      for (final symbol in [refName, descriptor]) {
        _claimGeneratedSymbol(
          claimedSymbols,
          source: source,
          library: rendered.declaration.library,
          symbol: symbol,
          issues: issues,
        );
      }
      _addPartFragment(
        partFragments,
        path: partPath,
        source: source,
        fragment: _emitNeutralReference(
          refName: refName,
          descriptor: descriptor,
          id: source.effectiveId,
          version: source.version,
          capabilities: sidecar.manifest,
          sdkPrefix: _sdkPrefixFor(
            rendered.declaration.library,
            const {
              'NeutralFlowScreenRef',
              'CapabilityManifest',
              'LibraryRequirement',
            },
          ),
          issues: issues,
        ),
      );
    }
  }

  final manifestInputs = <SurfacePublicationAssemblyInput>[];

  for (final entry in paywallsByIdentity.entries) {
    if (entry.value.isEmbeddedOnly) {
      final source = sourcesByIdentity[entry.key]!;
      if (!_isReferencedByAnotherPaywallFlow(
        entry.key,
        entry.value,
        paywallsByIdentity,
      )) {
        _addIssue(
          issues,
          code: IssueCode.missingScreenDescriptor,
          message: 'Adapter-only paywall ${source.effectiveId} is not '
              'referenced by a generated paywall flow closure.',
          location: source.span.location,
        );
      }
      // A pushed paywall with in-flow back navigation contributes its adapter
      // only. Its owning entry flow closure publishes those exact bytes;
      // synthesizing a standalone publication would invent a payload the
      // source deliberately suppressed.
      continue;
    }
    final source = sourcesByIdentity[entry.key]!;
    final publication = _assemblePaywallPublication(
      source: source,
      facts: entry.value,
      outputFiles: outputFiles,
      aggregateOwnedOutputPaths: aggregateOwnedOutputPaths,
      issues: issues,
      artifactLibraryPaths: artifactLibraryPaths,
    );
    if (publication != null) manifestInputs.add(publication);
  }

  final contractIdentities = <String>{};
  for (final contract in input.standaloneScreens) {
    final identity = _classIdentity(contract.screen);
    if (!contractIdentities.add(identity)) {
      _addIssue(
        issues,
        code: IssueCode.duplicateId,
        message: 'More than one standalone screen contract was supplied for '
            '$identity.',
        location: contract.input.location,
      );
      continue;
    }
    final artifact = _artifactForSurface(
      artifactsByIdentity[identity],
      contract.surface,
    );
    final source = sourcesByIdentity[identity];
    if (source == null || artifact == null) {
      _addIssue(
        issues,
        code: IssueCode.missingScreenDescriptor,
        message: 'Standalone screen ${contract.slug} requires one rendered '
            'source artifact admitted by the canonical roster.',
        location: contract.input.location,
      );
      continue;
    }
    if (source.kind != RestageRosterSourceKind.screen ||
        source.surface == null ||
        source.surface != contract.surface ||
        source.effectiveId != contract.slug ||
        source.version != contract.contractVersion) {
      _addIssue(
        issues,
        code: IssueCode.annotationEvaluationFailed,
        message: 'Standalone screen ${contract.slug} does not match its '
            'roster-owned source identity, category, or contract version.',
        location: source.span.location,
      );
      continue;
    }

    final screenName = contract.screen.name;
    if (screenName == null || screenName.isEmpty) {
      _addIssue(
        issues,
        code: IssueCode.generatedSymbolCollision,
        message: 'A generated standalone screen reference requires a named '
            'screen class.',
        location: source.span.location,
      );
      continue;
    }
    _claimGeneratedSymbol(
      claimedSymbols,
      source: source,
      library: contract.screen.library,
      symbol: generatedHandleName(screenName, fallback: 'surfaceScreen'),
      issues: issues,
    );

    final publication = _assembleStandalonePublication(
      artifact: artifact,
      contract: contract,
      issues: issues,
    );
    if (publication != null) manifestInputs.add(publication);

    final partPath = _requiredOutputPathAny(
      source,
      roles: kGeneratedPartRoles,
      issues: issues,
    );
    if (partPath != null) {
      // A categorized screen is standalone: its handle is the typed
      // `<name>Ref`. It carries no neutral in-flow reference, because a
      // flow step is a neutral `@Screen()` and the two are exclusive.
      pendingStandaloneParts.add(
        _PendingStandalonePart(
          partPath: partPath,
          source: source,
          contract: contract,
        ),
      );
    }
  }

  for (final contract in input.legacyStandaloneScreens) {
    final identity = _classIdentity(contract.screen);
    if (!contractIdentities.add(identity)) {
      _addIssue(
        issues,
        code: IssueCode.duplicateId,
        message: 'More than one standalone screen contract was supplied for '
            '$identity.',
        location: contract.input.location,
      );
      continue;
    }
    final artifact = _artifactForSurface(
      artifactsByIdentity[identity],
      contract.surface,
    );
    final source = sourcesByIdentity[identity];
    if (source == null || artifact == null) {
      _addIssue(
        issues,
        code: IssueCode.missingScreenDescriptor,
        message: 'Legacy standalone screen ${contract.slug} requires one '
            'rendered source artifact admitted by the package roster.',
        location: contract.input.location,
      );
      continue;
    }
    if (source.kind != RestageRosterSourceKind.screen ||
        source.isCanonical ||
        source.surface != contract.surface ||
        source.effectiveId != contract.slug ||
        source.version != contract.contractVersion) {
      _addIssue(
        issues,
        code: IssueCode.annotationEvaluationFailed,
        message: 'Legacy standalone screen ${contract.slug} does not match '
            'its roster-owned identity, category, or contract version.',
        location: source.span.location,
      );
      continue;
    }
    final publication = _assembleLegacyStandalonePublication(
      artifact: artifact,
      contract: contract,
      issues: issues,
    );
    if (publication != null) manifestInputs.add(publication);

    // The deprecated frontend's screens are referenced from flows by their
    // generated descriptor. It is emitted here because a library's part has
    // one owner; the emitter itself is the same one the canonical path uses
    // for its compatibility descriptor, so both frontends produce the same
    // reference shape. (This descriptor originated in the per-surface screen
    // builder, which no longer writes generated Dart.)
    final screenName = contract.screen.name;
    if (screenName == null || screenName.isEmpty) continue;
    final descriptor =
        '${_pascalIdentifier(screenName, fallback: 'SurfaceScreen')}Descriptor';
    _claimGeneratedSymbol(
      claimedSymbols,
      source: source,
      library: contract.screen.library,
      symbol: descriptor,
      issues: issues,
    );
    final partPath = _requiredOutputPathAny(
      source,
      roles: kGeneratedPartRoles,
      issues: issues,
    );
    if (partPath == null) continue;
    pendingCompatibilityScreenParts.add(
      _PendingCompatibilityScreenPart(
        partPath: partPath,
        source: source,
        descriptor: descriptor,
        id: source.effectiveId,
        artifactPath: artifact.rendered.flowArtifactPath,
        version: source.version,
        minClient: source.minClient,
        sdkPrefix: _sdkPrefixFor(
          contract.screen.library,
          const {'NeutralFlowScreenRef'},
        ),
      ),
    );
  }

  final precompiledFlowsByIdentity = <String, CompiledFlowArtifact>{};
  for (final precompiled in input.precompiledFlows) {
    final previous =
        precompiledFlowsByIdentity[precompiled.declarationIdentity];
    if (previous != null) {
      _addIssue(
        issues,
        code: IssueCode.duplicateId,
        message: 'More than one precompiled flow artifact was supplied for '
            '${precompiled.declarationIdentity}.',
        location: precompiled.declarationIdentity,
      );
      continue;
    }
    precompiledFlowsByIdentity[precompiled.declarationIdentity] = precompiled;
  }
  final precompiledFlowDocumentsByIdentity =
      _indexPrecompiledClassFlowDocuments(
    input.flows,
    precompiledFlowsByIdentity,
    issues: issues,
  );
  if (issues.isNotEmpty) return _invalidResult(issues);

  final compiledFlowDocuments = _compileCanonicalFlowDocuments(
    input.flows,
    sourcesByIdentity: sourcesByIdentity,
    artifactsByIdentity: artifactsByIdentity,
    precompiledFlowDocumentsByIdentity: precompiledFlowDocumentsByIdentity,
    issues: issues,
  );
  if (issues.isNotEmpty) return _invalidResult(issues);

  final seenFlowIdentities = <String>{};
  for (final flow in input.flows) {
    final source = sourcesByIdentity[flow.declarationIdentity];
    if (!seenFlowIdentities.add(flow.declarationIdentity)) {
      _addIssue(
        issues,
        code: IssueCode.duplicateId,
        message: 'More than one normalized flow was supplied for '
            '${flow.declarationIdentity}.',
        location: flow.declarationIdentity,
      );
      continue;
    }
    if (source == null) {
      _addIssue(
        issues,
        code: IssueCode.unresolvedIdentifier,
        message: 'Normalized flow ${flow.id} is absent from the canonical '
            'source roster.',
        location: flow.declarationIdentity,
      );
      continue;
    }
    if (source.kind != RestageRosterSourceKind.flow ||
        source.surface != flow.surface ||
        source.effectiveId != flow.id ||
        source.version != flow.version ||
        source.minClient != flow.minClient ||
        source.delivery != flow.delivery) {
      _addIssue(
        issues,
        code: IssueCode.annotationEvaluationFailed,
        message: 'Normalized flow ${flow.id} does not match its roster-owned '
            'identity, surface, version, minimum client, or delivery mode.',
        location: source.span.location,
      );
      continue;
    }
    final graph = flow.graph;
    final flowDocumentPath = _requiredOutputPathAny(
      source,
      roles: const {'flow-document', 'flow'},
      issues: issues,
    );
    if (flowDocumentPath == null) continue;

    if (graph == null) {
      final precompiled = precompiledFlowsByIdentity[flow.declarationIdentity];
      if (precompiled == null) {
        _addIssue(
          issues,
          code: IssueCode.unsupportedFlowRuntimeFeature,
          message: 'Class-shaped flow ${flow.id} was admitted by the source '
              'roster but has no exact precompiled artifact.',
          location: source.span.location,
        );
        continue;
      }
      final assembly = _assemblePrecompiledFlowPublication(
        flow: flow,
        source: source,
        artifactsByIdentity: artifactsByIdentity,
        flowDocumentPath: flowDocumentPath,
        flowDocumentBytes: precompiled.flowDocumentBytes,
        issues: issues,
      );
      if (assembly == null) continue;
      manifestInputs.add(assembly.manifestInput);
      _putOutputFile(
        outputFiles,
        path: flowDocumentPath,
        bytes: assembly.flowDocumentBytes,
        source: source,
        issues: issues,
        libraryPaths: artifactLibraryPaths,
      );
      if (source.isCanonical) aggregateOwnedOutputPaths.add(flowDocumentPath);
      // The generated part is library-owned for canonical and deprecated
      // sources alike; only artifact ownership differs between them.
      final generatedPart = precompiled.generatedPart;
      if (generatedPart != null) {
        final partPath = _requiredOutputPathAny(
          source,
          roles: kGeneratedPartRoles,
          issues: issues,
        );
        if (partPath != null) {
          _addPartFragment(
            partFragments,
            path: partPath,
            source: source,
            fragment: _withoutPartHeader(generatedPart),
          );
        }
      }
      continue;
    }

    final flowPartPath = _requiredOutputPathAny(
      source,
      roles: kGeneratedPartRoles,
      issues: issues,
    );
    if (flowPartPath == null) continue;

    final assembly = _assembleFlowPublication(
      flow: flow,
      graph: graph,
      source: source,
      artifactsByIdentity: artifactsByIdentity,
      flowDocumentPath: flowDocumentPath,
      flowDocumentBytes: compiledFlowDocuments[flow.identity],
      issues: issues,
    );
    if (assembly == null) continue;
    manifestInputs.add(assembly.manifestInput);
    _putOutputFile(
      outputFiles,
      path: flowDocumentPath,
      bytes: assembly.flowDocumentBytes,
      source: source,
      issues: issues,
      libraryPaths: artifactLibraryPaths,
    );
    if (source.isCanonical) aggregateOwnedOutputPaths.add(flowDocumentPath);

    final emittedDocument = FlowDocumentCodec.decodeJson(
      utf8.decode(assembly.flowDocumentBytes),
    );
    final emittedGraph = _withMinimumClientFloor(
      graph,
      emittedDocument.minClient,
    );

    final sourceName = flow.declaration.name;
    if (sourceName == null || sourceName.isEmpty) {
      _addIssue(
        issues,
        code: IssueCode.generatedSymbolCollision,
        message: 'A generated flow reference requires a named declaration.',
        location: source.span.location,
      );
      continue;
    }
    final library = flow.declaration.library;
    if (library == null) {
      _addIssue(
        issues,
        code: IssueCode.analyzerResolutionFailed,
        message: 'The flow declaration no longer has an owning analyzer '
            'library.',
        location: source.span.location,
      );
      continue;
    }
    final flowStem = _pascalIdentifier(sourceName, fallback: 'SurfaceFlow');
    final refName = generatedHandleName(sourceName, fallback: 'surfaceFlow');
    final resultName = '${flowStem}Result';
    final decoderName = '_decode${flowStem}Result';
    final seedName = '${flowStem}Seed';
    for (final symbol in <String>{
      refName,
      decoderName,
      if (flow.delivery == FlowDeliveryMode.typed) resultName,
      if (graph.flowState.values.any((state) => state.hostSeedable)) seedName,
      if (graph.actions.isNotEmpty) '${flowStem}Actions',
    }) {
      _claimGeneratedSymbol(
        claimedSymbols,
        source: source,
        library: library,
        symbol: symbol,
        issues: issues,
      );
    }
    final sdkPrefix = _sdkPrefixFor(
      library,
      const {
        'SurfaceFlowRef',
        'Surface',
        'FlowDeliveryMode',
        'FlowSeed',
      },
    );
    if (sdkPrefix == null) {
      _addIssue(
        issues,
        code: IssueCode.analyzerResolutionFailed,
        message: 'The flow library must import package:restage with a '
            'namespace that exposes the generated reference types.',
        location: source.span.location,
      );
      continue;
    }
    pendingFlowParts.add(
      _PendingFlowPart(
        partPath: flowPartPath,
        source: source,
        refName: refName,
        resultName: resultName,
        decoderName: decoderName,
        seedName: seedName,
        graph: emittedGraph,
        flow: flow,
        sdkPrefix: sdkPrefix,
        measurementPublicationKey: _measurementSelectorForAssembly(
          assembly.manifestInput,
        ).key,
      ),
    );
  }

  for (final source in sourcesByIdentity.values) {
    switch (source.kind) {
      case RestageRosterSourceKind.screen:
        if (!artifactsByIdentity.containsKey(source.declarationIdentity)) {
          _addIssue(
            issues,
            code: IssueCode.missingScreenDescriptor,
            message: 'Admitted screen ${source.effectiveId} has no complete '
                'compiled artifact family.',
            location: source.span.location,
          );
        } else if (source.surface != null &&
            !contractIdentities.contains(source.declarationIdentity)) {
          _addIssue(
            issues,
            code: IssueCode.missingScreenDescriptor,
            message: 'Standalone screen ${source.effectiveId} has no '
                'analyzer-resolved typed event contract.',
            location: source.span.location,
          );
        }
      case RestageRosterSourceKind.paywall:
        if (!paywallsByIdentity.containsKey(source.declarationIdentity)) {
          _addIssue(
            issues,
            code: IssueCode.missingScreenDescriptor,
            message: 'Admitted paywall ${source.effectiveId} has no complete '
                'specialized artifact family.',
            location: source.span.location,
          );
        }
      case RestageRosterSourceKind.flow:
        if (!seenFlowIdentities.contains(source.declarationIdentity)) {
          _addIssue(
            issues,
            code: IssueCode.unsupportedFlowRuntimeFeature,
            message: 'Admitted flow ${source.effectiveId} was not compiled '
                'into the aggregate publication contract.',
            location: source.span.location,
          );
        }
    }
  }

  if (issues.isNotEmpty) return _invalidResult(issues);

  final measurementPublications = <MeasurementCompilerPublication>[];
  if (input.measurementRoutePlansByPublicationKey.isNotEmpty) {
    try {
      final finalized = _finalizeMeasurementAssemblies(
        inputs: manifestInputs,
        routePlansByPublicationKey: input.measurementRoutePlansByPublicationKey,
        sourcesByOutputPath: {
          for (final source in sourcesByIdentity.values)
            for (final output in source.outputs) output.path: source,
        },
      );
      final unplannedPaths = <String>{
        for (final assembly in manifestInputs)
          if (!input.measurementRoutePlansByPublicationKey.containsKey(
            _measurementSelectorForAssembly(assembly).key,
          ))
            for (final artifact in assembly.artifacts) artifact.path,
      };
      final replacedTemplatePaths = <String>{
        for (final assembly in manifestInputs)
          if (input.measurementRoutePlansByPublicationKey.containsKey(
            _measurementSelectorForAssembly(assembly).key,
          ))
            for (final artifact in assembly.artifacts) artifact.path,
      };
      for (final path in replacedTemplatePaths.difference(unplannedPaths)) {
        outputFiles.remove(path);
        aggregateOwnedOutputPaths.remove(path);
        artifactLibraryPaths.remove(path);
      }
      for (final artifact in finalized.artifacts) {
        _putOutputFile(
          outputFiles,
          path: artifact.path,
          bytes: artifact.bytes,
          source: artifact.source,
          issues: issues,
          libraryPaths: artifactLibraryPaths,
        );
        if (artifact.source.isCanonical) {
          aggregateOwnedOutputPaths.add(artifact.path);
        }
      }
      manifestInputs
        ..clear()
        ..addAll(finalized.inputs);
      measurementPublications.addAll(finalized.publications);
      _stripMeasurementMarkersFromInspectionOutputs(outputFiles);
    } on Object catch (error) {
      _addIssue(
        issues,
        code: IssueCode.annotationEvaluationFailed,
        message: 'Measurement publication finalization failed: $error',
        location: 'the package Measurement publication closure',
      );
    }
  }
  if (issues.isNotEmpty) return _invalidResult(issues);

  final finalizedDraftDigestsByPublicationKey = <String, String>{
    for (final publication in measurementPublications)
      publication.selector.key: publication.draft.canonicalDigest.hex,
  };
  for (final carrier
      in input.generatedSourceCarrierDraftDigestsByPublicationKey.entries) {
    final finalized = finalizedDraftDigestsByPublicationKey[carrier.key];
    if (finalized == carrier.value) continue;
    _addIssue(
      issues,
      code: IssueCode.annotationEvaluationFailed,
      message: 'Generated Measurement source carrier for ${carrier.key} does '
          'not match the exact final publication draft.',
      location: 'the package Measurement publication closure',
    );
  }
  if (issues.isNotEmpty) return _invalidResult(issues);

  final manifest = _buildManifest(
    manifestInputs,
    issues: issues,
  );
  if (manifest == null || issues.isNotEmpty) return _invalidResult(issues);

  final carrierDraftDigestsByPublicationKey =
      input.generatedSourceCarrierDraftDigestsByPublicationKey;
  for (final pending in pendingStandaloneParts) {
    final contract = _refreshStandaloneContractBundleMetadata(
      pending.contract,
      manifestInputs: manifestInputs,
      issues: issues,
    );
    if (contract == null) continue;
    final selector = MeasurementPublicationSelectorV1(
      surface: contract.surface,
      slug: contract.slug,
      sourceKind: SurfaceSourceKind.screen,
      contractVersion: contract.contractVersion,
    );
    _addPartFragment(
      partFragments,
      path: pending.partPath,
      source: pending.source,
      fragment: '${_withoutPartHeader(
        contract.emitReferenceDart(
          measurementPublicationDraftDigest:
              carrierDraftDigestsByPublicationKey[selector.key],
        ),
      )}\n\n',
    );
  }
  for (final pending in pendingCompatibilityScreenParts) {
    final surface = pending.source.surface;
    final measurementPublicationDraftDigest = surface == null
        ? null
        : carrierDraftDigestsByPublicationKey[MeasurementPublicationSelectorV1(
            surface: surface,
            slug: pending.source.effectiveId,
            sourceKind: SurfaceSourceKind.screen,
            contractVersion: pending.source.version,
          ).key];
    final reference = _emitCompatibilityScreenDescriptor(
      descriptor: pending.descriptor,
      id: pending.id,
      artifactPath: pending.artifactPath,
      version: pending.version,
      minClient: pending.minClient,
      sdkPrefix: pending.sdkPrefix,
      source: pending.source,
      measurementPublicationDraftDigest: measurementPublicationDraftDigest,
      issues: issues,
    );
    if (reference == null) continue;
    _addPartFragment(
      partFragments,
      path: pending.partPath,
      source: pending.source,
      fragment: reference,
    );
  }
  for (final pending in pendingFlowParts) {
    final reference = _emitFlowReference(
      refName: pending.refName,
      resultName: pending.resultName,
      decoderName: pending.decoderName,
      seedName: pending.seedName,
      graph: pending.graph,
      flow: pending.flow,
      sdkPrefix: pending.sdkPrefix,
      source: pending.source,
      measurementPublicationDraftDigest: carrierDraftDigestsByPublicationKey[
          pending.measurementPublicationKey],
      issues: issues,
    );
    if (reference == null) continue;
    _addPartFragment(
      partFragments,
      path: pending.partPath,
      source: pending.source,
      fragment: reference,
    );
  }
  if (issues.isNotEmpty) return _invalidResult(issues);

  final generatedParts = <String, String>{};
  for (final entry in partFragments.entries) {
    final source = _formatPart(entry.value, issues: issues);
    if (source != null) generatedParts[entry.key] = source;
  }
  if (issues.isNotEmpty) return _invalidResult(issues);

  return PackageSurfaceCompilationResult(
    bundle: PackageSurfaceCompilationBundle(
      manifest: manifest.manifest,
      outputFiles: outputFiles,
      generatedParts: generatedParts,
      aggregateOwnedOutputPaths: aggregateOwnedOutputPaths,
      artifactLibraryPaths: artifactLibraryPaths,
      measurementPublications: measurementPublications,
    ),
    issues: const [],
  );
}

bool _isReferencedByAnotherPaywallFlow(
  String identity,
  PaywallArtifactFacts embedded,
  Map<String, PaywallArtifactFacts> paywallsByIdentity,
) {
  for (final owner in paywallsByIdentity.entries) {
    if (owner.key == identity || !owner.value.hasFlow) continue;
    final screen = owner.value.flowScreens[embedded.adapter.id];
    if (screen != null &&
        screen.blob.contentHash == embedded.adapter.blob.contentHash &&
        screen.capabilitySidecar.contentHash ==
            embedded.adapter.capabilitySidecar.contentHash) {
      return true;
    }
  }
  return false;
}

SurfacePublicationAssemblyInput? _assemblePaywallPublication({
  required RestageSourceDeclaration source,
  required PaywallArtifactFacts facts,
  required Map<String, Uint8List> outputFiles,
  required Set<String> aggregateOwnedOutputPaths,
  required List<Issue> issues,
  required Map<String, String> artifactLibraryPaths,
}) {
  try {
    final files = facts.filesByPath;
    if (facts.hasFlow) {
      // A navigation paywall remains independently renderable through its
      // specialized blob even though the publication manifest selects the
      // flow payload. Preserve that roster-owned sibling family as generated
      // output without adding it to the strict flow artifact closure.
      for (final declaration in facts.standaloneArtifacts) {
        final bytes = files[declaration.path];
        if (bytes == null) {
          throw FormatException(
            'Paywall artifact ${declaration.path} has no exact bytes.',
          );
        }
        _putOutputFile(
          outputFiles,
          path: declaration.path,
          bytes: bytes,
          source: source,
          issues: issues,
          libraryPaths: artifactLibraryPaths,
        );
        if (source.isCanonical) {
          aggregateOwnedOutputPaths.add(declaration.path);
        }
      }
    }
    final declarations =
        facts.hasFlow ? facts.flowArtifacts : facts.standaloneArtifacts;
    if (declarations.isEmpty) {
      throw const FormatException(
        'Paywall adapter did not expose a publishable artifact closure.',
      );
    }
    final inputs = <SurfacePublicationArtifactInput>[];
    for (final declaration in declarations) {
      final bytes = files[declaration.path];
      if (bytes == null) {
        throw FormatException(
          'Paywall artifact ${declaration.path} has no exact bytes.',
        );
      }
      _putOutputFile(
        outputFiles,
        path: declaration.path,
        bytes: bytes,
        source: source,
        issues: issues,
        libraryPaths: artifactLibraryPaths,
      );
      if (source.isCanonical) {
        aggregateOwnedOutputPaths.add(declaration.path);
      }
      inputs.add(
        SurfacePublicationArtifactInput(
          path: declaration.path,
          role: declaration.role,
          id: declaration.id,
          bytes: bytes,
        ),
      );
    }
    return SurfacePublicationAssemblyInput(
      surface: Surface.paywall,
      slug: facts.slug,
      sourceKind: SurfaceSourceKind.paywall,
      payloadKind:
          facts.hasFlow ? SurfacePayloadKind.flow : SurfacePayloadKind.blob,
      artifacts: inputs,
      sources: _authoringSources([source]),
      flowFacts: facts.hasFlow
          ? SurfacePublicationFlowFacts(
              deliveryMode: facts.navigationFlow!.deliveryMode,
            )
          : null,
    );
  } on Object catch (error) {
    _addIssue(
      issues,
      code: IssueCode.annotationEvaluationFailed,
      message: 'Could not assemble paywall ${source.effectiveId}: $error',
      location: source.span.location,
    );
    return null;
  }
}

SurfacePublicationAssemblyInput? _assembleStandalonePublication({
  required _ResolvedArtifact artifact,
  required ResolvedStandaloneScreenContract contract,
  required List<Issue> issues,
}) {
  final source = artifact.source;
  if (artifact.sidecar.manifest != contract.capabilities) {
    _addIssue(
      issues,
      code: IssueCode.annotationEvaluationFailed,
      message: 'Standalone screen ${contract.slug} capability sidecar does '
          'not match its resolved generated contract.',
      location: source.span.location,
    );
    return null;
  }
  try {
    return SurfacePublicationAssemblyInput(
      surface: contract.surface,
      slug: contract.slug,
      sourceKind: SurfaceSourceKind.screen,
      payloadKind: SurfacePayloadKind.blob,
      artifacts: _screenClosureInputs(artifact),
      sources: _authoringSources([source]),
      screenContractFacts: SurfacePublicationScreenContractFacts(
        contractVersion: contract.contractVersion,
        capabilities: contract.capabilities,
        eventContract: contract.eventSchema,
      ),
    );
  } on Object catch (error) {
    _addIssue(
      issues,
      code: IssueCode.annotationEvaluationFailed,
      message: 'Could not assemble standalone screen ${contract.slug}: $error',
      location: source.span.location,
    );
    return null;
  }
}

SurfacePublicationAssemblyInput? _assembleLegacyStandalonePublication({
  required _ResolvedArtifact artifact,
  required LegacyStandaloneScreenContract contract,
  required List<Issue> issues,
}) {
  final source = artifact.source;
  if (artifact.sidecar.manifest != contract.capabilities) {
    _addIssue(
      issues,
      code: IssueCode.annotationEvaluationFailed,
      message: 'Legacy standalone screen ${contract.slug} capability '
          'sidecar does not match its resolved publication contract.',
      location: source.span.location,
    );
    return null;
  }
  try {
    return SurfacePublicationAssemblyInput(
      surface: contract.surface,
      slug: contract.slug,
      sourceKind: SurfaceSourceKind.screen,
      payloadKind: SurfacePayloadKind.blob,
      artifacts: _screenClosureInputs(artifact),
      sources: _authoringSources([source]),
      screenContractFacts: SurfacePublicationScreenContractFacts(
        contractVersion: contract.contractVersion,
        capabilities: contract.capabilities,
        eventContract: contract.eventSchema,
      ),
    );
  } on Object catch (error) {
    _addIssue(
      issues,
      code: IssueCode.annotationEvaluationFailed,
      message: 'Could not assemble legacy standalone screen '
          '${contract.slug}: $error',
      location: source.span.location,
    );
    return null;
  }
}

/// The package-relative authoring files behind one publication.
///
/// Both the declaration's own file and its owning library are recorded: they
/// differ when a surface is declared in a part, and a developer naming a file
/// may reasonably name either one. The assembler sorts and de-duplicates.
///
/// A roster path that is not package-relative is dropped rather than passed
/// on. The roster resolves a path best-effort and can fall back to a
/// `package:` URI or an absolute path for a source it cannot place; those are
/// fine in a diagnostic span but the manifest cannot represent them, and
/// letting one through would fail the whole package's manifest over a single
/// unplaceable declaration. Dropping it costs that one file as a publish
/// selector and nothing else.
///
/// The filter delegates to the shared predicate the manifest validates with,
/// so the producer's rule and the constructor's gate cannot drift apart.
List<String> _authoringSources(
  Iterable<RestageSourceDeclaration> declarations,
) =>
    <String>[
      for (final declaration in declarations) ...<String>[
        declaration.sourcePath,
        declaration.libraryPath,
      ],
    ].where(_isRepresentableDartPath).toList();

bool _isRepresentableDartPath(String value) =>
    value.endsWith('.dart') &&
    value.trim() == value &&
    !value.contains('\u0000') &&
    isPackageRelativePath(value);

Map<NormalizedFlowIdentity, Uint8List> _compileCanonicalFlowDocuments(
  Iterable<NormalizedFlowSource> flows, {
  required Map<String, RestageSourceDeclaration> sourcesByIdentity,
  required Map<String, List<_ResolvedArtifact>> artifactsByIdentity,
  required Map<NormalizedFlowIdentity, Uint8List>
      precompiledFlowDocumentsByIdentity,
  required List<Issue> issues,
}) {
  final normalizedFlows = flows.toList(growable: false);
  final byIdentity = <NormalizedFlowIdentity, NormalizedFlowSource>{};
  for (final flow in normalizedFlows.where(
    (candidate) => candidate.graph != null,
  )) {
    if (precompiledFlowDocumentsByIdentity.containsKey(flow.identity)) {
      _addIssue(
        issues,
        code: IssueCode.duplicateId,
        message: 'Flow identity ${flow.surface.wireName}/${flow.id} has both '
            'a normalized graph and a precompiled class-flow document.',
        location: flow.declarationIdentity,
      );
      continue;
    }
    final previous = byIdentity[flow.identity];
    if (previous != null &&
        previous.declarationIdentity != flow.declarationIdentity) {
      _addIssue(
        issues,
        code: IssueCode.duplicateId,
        message: 'Multiple canonical flows share identity '
            '${flow.surface.wireName}/${flow.id}.',
        location: flow.declarationIdentity,
      );
      continue;
    }
    byIdentity[flow.identity] = flow;
  }
  final compiled = <NormalizedFlowIdentity, Uint8List>{};
  final visiting = <NormalizedFlowIdentity>{};

  Uint8List? compile(NormalizedFlowSource flow) {
    final existing = compiled[flow.identity];
    if (existing != null) return existing;
    if (!visiting.add(flow.identity)) {
      _addIssue(
        issues,
        code: IssueCode.unsupportedFlowRuntimeFeature,
        message: 'Subflow cycle detected at ${flow.id}.',
        location: flow.declarationIdentity,
      );
      return null;
    }
    final source = sourcesByIdentity[flow.declarationIdentity];
    if (source == null) {
      visiting.remove(flow.identity);
      return null;
    }
    final childDocuments = <NormalizedFlowIdentity, List<int>>{};
    final declarationBoundChildFlowIdentities = <NormalizedFlowIdentity>{};
    for (final reference in flow.graph!.childFlows.values) {
      final child = byIdentity[reference.identity];
      final precompiledChild =
          precompiledFlowDocumentsByIdentity[reference.identity];
      if (child != null && precompiledChild != null) {
        _addIssue(
          issues,
          code: IssueCode.duplicateId,
          message: 'Child flow ${reference.identity.surface.wireName}/'
              '${reference.identity.id} has both a normalized graph and a '
              'precompiled class-flow document.',
          location: source.span.location,
        );
        continue;
      }
      if (child == null && precompiledChild == null) {
        _addIssue(
          issues,
          code: IssueCode.missingScreenDescriptor,
          message: 'Flow ${flow.id} references unavailable child flow '
              '${reference.identity.surface.wireName}/'
              '${reference.identity.id}.',
          location: source.span.location,
        );
        continue;
      }
      final bytes = child == null ? precompiledChild : compile(child);
      if (bytes != null) {
        childDocuments[reference.identity] = bytes;
        final aggregateDeclarationIdentity = child?.declarationIdentity ??
            normalizedFlows
                .where(
                  (candidate) =>
                      candidate.identity == reference.identity &&
                      candidate.graph == null,
                )
                .map((candidate) => candidate.declarationIdentity)
                .firstOrNull;
        if (aggregateDeclarationIdentity == reference.declarationIdentity) {
          declarationBoundChildFlowIdentities.add(reference.identity);
        }
      }
    }
    final screenArtifacts = <String, ScreenArtifact>{};
    for (final reference in flow.graph!.screens.values) {
      final artifact = _artifactForFlowReference(
        artifactsByIdentity[reference.declarationIdentity],
        flow: flow,
        reference: reference,
      );
      if (artifact == null ||
          !_matchesFlowReference(
            flow: flow,
            reference: reference,
            artifact: artifact,
            issues: issues,
          )) {
        continue;
      }
      screenArtifacts[reference.id] = ScreenArtifact(
        path: artifact.rendered.flowArtifactPath,
        version: reference.version,
        schemaVersion: 1,
        minClient: artifact.sidecar.manifest.builtInFloor,
        contentHash: FlowContentHash.compute(artifact.rendered.blob),
      );
    }
    if (issues.isNotEmpty) {
      visiting.remove(flow.identity);
      return null;
    }
    final result = compileCanonicalFlowArtifact(
      flow: flow,
      source: source,
      screenArtifacts: screenArtifacts,
      childFlowDocuments: childDocuments,
      declarationBoundChildFlowIdentities: declarationBoundChildFlowIdentities,
    );
    issues.addAll(result.issues);
    visiting.remove(flow.identity);
    final bytes = result.compilation?.flowDocumentBytes;
    if (bytes != null) compiled[flow.identity] = bytes;
    return bytes;
  }

  (byIdentity.values.toList()
        ..sort((left, right) {
          final bySurface = left.surface.wireName.compareTo(
            right.surface.wireName,
          );
          return bySurface != 0 ? bySurface : left.id.compareTo(right.id);
        }))
      .forEach(compile);
  return compiled;
}

Map<NormalizedFlowIdentity, Uint8List> _indexPrecompiledClassFlowDocuments(
  Iterable<NormalizedFlowSource> flows,
  Map<String, CompiledFlowArtifact> precompiledFlowsByDeclarationIdentity, {
  required List<Issue> issues,
}) {
  final flowsByDeclarationIdentity = <String, NormalizedFlowSource>{};
  for (final flow in flows) {
    flowsByDeclarationIdentity[flow.declarationIdentity] = flow;
  }

  final documentsByIdentity = <NormalizedFlowIdentity, Uint8List>{};
  for (final entry in precompiledFlowsByDeclarationIdentity.entries) {
    final flow = flowsByDeclarationIdentity[entry.key];
    if (flow == null) {
      _addIssue(
        issues,
        code: IssueCode.unresolvedIdentifier,
        message: 'Precompiled flow ${entry.key} is absent from the '
            'normalized flow index.',
        location: entry.key,
      );
      continue;
    }
    if (flow.graph != null) {
      _addIssue(
        issues,
        code: IssueCode.duplicateId,
        message: 'Precompiled flow ${flow.id} also has a normalized graph; '
            'only class-shaped flows may supply precompiled documents.',
        location: flow.declarationIdentity,
      );
      continue;
    }

    final exactBytes = Uint8List.fromList(entry.value.flowDocumentBytes);
    try {
      final document = FlowDocumentCodec.decodeJson(utf8.decode(exactBytes));
      FlowDocumentValidation.checkValid(document);
      if (document.flow != flow.id ||
          document.version != flow.version ||
          document.minClient != flow.minClient ||
          document.deliveryMode != flow.delivery) {
        throw StateError(
          'Precompiled flow identity, version, minimum client, or delivery '
          'mode does not match its normalized source.',
        );
      }
    } on Object catch (error) {
      _addIssue(
        issues,
        code: IssueCode.unsupportedFlowRuntimeFeature,
        message: 'Could not validate exact precompiled flow ${flow.id}: '
            '$error',
        location: flow.declarationIdentity,
      );
      continue;
    }

    final previous = documentsByIdentity[flow.identity];
    if (previous != null) {
      _addIssue(
        issues,
        code: IssueCode.duplicateId,
        message: 'More than one precompiled flow document was supplied for '
            '${flow.surface.wireName}/${flow.id}.',
        location: flow.declarationIdentity,
      );
      continue;
    }
    documentsByIdentity[flow.identity] = exactBytes;
  }
  return documentsByIdentity;
}

_FlowAssembly? _assembleFlowPublication({
  required NormalizedFlowSource flow,
  required NormalizedFlowGraph graph,
  required RestageSourceDeclaration source,
  required Map<String, List<_ResolvedArtifact>> artifactsByIdentity,
  required String flowDocumentPath,
  required Uint8List? flowDocumentBytes,
  required List<Issue> issues,
}) {
  final screenArtifacts = <String, ScreenArtifact>{};
  final closureArtifacts = <_FlowClosureArtifact>[];
  final seenScreenIds = <String>{};
  final references = graph.screens.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));

  for (final graphEntry in references) {
    final reference = graphEntry.value;
    final artifact = _artifactForFlowReference(
      artifactsByIdentity[reference.declarationIdentity],
      flow: flow,
      reference: reference,
    );
    if (artifact == null) {
      _addIssue(
        issues,
        code: IssueCode.missingScreenDescriptor,
        message: 'Flow ${flow.id} references ${reference.id}, but no '
            'rendered roster-owned source artifact was supplied.',
        location: source.span.location,
      );
      continue;
    }
    if (!seenScreenIds.add(reference.id)) {
      _addIssue(
        issues,
        code: IssueCode.duplicateId,
        message: 'Flow ${flow.id} resolves multiple screen declarations to '
            'the same screen ID ${reference.id}.',
        location: source.span.location,
      );
      continue;
    }
    if (!_matchesFlowReference(
      flow: flow,
      reference: reference,
      artifact: artifact,
      issues: issues,
    )) {
      continue;
    }
    screenArtifacts[reference.id] = ScreenArtifact(
      path: artifact.rendered.flowArtifactPath,
      version: reference.version,
      schemaVersion: 1,
      minClient: artifact.sidecar.manifest.builtInFloor,
      contentHash: FlowContentHash.compute(artifact.rendered.blob),
    );
    closureArtifacts.add(
      _FlowClosureArtifact(artifact: artifact, id: reference.id),
    );
  }
  if (issues.isNotEmpty) return null;

  try {
    if (flowDocumentBytes == null) {
      throw StateError('Canonical flow document was not precompiled.');
    }
    final documentBytes = Uint8List.fromList(flowDocumentBytes);
    final document = FlowDocumentCodec.decodeJson(utf8.decode(documentBytes));
    if (document.flow != flow.id ||
        document.screenArtifacts.keys
            .toSet()
            .difference(screenArtifacts.keys.toSet())
            .isNotEmpty ||
        screenArtifacts.keys
            .toSet()
            .difference(document.screenArtifacts.keys.toSet())
            .isNotEmpty) {
      throw StateError('Precompiled flow identity or screen closure changed.');
    }
    final manifestInput = SurfacePublicationAssemblyInput(
      surface: flow.surface,
      slug: flow.id,
      sourceKind: SurfaceSourceKind.flowGraph,
      payloadKind: SurfacePayloadKind.flow,
      artifacts: [
        SurfacePublicationArtifactInput(
          path: flowDocumentPath,
          role: SurfacePublicationArtifactRole.flowDocument,
          bytes: documentBytes,
        ),
        for (final artifact in closureArtifacts)
          ..._screenClosureInputs(artifact.artifact, id: artifact.id),
      ],
      sources: _authoringSources([
        source,
        for (final artifact in closureArtifacts) artifact.artifact.source,
      ]),
      flowFacts: SurfacePublicationFlowFacts(deliveryMode: flow.delivery),
    );
    return _FlowAssembly(
      manifestInput: manifestInput,
      flowDocumentBytes: documentBytes,
    );
  } on Object catch (error) {
    _addIssue(
      issues,
      code: IssueCode.unsupportedFlowRuntimeFeature,
      message: 'Could not assemble canonical flow ${flow.id}: $error',
      location: source.span.location,
    );
    return null;
  }
}

_FlowAssembly? _assemblePrecompiledFlowPublication({
  required NormalizedFlowSource flow,
  required RestageSourceDeclaration source,
  required Map<String, List<_ResolvedArtifact>> artifactsByIdentity,
  required String flowDocumentPath,
  required List<int> flowDocumentBytes,
  required List<Issue> issues,
}) {
  try {
    final documentBytes = Uint8List.fromList(flowDocumentBytes);
    final document = FlowDocumentCodec.decodeJson(utf8.decode(documentBytes));
    FlowDocumentValidation.checkValid(document);
    if (document.flow != flow.id ||
        document.version != flow.version ||
        document.minClient != flow.minClient ||
        document.deliveryMode != flow.delivery) {
      throw StateError(
        'Precompiled flow identity, version, minimum client, or delivery '
        'mode does not match its analyzer-resolved source.',
      );
    }

    final allArtifacts = artifactsByIdentity.values.expand((value) => value);
    final closure = <_FlowClosureArtifact>[];
    final entries = document.screenArtifacts.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    for (final entry in entries) {
      final candidates = allArtifacts.where((artifact) {
        final rendered = artifact.rendered;
        final idMatches = rendered.flowScreenId == entry.key ||
            (rendered.flowScreenId == null &&
                artifact.source.effectiveId == entry.key);
        if (!idMatches ||
            rendered.flowArtifactPath != entry.value.path ||
            FlowContentHash.compute(rendered.blob) != entry.value.contentHash) {
          return false;
        }
        return artifact.source.kind == RestageRosterSourceKind.paywall ||
            artifact.surface == flow.surface;
      }).toList(growable: false);
      if (candidates.length != 1) {
        throw StateError(
          'Precompiled flow screen ${entry.key} resolved to '
          '${candidates.length} exact roster-owned artifacts.',
        );
      }
      closure.add(
        _FlowClosureArtifact(artifact: candidates.single, id: entry.key),
      );
    }

    return _FlowAssembly(
      manifestInput: SurfacePublicationAssemblyInput(
        surface: flow.surface,
        slug: flow.id,
        sourceKind: SurfaceSourceKind.flowGraph,
        payloadKind: SurfacePayloadKind.flow,
        artifacts: [
          SurfacePublicationArtifactInput(
            path: flowDocumentPath,
            role: SurfacePublicationArtifactRole.flowDocument,
            bytes: documentBytes,
          ),
          for (final artifact in closure)
            ..._screenClosureInputs(artifact.artifact, id: artifact.id),
        ],
        sources: _authoringSources([
          source,
          for (final artifact in closure) artifact.artifact.source,
        ]),
        flowFacts: SurfacePublicationFlowFacts(
          deliveryMode: flow.delivery,
        ),
      ),
      flowDocumentBytes: documentBytes,
    );
  } on Object catch (error) {
    _addIssue(
      issues,
      code: IssueCode.unsupportedFlowRuntimeFeature,
      message: 'Could not assemble class-shaped flow ${flow.id}: $error',
      location: source.span.location,
    );
    return null;
  }
}

bool _matchesFlowReference({
  required NormalizedFlowSource flow,
  required NormalizedScreenReference reference,
  required _ResolvedArtifact artifact,
  required List<Issue> issues,
}) {
  final source = artifact.source;
  if (source.version != reference.version ||
      source.minClient != reference.minClient) {
    _addIssue(
      issues,
      code: IssueCode.annotationEvaluationFailed,
      message: 'Flow ${flow.id} reference ${reference.id} does not match the '
          'rendered source ID, version, or minimum client.',
      location: source.span.location,
    );
    return false;
  }
  if (reference.isPaywall) {
    if (source.kind != RestageRosterSourceKind.paywall ||
        source.surface != Surface.paywall ||
        artifact.rendered.flowScreenId != reference.id) {
      _addIssue(
        issues,
        code: IssueCode.annotationEvaluationFailed,
        message: 'Flow ${flow.id} marks ${reference.id} as a paywall, but '
            'its rendered source is not the matching roster-owned paywall '
            'adapter.',
        location: source.span.location,
      );
      return false;
    }
    // Paywalls are specialized sources, not a composition fence.
    return true;
  }
  if (source.kind != RestageRosterSourceKind.screen) {
    _addIssue(
      issues,
      code: IssueCode.annotationEvaluationFailed,
      message: 'Flow ${flow.id} references ${reference.id} as an ordinary '
          'screen, but its rendered source has another source kind.',
      location: source.span.location,
    );
    return false;
  }
  if (artifact.rendered.flowScreenId != null ||
      source.effectiveId != reference.id) {
    _addIssue(
      issues,
      code: IssueCode.annotationEvaluationFailed,
      message: 'Flow ${flow.id} reference ${reference.id} does not match the '
          'rendered ordinary screen identity.',
      location: source.span.location,
    );
    return false;
  }
  if (reference.declaredSurface != null &&
      reference.declaredSurface != flow.surface) {
    _addIssue(
      issues,
      code: IssueCode.annotationEvaluationFailed,
      message: 'Categorized screen ${reference.id} '
          '(${reference.declaredSurface!.wireName}) cannot be included in '
          'flow ${flow.id} (${flow.surface.wireName}).',
      location: source.span.location,
    );
    return false;
  }
  if (source.surface != null && source.surface != flow.surface) {
    _addIssue(
      issues,
      code: IssueCode.annotationEvaluationFailed,
      message: 'Roster category ${source.surface!.wireName} for screen '
          '${reference.id} does not match flow ${flow.id} '
          '(${flow.surface.wireName}).',
      location: source.span.location,
    );
    return false;
  }
  return true;
}

SurfacePublicationAssemblyResult? _buildManifest(
  List<SurfacePublicationAssemblyInput> inputs, {
  required List<Issue> issues,
}) {
  try {
    return SurfacePublicationManifestAssembler.assemble(inputs);
  } on Object catch (error) {
    _addIssue(
      issues,
      code: IssueCode.annotationEvaluationFailed,
      message: 'Surface publication manifest assembly failed: $error',
      location: 'the package surface publication manifest',
    );
    return null;
  }
}

String? _emitNeutralReference({
  required String refName,
  required String descriptor,
  required String id,
  required int version,
  required CapabilityManifest capabilities,
  required String? sdkPrefix,
  required List<Issue> issues,
}) {
  if (sdkPrefix == null) {
    _addIssue(
      issues,
      code: IssueCode.analyzerResolutionFailed,
      message: 'The neutral screen library must import package:restage with '
          'a namespace that exposes generated reference types.',
      location: descriptor,
    );
    return null;
  }
  // The handle is the top-level `<className>Ref`. The holder class is the
  // previous shape, kept as a deprecated alias for one major so a source
  // written against it still compiles.
  return '''
const $refName = ${sdkPrefix}NeutralFlowScreenRef(
  id: ${_dartSingleString(id)},
  artifactPath: ${_dartSingleString('$id.rfw')},
  version: $version,
  minClient: ${capabilities.builtInFloor},
);

@Deprecated('Use $refName')
abstract final class $descriptor {
  const $descriptor._();

  static const ${sdkPrefix}NeutralFlowScreenRef ref = $refName;
}
''';
}

String? _emitCompatibilityScreenDescriptor({
  required String descriptor,
  required String id,
  required String artifactPath,
  required int version,
  required int minClient,
  required String? sdkPrefix,
  required RestageSourceDeclaration source,
  required List<Issue> issues,
  String? measurementPublicationDraftDigest,
}) {
  if (sdkPrefix == null) {
    _addIssue(
      issues,
      code: IssueCode.analyzerResolutionFailed,
      message: 'The screen library must expose NeutralFlowScreenRef for its '
          'advanced compatibility descriptor.',
      location: source.span.location,
    );
    return null;
  }
  final declarationKeyword =
      measurementPublicationDraftDigest == null ? 'const' : 'final';
  final referenceConstructor = measurementPublicationDraftDigest == null
      ? '${sdkPrefix}NeutralFlowScreenRef'
      : '${sdkPrefix}NeutralFlowScreenRef'
          '.generatedWithMeasurementPublicationDraftDigest';
  final carrierArgument = measurementPublicationDraftDigest == null
      ? ''
      : '    measurementPublicationDraftDigest: '
          '${_dartSingleString(measurementPublicationDraftDigest)},\n';
  return '''
abstract final class $descriptor {
  const $descriptor._();

  static $declarationKeyword ${sdkPrefix}NeutralFlowScreenRef ref =
      $referenceConstructor(
    id: ${_dartSingleString(id)},
    artifactPath: ${_dartSingleString(artifactPath)},
    version: $version,
    minClient: $minClient,
$carrierArgument  );
}
''';
}

String? _emitFlowReference({
  required String refName,
  required String resultName,
  required String decoderName,
  required String seedName,
  required NormalizedFlowGraph graph,
  required NormalizedFlowSource flow,
  required String sdkPrefix,
  required RestageSourceDeclaration source,
  required List<Issue> issues,
  String? measurementPublicationDraftDigest,
}) {
  final support = _emitCanonicalActions(resultName, graph.actions, sdkPrefix);
  final declarationKeyword =
      measurementPublicationDraftDigest == null ? 'const' : 'final';
  String referenceConstructor(String resultType) =>
      measurementPublicationDraftDigest == null
          ? '${sdkPrefix}SurfaceFlowRef<$resultType>'
          : '${sdkPrefix}SurfaceFlowRef<$resultType>'
              '.generatedWithMeasurementPublicationDraftDigest';
  final carrierArgument = measurementPublicationDraftDigest == null
      ? ''
      : '  measurementPublicationDraftDigest: '
          '${_dartSingleString(measurementPublicationDraftDigest)},\n';
  if (flow.delivery == FlowDeliveryMode.general) {
    return '''
$declarationKeyword $refName = ${referenceConstructor('Map<String, Object?>')}(
  id: ${_dartSingleString(flow.id)},
  version: ${flow.version},
  minClient: ${graph.minClient},
  surface: ${sdkPrefix}Surface.${flow.surface.name},
  deliveryMode: ${sdkPrefix}FlowDeliveryMode.${flow.delivery.name},
  decodeResult: $decoderName,
$carrierArgument);

Map<String, Object?> $decoderName(Map<String, Object?> result) => result;
${_emitSeedClass(seedName, graph.flowState, sdkPrefix)}
$support''';
  }

  final fields = graph.outbound.terminalResult.fields.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  for (final field in fields) {
    if (!_isSafeGeneratedIdentifier(field.key)) {
      _addIssue(
        issues,
        code: IssueCode.unsupportedFlowRuntimeFeature,
        message: 'Flow ${flow.id} terminal result key "${field.key}" cannot '
            'be represented by a typed Dart result field.',
        location: source.span.location,
      );
      return null;
    }
  }
  final decoder = _emitTypedResultDecoder(
    decoderName: decoderName,
    resultName: resultName,
    fields: fields,
  );
  final result = _emitTypedResultClass(resultName, fields);
  return '''
$declarationKeyword $refName = ${referenceConstructor(resultName)}(
  id: ${_dartSingleString(flow.id)},
  version: ${flow.version},
  minClient: ${graph.minClient},
  surface: ${sdkPrefix}Surface.${flow.surface.name},
  deliveryMode: ${sdkPrefix}FlowDeliveryMode.${flow.delivery.name},
  decodeResult: $decoderName,
$carrierArgument);

$decoder

$result
${_emitSeedClass(seedName, graph.flowState, sdkPrefix)}
$support''';
}

String _emitCanonicalActions(
  String resultName,
  Map<String, FlowActionContract> actions,
  String sdkPrefix,
) {
  if (actions.isEmpty) return '';
  final className =
      '${resultName.substring(0, resultName.length - 'Result'.length)}Actions';
  final entries = actions.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  final parameters = entries.map((entry) {
    final parameter = _lowerCamelIdentifier(entry.key, fallback: 'action');
    return '    required ${sdkPrefix}FlowActionHandler<Object?, Object?> '
        '$parameter,';
  }).join('\n');
  final bindings = entries.map((entry) {
    final parameter = _lowerCamelIdentifier(entry.key, fallback: 'action');
    final descriptor = '${parameter}Descriptor';
    return '''
      ${_dartSingleString(entry.key)}:
          ${sdkPrefix}FlowActionBinding<Object?, Object?>(
        descriptor: $descriptor,
        actionName: $descriptor.actionName,
        contractVersion: $descriptor.contractVersion,
        argsSchema: $descriptor.argsSchema,
        resultSchema: $descriptor.resultSchema,
        minClient: $descriptor.minClient,
        idempotent: $descriptor.idempotent,
        handler: $parameter,
        decodeArgs: (value) => value,
        encodeResult: (value) => value,
      ),''';
  }).join('\n');
  final descriptors = entries.map((entry) {
    final descriptor =
        '${_lowerCamelIdentifier(entry.key, fallback: 'action')}Descriptor';
    final contract = entry.value;
    return '''
  static final ${sdkPrefix}FlowActionDescriptor<Object?, Object?> $descriptor =
      ${sdkPrefix}FlowActionDescriptor<Object?, Object?>(
    actionName: ${_dartSingleString(contract.actionName)},
    contractVersion: ${contract.contractVersion},
    argsSchema: ${_flowActionSchemaSource(contract.argsSchema, sdkPrefix)},
    resultSchema: ${_flowActionSchemaSource(contract.resultSchema, sdkPrefix)},
    minClient: ${contract.minClient},
    idempotent: ${contract.idempotent},
  );''';
  }).join('\n\n');
  return '''
final class $className implements ${sdkPrefix}FlowActionRegistry {
  $className({
$parameters
  }) : flowActionBindings =
            Map<String, ${sdkPrefix}FlowActionBinding<dynamic, dynamic>>
                .unmodifiable({
$bindings
          });

$descriptors

  @override
  final Map<String, ${sdkPrefix}FlowActionBinding<dynamic, dynamic>>
      flowActionBindings;
}''';
}

String _flowActionSchemaSource(FlowActionSchema schema, String sdkPrefix) {
  switch (schema) {
    case FlowObjectActionSchema(:final fields):
      if (fields.isEmpty) {
        return 'const ${sdkPrefix}FlowActionSchema.object({})';
      }
      final entries = fields.entries.toList()
        ..sort((left, right) => left.key.compareTo(right.key));
      final values = entries.map((entry) {
        final fieldType = '${sdkPrefix}FlowActionSchemaField';
        final fieldSchema = _flowActionSchemaSource(
          entry.value.schema,
          sdkPrefix,
        );
        return [
          '${_dartSingleString(entry.key)}: $fieldType(',
          'required: ${entry.value.required},',
          'schema: $fieldSchema,',
          ')',
        ].join(' ');
      }).join(', ');
      return 'const ${sdkPrefix}FlowActionSchema.object({$values})';
    case FlowBoolActionSchema():
      return 'const ${sdkPrefix}FlowActionSchema.bool()';
    case FlowIntActionSchema():
      return 'const ${sdkPrefix}FlowActionSchema.int()';
    case FlowDoubleActionSchema():
      return 'const ${sdkPrefix}FlowActionSchema.double()';
    case FlowStringActionSchema():
      return 'const ${sdkPrefix}FlowActionSchema.string()';
    case FlowEnumActionSchema(:final values):
      final enumType = '${sdkPrefix}FlowActionSchema.enumValues';
      return 'const $enumType([${values.map(_dartSingleString).join(', ')}])';
    case FlowListActionSchema(:final child):
      return 'const ${sdkPrefix}FlowActionSchema.list('
          '${_flowActionSchemaSource(child, sdkPrefix)})';
    case FlowNullableActionSchema(:final child):
      return 'const ${sdkPrefix}FlowActionSchema.nullable('
          '${_flowActionSchemaSource(child, sdkPrefix)})';
  }
}

String _emitTypedResultDecoder({
  required String decoderName,
  required String resultName,
  required List<MapEntry<String, FlowOutboundField>> fields,
}) {
  if (fields.isEmpty) {
    return '''
$resultName $decoderName(Map<String, Object?> result) {
    if (result.isNotEmpty) {
      throw const FormatException('Unexpected flow result keys.');
    }
    return const $resultName();
  }''';
  }
  final missing = fields
      .map((field) => '!result.containsKey(${_dartString(field.key)})')
      .join(' || ');
  final reads = fields.map((field) {
    final type = _dartType(field.value.type);
    return '''
    final ${field.key} = result[${_dartString(field.key)}];
    if (${field.key} is! $type) {
      throw const FormatException('Expected result field ${field.key} to be $type.');
    }''';
  }).join('\n');
  final arguments =
      fields.map((field) => '${field.key}: ${field.key}').join(', ');
  return '''
$resultName $decoderName(Map<String, Object?> result) {
    if (result.length != ${fields.length} || $missing) {
      throw const FormatException('Unexpected flow result keys.');
    }
$reads
    return $resultName($arguments);
  }''';
}

String _emitTypedResultClass(
  String resultName,
  List<MapEntry<String, FlowOutboundField>> fields,
) {
  if (fields.isEmpty) {
    return '''
final class $resultName {
  const $resultName();
}''';
  }
  final parameters =
      fields.map((field) => 'required this.${field.key}').join(', ');
  final members = fields
      .map((field) => '  final ${_dartType(field.value.type)} ${field.key};')
      .join('\n');
  return '''
final class $resultName {
  const $resultName({$parameters});

$members
}''';
}

String _emitSeedClass(
  String seedName,
  Map<String, FlowStateDeclaration> flowState,
  String sdkPrefix,
) {
  final seedable = flowState.entries
      .where((entry) => entry.value.hostSeedable)
      .toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  if (seedable.isEmpty) return '';
  if (seedable.any((entry) => !_isSafeGeneratedIdentifier(entry.key))) {
    return '';
  }
  final parameters =
      seedable.map((entry) => '    this.${entry.key},').join('\n');
  final fields = seedable
      .map((entry) => '  final ${_dartType(entry.value.type)}? ${entry.key};')
      .join('\n');
  final values = seedable
      .map(
        (entry) => '        if (${entry.key} != null) '
            '${_dartString(entry.key)}: ${entry.key},',
      )
      .join('\n');
  return '''
final class $seedName implements ${sdkPrefix}FlowSeed {
  const $seedName({
$parameters
  });

$fields

  @override
  Map<String, Object?> toFlowState() => {
$values
      };
}
''';
}

String _dartType(FlowDataType type) => switch (type) {
      FlowDataType.bool => 'bool',
      FlowDataType.int => 'int',
      FlowDataType.string => 'String',
    };

List<SurfacePublicationArtifactInput> _screenClosureInputs(
  _ResolvedArtifact artifact, {
  String? id,
}) {
  final artifactId = id ?? artifact.source.effectiveId;
  return [
    SurfacePublicationArtifactInput(
      path: artifact.blobPath,
      role: SurfacePublicationArtifactRole.screenBlob,
      id: artifactId,
      bytes: artifact.rendered.blob,
    ),
    SurfacePublicationArtifactInput(
      path: artifact.sidecarPath,
      role: SurfacePublicationArtifactRole.capabilitySidecar,
      id: artifactId,
      bytes: artifact.rendered.capabilitySidecar,
    ),
  ];
}

ResolvedStandaloneScreenContract? _refreshStandaloneContractBundleMetadata(
  ResolvedStandaloneScreenContract contract, {
  required List<SurfacePublicationAssemblyInput> manifestInputs,
  required List<Issue> issues,
}) {
  final matchingPublications = manifestInputs.where(
    (input) =>
        input.surface == contract.surface &&
        input.slug == contract.slug &&
        input.sourceKind == SurfaceSourceKind.screen &&
        input.screenContractFacts?.contractVersion == contract.contractVersion,
  );
  if (matchingPublications.length != 1) {
    _addIssue(
      issues,
      code: IssueCode.missingScreenDescriptor,
      message: 'Standalone screen ${contract.slug} must resolve exactly one '
          'final publication before generated reference emission.',
      location: contract.input.location,
    );
    return null;
  }
  final artifacts = matchingPublications.single.artifacts;
  final blobs = artifacts.where(
    (artifact) => artifact.role == SurfacePublicationArtifactRole.screenBlob,
  );
  final sidecars = artifacts.where(
    (artifact) =>
        artifact.role == SurfacePublicationArtifactRole.capabilitySidecar,
  );
  if (blobs.length != 1 || sidecars.length != 1) {
    _addIssue(
      issues,
      code: IssueCode.missingScreenDescriptor,
      message: 'Standalone screen ${contract.slug} must resolve one final '
          'blob and capability sidecar before generated reference emission.',
      location: contract.input.location,
    );
    return null;
  }
  final blob = blobs.single.bytes;
  final sidecar = sidecars.single.bytes;
  final inspection = inspectStandaloneScreenContract(
    ResolvedStandaloneScreenContractInput(
      assetId: contract.input.assetId,
      screen: contract.screen,
      surface: contract.surface,
      slug: contract.slug,
      contractVersion: contract.contractVersion,
      capabilities: contract.capabilities,
      plan: contract.input.plan,
      bundleEntryMetadata: ResolvedScreenBundleEntryMetadata(
        blobSha256: CapabilitySidecar.hashBlob(blob),
        blobByteLength: blob.length,
        sidecarSha256: CapabilitySidecar.hashBlob(sidecar),
        sidecarByteLength: sidecar.length,
      ),
    ),
  );
  issues.addAll(inspection.issues);
  return inspection.contract;
}

List<String> _outputPaths(
  RestageSourceDeclaration source, {
  required Set<String> roles,
}) {
  final paths = source.outputs
      .where((output) => roles.contains(output.role))
      .map((output) => output.path)
      .toSet()
      .toList()
    ..sort();
  return paths;
}

Surface? _artifactSurfaceFromPath(
  String path, {
  required RestageSourceDeclaration source,
  required Iterable<NormalizedScreenReference> flowReferences,
  required List<Issue> issues,
}) {
  if (source.surface case final surface?) return surface;
  final segments = path.split('/');
  if (segments.length >= 4 && segments.first == 'assets') {
    final wireName = segments[1];
    for (final surface in Surface.values) {
      if (surface.wireName == wireName) return surface;
    }
  }
  final inherited =
      flowReferences.map((reference) => reference.effectiveSurface).toSet();
  if (inherited.length == 1) return inherited.single;
  _addIssue(
    issues,
    code: IssueCode.annotationEvaluationFailed,
    message: 'Roster artifact path "$path" has no supported surface '
        'identity.',
    location: source.span.location,
  );
  return null;
}

String? _matchingSidecarPath(
  String blobPath,
  List<String> sidecarPaths, {
  required RestageSourceDeclaration source,
  required List<Issue> issues,
}) {
  final expected = blobPath.endsWith('.rfw')
      ? '${blobPath.substring(0, blobPath.length - '.rfw'.length)}'
          '.capability.json'
      : null;
  final matches = expected == null
      ? const <String>[]
      : sidecarPaths.where((path) => path == expected).toList();
  if (matches.length == 1) return matches.single;
  _addIssue(
    issues,
    code: IssueCode.missingScreenDescriptor,
    message: 'Roster blob "$blobPath" requires its exact capability '
        'sidecar; found ${matches.length}.',
    location: source.span.location,
  );
  return null;
}

_ResolvedArtifact? _artifactForSurface(
  List<_ResolvedArtifact>? artifacts,
  Surface surface,
) {
  if (artifacts == null) return null;
  return artifacts.where((artifact) => artifact.surface == surface).firstOrNull;
}

_ResolvedArtifact? _artifactForFlowReference(
  List<_ResolvedArtifact>? artifacts, {
  required NormalizedFlowSource flow,
  required NormalizedScreenReference reference,
}) {
  if (artifacts == null) return null;
  if (reference.isPaywall) {
    return artifacts
        .where(
          (artifact) =>
              artifact.source.kind == RestageRosterSourceKind.paywall &&
              artifact.rendered.flowScreenId == reference.id,
        )
        .firstOrNull;
  }
  return artifacts
      .where(
        (artifact) =>
            artifact.source.kind == RestageRosterSourceKind.screen &&
            artifact.surface == (reference.declaredSurface ?? flow.surface),
      )
      .firstOrNull;
}

CapabilitySidecar? _decodeSidecar(
  List<int> sidecarBytes,
  List<int> blob, {
  required RestageSourceDeclaration source,
  required List<Issue> issues,
}) {
  try {
    final decoded = jsonDecode(utf8.decode(sidecarBytes));
    if (decoded is! Map<Object?, Object?> ||
        decoded.length != 2 ||
        !decoded.containsKey('blobSha256') ||
        !decoded.containsKey('manifest')) {
      throw const FormatException(
        'Capability sidecar must contain exactly blobSha256 and manifest.',
      );
    }
    final sidecarJson = <String, dynamic>{};
    for (final entry in decoded.entries) {
      final key = entry.key;
      if (key is! String) {
        throw const FormatException('Capability sidecar keys must be strings.');
      }
      sidecarJson[key] = entry.value;
    }
    final sidecar = CapabilitySidecar.fromJson(sidecarJson);
    if (sidecar.blobSha256 != CapabilitySidecar.hashBlob(blob)) {
      throw const FormatException(
        'Capability sidecar hash does not match blob.',
      );
    }
    return sidecar;
  } on Object catch (error) {
    _addIssue(
      issues,
      code: IssueCode.annotationEvaluationFailed,
      message: 'Invalid capability sidecar for ${source.effectiveId}: $error',
      location: source.span.location,
    );
    return null;
  }
}

_FinalizedMeasurementAssemblies _finalizeMeasurementAssemblies({
  required List<SurfacePublicationAssemblyInput> inputs,
  required Map<String, MeasurementPublicationRoutePlanV1>
      routePlansByPublicationKey,
  required Map<String, RestageSourceDeclaration> sourcesByOutputPath,
}) {
  final pathClaims = <String, int>{};
  for (final input in inputs) {
    for (final artifact in input.artifacts) {
      pathClaims.update(artifact.path, (count) => count + 1, ifAbsent: () => 1);
    }
  }
  final finalizedInputs = <SurfacePublicationAssemblyInput>[];
  final finalizedArtifacts = <_FinalizedMeasurementArtifact>[];
  final publications = <MeasurementCompilerPublication>[];
  final claimedPlans = <String>{};

  for (final input in inputs) {
    final selector = _measurementSelectorForAssembly(input);
    final routePlan = routePlansByPublicationKey[selector.key];
    if (routePlan == null) {
      finalizedInputs.add(input);
      continue;
    }
    claimedPlans.add(selector.key);
    final bySlot = <String, SurfacePublicationArtifactInput>{
      for (final artifact in input.artifacts)
        _measurementArtifactSlot(artifact.role, artifact.id): artifact,
    };
    final finalBytesBySlot = <String, Uint8List>{
      for (final entry in bySlot.entries)
        entry.key: Uint8List.fromList(entry.value.bytes),
    };
    final consumed = <String>{};
    for (final entry in bySlot.entries.where(
      (entry) => entry.value.role == SurfacePublicationArtifactRole.screenBlob,
    )) {
      final composition = MeasurementRfwRouteComposer.composeBlob(
        blob: entry.value.bytes,
        routePlan: routePlan,
      );
      final duplicate = consumed.intersection(composition.generatedReferences);
      if (duplicate.isNotEmpty) {
        throw FormatException(
          'Measurement generated references occurred in multiple publication '
          'artifacts: ${duplicate.toList()..sort()}',
        );
      }
      consumed.addAll(composition.generatedReferences);
      finalBytesBySlot[entry.key] = composition.blob;
      final sidecarSlot = _measurementArtifactSlot(
        SurfacePublicationArtifactRole.capabilitySidecar,
        entry.value.id,
      );
      final sidecar = finalBytesBySlot[sidecarSlot];
      if (sidecar == null) {
        throw FormatException(
          'Measurement blob ${entry.value.id} has no capability sidecar.',
        );
      }
      finalBytesBySlot[sidecarSlot] = Uint8List.fromList(
        _sidecarForComposedBlob(sidecar, composition.blob),
      );
    }
    MeasurementRfwRouteComposer.requireCompleteRouteClosure(
      routePlan: routePlan,
      consumedReferences: consumed,
    );

    if (input.payloadKind == SurfacePayloadKind.flow) {
      final flowSlot = _measurementArtifactSlot(
        SurfacePublicationArtifactRole.flowDocument,
        null,
      );
      final flowBytes = finalBytesBySlot[flowSlot];
      if (flowBytes == null) {
        throw const FormatException(
          'A measured flow has no exact flow document.',
        );
      }
      final flow = FlowDocumentCodec.decodeJson(utf8.decode(flowBytes));
      final screenArtifacts = <String, ScreenArtifact>{};
      for (final entry in flow.screenArtifacts.entries) {
        final blob = finalBytesBySlot[_measurementArtifactSlot(
          SurfacePublicationArtifactRole.screenBlob,
          entry.key,
        )];
        if (blob == null) {
          throw FormatException(
            'Measured flow screen ${entry.key} has no exact final blob.',
          );
        }
        screenArtifacts[entry.key] = ScreenArtifact(
          path: entry.value.path,
          version: entry.value.version,
          schemaVersion: entry.value.schemaVersion,
          minClient: entry.value.minClient,
          contentHash: FlowContentHash.compute(blob),
        );
      }
      finalBytesBySlot[flowSlot] = Uint8List.fromList(
        FlowDocumentCodec.encodeCanonicalJson(
          flow.copyWith(screenArtifacts: screenArtifacts),
        ),
      );
    }

    final finalArtifacts = <SurfacePublicationArtifactInput>[];
    final draftArtifacts = <MeasurementPublicationDraftArtifactV1>[];
    for (final artifact in input.artifacts) {
      final slot = _measurementArtifactSlot(artifact.role, artifact.id);
      final bytes = finalBytesBySlot[slot]!;
      final path = pathClaims[artifact.path]! > 1
          ? _measurementPublicationOwnedPath(artifact.path, selector)
          : artifact.path;
      final finalArtifact = SurfacePublicationArtifactInput(
        path: path,
        role: artifact.role,
        id: artifact.id,
        bytes: bytes,
      );
      finalArtifacts.add(finalArtifact);
      final source = sourcesByOutputPath[artifact.path];
      if (source == null) {
        throw FormatException(
          'Measurement artifact ${artifact.path} has no roster source owner.',
        );
      }
      finalizedArtifacts.add(
        _FinalizedMeasurementArtifact(
          path: path,
          bytes: bytes,
          source: source,
        ),
      );
      final artifactId = measurementArtifactIdForPublicationArtifactV1(
        selector,
        SurfacePublicationArtifact(
          contentHash: CapabilitySidecar.hashBlob(bytes),
          path: artifact.path,
          role: artifact.role,
          id: artifact.id,
        ),
      );
      final topology = routePlan.artifacts.singleWhere(
        (candidate) => candidate.artifactId == artifactId,
      );
      draftArtifacts.add(
        MeasurementPublicationDraftArtifactV1(
          artifactId: topology.artifactId,
          artifactKind: topology.artifactKind,
          contentHash: CanonicalDigest(
            crypto.sha256.convert(bytes).toString(),
          ),
          occurrenceEdgeToken: topology.occurrenceEdgeToken,
          localManifestId: topology.localManifestId,
          parentOccurrenceEdgeToken: topology.parentOccurrenceEdgeToken,
        ),
      );
    }
    final draft = MeasurementPublicationDraftV1(
      routePlan: routePlan,
      artifacts: draftArtifacts,
    );
    publications.add(
      MeasurementCompilerPublication(
        selector: selector,
        routePlan: routePlan,
        draft: draft,
      ),
    );
    finalizedInputs.add(
      SurfacePublicationAssemblyInput(
        surface: input.surface,
        slug: input.slug,
        sourceKind: input.sourceKind,
        payloadKind: input.payloadKind,
        artifacts: finalArtifacts,
        flowFacts: input.flowFacts,
        screenContractFacts: input.screenContractFacts,
      ),
    );
  }
  final missingPlans = routePlansByPublicationKey.keys
      .where((key) => !claimedPlans.contains(key))
      .toList()
    ..sort();
  if (missingPlans.isNotEmpty) {
    throw FormatException(
      'Measurement route plans have no exact publication: $missingPlans',
    );
  }
  return _FinalizedMeasurementAssemblies(
    inputs: finalizedInputs,
    artifacts: finalizedArtifacts,
    publications: publications,
  );
}

MeasurementPublicationSelectorV1 _measurementSelectorForAssembly(
  SurfacePublicationAssemblyInput input,
) =>
    MeasurementPublicationSelectorV1(
      surface: input.surface,
      slug: input.slug,
      sourceKind: input.sourceKind,
      contractVersion: input.screenContractFacts?.contractVersion,
    );

void _stripMeasurementMarkersFromInspectionOutputs(
  Map<String, Uint8List> outputFiles,
) {
  for (final entry in outputFiles.entries.toList()) {
    if (!entry.key.endsWith('.rfwtxt')) continue;
    final text = utf8.decode(entry.value);
    if (!text.contains(kMeasurementRouteReferenceMarkerKeyV1)) continue;
    outputFiles[entry.key] = Uint8List.fromList(
      utf8.encode(
        MeasurementRfwRouteComposer.stripTransientMarkersFromText(text),
      ),
    );
  }
}

String _measurementArtifactSlot(
  SurfacePublicationArtifactRole role,
  String? id,
) =>
    '${role.wireName}:${id ?? ''}';

String _measurementPublicationOwnedPath(
  String original,
  MeasurementPublicationSelectorV1 selector,
) {
  final digest = crypto.sha256
      .convert(CanonicalJsonCodec.encode(selector.toJson()))
      .toString()
      .substring(0, 16);
  return p.posix.join(
    p.posix.dirname(original),
    'measurement',
    digest,
    p.posix.basename(original),
  );
}

final class _FinalizedMeasurementAssemblies {
  const _FinalizedMeasurementAssemblies({
    required this.inputs,
    required this.artifacts,
    required this.publications,
  });

  final List<SurfacePublicationAssemblyInput> inputs;
  final List<_FinalizedMeasurementArtifact> artifacts;
  final List<MeasurementCompilerPublication> publications;
}

final class _FinalizedMeasurementArtifact {
  const _FinalizedMeasurementArtifact({
    required this.path,
    required this.bytes,
    required this.source,
  });

  final String path;
  final Uint8List bytes;
  final RestageSourceDeclaration source;
}

List<int> _sidecarForComposedBlob(
  List<int> sidecarBytes,
  List<int> blob,
) {
  final decoded = jsonDecode(utf8.decode(sidecarBytes));
  if (decoded is! Map<Object?, Object?> ||
      decoded.length != 2 ||
      !decoded.containsKey('blobSha256') ||
      !decoded.containsKey('manifest')) {
    throw const FormatException(
      'Capability sidecar must contain exactly blobSha256 and manifest.',
    );
  }
  final sidecarJson = <String, dynamic>{};
  for (final entry in decoded.entries) {
    if (entry.key is! String) {
      throw const FormatException('Capability sidecar keys must be strings.');
    }
    final key = entry.key;
    if (key is! String) {
      throw const FormatException('Capability sidecar keys must be strings.');
    }
    sidecarJson[key] = entry.value;
  }
  final previous = CapabilitySidecar.fromJson(sidecarJson);
  return utf8.encode(
    jsonEncode(
      CapabilitySidecar(
        blobSha256: CapabilitySidecar.hashBlob(blob),
        manifest: previous.manifest,
      ).toJson(),
    ),
  );
}

String? _requiredOutputPath(
  RestageSourceDeclaration source, {
  required String role,
  required List<Issue> issues,
}) {
  final path = _optionalOutputPath(source, role: role, issues: issues);
  if (path != null) return path;
  _addIssue(
    issues,
    code: IssueCode.missingScreenDescriptor,
    message: 'Roster declaration ${source.effectiveId} is missing its '
        'required $role output claim.',
    location: source.span.location,
  );
  return null;
}

String? _requiredOutputPathAny(
  RestageSourceDeclaration source, {
  required Set<String> roles,
  required List<Issue> issues,
}) {
  final paths = _outputPaths(source, roles: roles);
  if (paths.length == 1) return paths.single;
  _addIssue(
    issues,
    code: paths.isEmpty
        ? IssueCode.missingScreenDescriptor
        : IssueCode.generatedSymbolCollision,
    message: 'Roster declaration ${source.effectiveId} requires exactly one '
        '${roles.toList()..sort()} output claim; found ${paths.length}.',
    location: source.span.location,
  );
  return null;
}

String? _optionalOutputPath(
  RestageSourceDeclaration source, {
  required String role,
  required List<Issue> issues,
}) {
  final paths = source.outputs
      .where((output) => output.role == role)
      .map((output) => output.path)
      .toSet()
      .toList()
    ..sort();
  if (paths.length <= 1) return paths.firstOrNull;
  _addIssue(
    issues,
    code: IssueCode.generatedSymbolCollision,
    message: 'Roster declaration ${source.effectiveId} has more than one '
        '$role output path: ${paths.join(', ')}.',
    location: source.span.location,
  );
  return null;
}

void _putOutputFile(
  Map<String, Uint8List> files, {
  required String path,
  required List<int> bytes,
  required RestageSourceDeclaration source,
  required List<Issue> issues,
  required Map<String, String> libraryPaths,
}) =>
    _putFile(
      files,
      path: path,
      bytes: bytes,
      source: source,
      issues: issues,
      label: 'output',
      libraryPaths: libraryPaths,
    );

void _putFile(
  Map<String, Uint8List> files, {
  required String path,
  required List<int> bytes,
  required RestageSourceDeclaration source,
  required List<Issue> issues,
  required String label,
  required Map<String, String> libraryPaths,
}) {
  final frozen = Uint8List.fromList(bytes);
  final existing = files[path];
  if (existing != null && !_sameBytes(existing, frozen)) {
    _addIssue(
      issues,
      code: IssueCode.generatedSymbolCollision,
      message: 'Conflicting $label bytes claim roster-owned path $path.',
      location: source.span.location,
    );
    return;
  }
  files[path] = frozen;
  libraryPaths[path] = source.libraryPath;
}

void _addPartFragment(
  Map<String, _PartAccumulator> fragments, {
  required String path,
  required RestageSourceDeclaration source,
  required String? fragment,
}) {
  if (fragment == null || fragment.trim().isEmpty) return;
  final header = _partOfHeader(
    partPath: path,
    libraryPath: source.libraryPath,
  );
  final accumulator = fragments[path];
  if (accumulator == null) {
    fragments[path] = _PartAccumulator(header: header, fragments: [fragment]);
    return;
  }
  if (accumulator.header != header) {
    // This cannot occur for a valid shared library-owned output claim. The
    // later formatter call will not make a mismatched library part valid, so
    // retain the first deterministic header and let the caller surface its
    // source ownership diagnostic through the roster.
    return;
  }
  accumulator.fragments.add(fragment);
}

String? _formatPart(
  _PartAccumulator accumulator, {
  required List<Issue> issues,
}) {
  final fragments = List<String>.of(accumulator.fragments)..sort();
  try {
    return formatGeneratedDart(
      '${accumulator.header}\n\n${fragments.join('\n\n')}\n',
    );
  } on Object catch (error) {
    _addIssue(
      issues,
      code: IssueCode.malformedTranslatorOutput,
      message: 'Could not format generated publication reference part: $error',
      location: accumulator.header,
    );
    return null;
  }
}

void _claimGeneratedSymbol(
  Map<String, String> claimedSymbols, {
  required RestageSourceDeclaration source,
  required LibraryElement? library,
  required String symbol,
  required List<Issue> issues,
}) {
  if (library != null &&
      _topLevelNames(library, source: source).contains(symbol)) {
    _addIssue(
      issues,
      code: IssueCode.generatedSymbolCollision,
      message: 'Generated symbol $symbol already exists in '
          '${source.libraryPath}.',
      location: source.span.location,
    );
    return;
  }
  final key = '${source.libraryIdentity}\u0000$symbol';
  final existing = claimedSymbols[key];
  if (existing != null && existing != source.declarationIdentity) {
    _addIssue(
      issues,
      code: IssueCode.generatedSymbolCollision,
      message: 'Generated symbol $symbol is shared by $existing and '
          '${source.declarationIdentity}.',
      location: source.span.location,
    );
    return;
  }
  claimedSymbols[key] = source.declarationIdentity;
}

/// Returns the analyzer-resolved top-level declarations that can collide with
/// a generated symbol for [source].
///
/// The generated descriptor part is already visible to the analyzer during a
/// warm or incremental build. It is safe to exclude declarations from that
/// part only when its exact package-relative path is claimed by [source]. A
/// filename suffix or a general `.g.dart` check would also hide user
/// declarations in lookalike/foreign generated parts.
@visibleForTesting
Set<String> topLevelNamesForGeneratedSymbolCollision(
  LibraryElement library,
  RestageSourceDeclaration source,
) =>
    _topLevelNames(library, source: source);

Set<String> _topLevelNames(
  LibraryElement library, {
  RestageSourceDeclaration? source,
}) {
  final names = <String>{};
  final ownedGeneratedPart =
      source == null ? null : _ownedGeneratedPartAsset(library, source);
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
    for (final element in elements) {
      if (ownedGeneratedPart != null &&
          _elementAssetId(element) == ownedGeneratedPart) {
        continue;
      }
      final name = element.name;
      if (name != null && name.isNotEmpty) names.add(name);
      final lookup = element.lookupName;
      if (lookup != null && lookup.isNotEmpty) names.add(lookup);
    }
  }
  return names;
}

AssetId? _ownedGeneratedPartAsset(
  LibraryElement library,
  RestageSourceDeclaration source,
) {
  final paths = source.outputs
      .where(
        (output) =>
            kGeneratedPartRoles.contains(output.role) &&
            output.path.endsWith(kNeutralGeneratedPartSuffix),
      )
      .map((output) => output.path)
      .toSet();
  if (paths.length != 1) return null;

  final libraryAsset = _elementAssetId(library);
  if (libraryAsset == null) return null;
  return AssetId(libraryAsset.package, paths.single);
}

AssetId? _elementAssetId(Element element) {
  final uri = element is LibraryElement
      ? element.uri
      : element.firstFragment.libraryFragment?.source.uri;
  if (uri == null) return null;
  try {
    return AssetId.resolve(uri);
  } on Object {
    // File URIs occur in a few analyzer-only callers. They have no stable
    // package-relative identity, so fail closed and retain the declaration.
    return null;
  }
}

String? _sdkPrefixFor(
  LibraryElement library,
  Set<String> symbols,
) {
  final candidates = <String>[];
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

String _withoutPartHeader(String source) {
  final trimmed = source.trim();
  if (!trimmed.startsWith('part of ')) return trimmed;
  final lineEnd = trimmed.indexOf('\n');
  if (lineEnd == -1) return '';
  return trimmed.substring(lineEnd + 1).trim();
}

String _classIdentity(ClassElement element) =>
    '${element.library.identifier}#${element.name ?? '<unnamed>'}';

/// The `part of` directive a generated part at [partPath] must declare to
/// reach the authored library at [libraryPath].
///
/// The URI is resolved relative to the part's own directory, so it follows
/// the part wherever the placement plan put it.
String _partOfHeader({
  required String partPath,
  required String libraryPath,
}) =>
    'part of ${_dartSingleString(
      p.posix.relative(libraryPath, from: p.posix.dirname(partPath)),
    )};';

// Both name derivations live in generated_handle_names.dart so the screen and
// flow frontends spell one rule. These aliases keep the call sites unchanged.
const String Function(String, {required String fallback}) _pascalIdentifier =
    pascalIdentifier;
const String Function(String, {required String fallback})
    _lowerCamelIdentifier = lowerCamelIdentifier;

String _dartString(String value) => jsonEncode(value).replaceAll(r'$', r'\$');

String _dartSingleString(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$');
  return "'$escaped'";
}

bool _isDeliveryArtifactPath(String path) {
  if (path.isEmpty || path.trim() != path || path.startsWith('/')) {
    return false;
  }
  if (path.contains(r'\')) return false;
  return path.split('/').every(
        (segment) => segment.isNotEmpty && segment != '.' && segment != '..',
      );
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _isSafeGeneratedIdentifier(String value) {
  if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value)) return false;
  return !_dartReservedWords.contains(value);
}

const Set<String> _dartReservedWords = {
  'abstract',
  'as',
  'assert',
  'async',
  'await',
  'base',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'covariant',
  'default',
  'deferred',
  'do',
  'dynamic',
  'else',
  'enum',
  'export',
  'extends',
  'extension',
  'external',
  'factory',
  'false',
  'final',
  'finally',
  'for',
  'Function',
  'get',
  'hide',
  'if',
  'implements',
  'import',
  'in',
  'interface',
  'is',
  'late',
  'library',
  'mixin',
  'new',
  'null',
  'on',
  'operator',
  'part',
  'required',
  'rethrow',
  'return',
  'sealed',
  'set',
  'static',
  'super',
  'switch',
  'sync',
  'this',
  'throw',
  'true',
  'try',
  'typedef',
  'var',
  'void',
  'when',
  'while',
  'with',
  'yield',
};

void _addIssue(
  List<Issue> issues, {
  required IssueCode code,
  required String message,
  required String location,
}) {
  issues.add(Issue(code: code, message: message, location: location));
}

PackageSurfaceCompilationResult _invalidResult(List<Issue> unsorted) {
  final issues = List<Issue>.of(unsorted)
    ..sort((left, right) {
      final byLocation = left.location.compareTo(right.location);
      if (byLocation != 0) return byLocation;
      final byCode = left.code.index.compareTo(right.code.index);
      if (byCode != 0) return byCode;
      return left.message.compareTo(right.message);
    });
  return PackageSurfaceCompilationResult(bundle: null, issues: issues);
}

Map<String, Uint8List> _freezeFileMap(Map<String, List<int>> source) =>
    Map.unmodifiable({
      for (final entry in source.entries)
        entry.key: Uint8List.fromList(entry.value),
    });

Map<String, Uint8List> _copyFileMap(Map<String, Uint8List> source) =>
    Map.unmodifiable({
      for (final entry in source.entries)
        entry.key: Uint8List.fromList(entry.value),
    });

final class _ResolvedArtifact {
  const _ResolvedArtifact({
    required this.rendered,
    required this.source,
    required this.surface,
    required this.blobPath,
    required this.sidecarPath,
    required this.sidecar,
  });

  final CompiledSurfaceArtifact rendered;
  final RestageSourceDeclaration source;
  final Surface surface;
  final String blobPath;
  final String sidecarPath;
  final CapabilitySidecar sidecar;
}

final class _FlowAssembly {
  const _FlowAssembly({
    required this.manifestInput,
    required this.flowDocumentBytes,
  });

  final SurfacePublicationAssemblyInput manifestInput;
  final Uint8List flowDocumentBytes;
}

final class _FlowClosureArtifact {
  const _FlowClosureArtifact({
    required this.artifact,
    required this.id,
  });

  final _ResolvedArtifact artifact;
  final String id;
}

final class _PendingStandalonePart {
  const _PendingStandalonePart({
    required this.partPath,
    required this.source,
    required this.contract,
  });

  final String partPath;
  final RestageSourceDeclaration source;
  final ResolvedStandaloneScreenContract contract;
}

final class _PendingCompatibilityScreenPart {
  const _PendingCompatibilityScreenPart({
    required this.partPath,
    required this.source,
    required this.descriptor,
    required this.id,
    required this.artifactPath,
    required this.version,
    required this.minClient,
    required this.sdkPrefix,
  });

  final String partPath;
  final RestageSourceDeclaration source;
  final String descriptor;
  final String id;
  final String artifactPath;
  final int version;
  final int minClient;
  final String? sdkPrefix;
}

final class _PendingFlowPart {
  const _PendingFlowPart({
    required this.partPath,
    required this.source,
    required this.refName,
    required this.resultName,
    required this.decoderName,
    required this.seedName,
    required this.graph,
    required this.flow,
    required this.sdkPrefix,
    required this.measurementPublicationKey,
  });

  final String partPath;
  final RestageSourceDeclaration source;
  final String refName;
  final String resultName;
  final String decoderName;
  final String seedName;
  final NormalizedFlowGraph graph;
  final NormalizedFlowSource flow;
  final String sdkPrefix;
  final String measurementPublicationKey;
}

final class _PartAccumulator {
  _PartAccumulator({required this.header, required this.fragments});

  final String header;
  final List<String> fragments;
}
