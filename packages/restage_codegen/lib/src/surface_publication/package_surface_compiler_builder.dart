// Package-level production adapter for canonical surface compilation.
// ignore_for_file: public_member_api_docs

import 'dart:convert';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:restage_codegen/src/authored_library_predicate.dart';
import 'package:restage_codegen/src/codegen_builder.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/onboarding/flow_builder.dart';
import 'package:restage_codegen/src/onboarding/flow_definition_frontend.dart';
import 'package:restage_codegen/src/onboarding/screen_builder.dart';
import 'package:restage_codegen/src/paywall_flow_builder.dart';
import 'package:restage_codegen/src/restage_source_roster.dart';
import 'package:restage_codegen/src/restage_source_roster_builder.dart';
import 'package:restage_codegen/src/source_visitor.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/surface_publication/legacy_screen_contract_adapter.dart';
import 'package:restage_codegen/src/surface_publication/output_placement.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler.dart';
import 'package:restage_codegen/src/surface_publication/paywall_artifact_adapter.dart';
import 'package:restage_codegen/src/surface_publication/placement_registry.dart';
import 'package:restage_codegen/src/surface_publication/screen_contract_reference_emitter.dart';
import 'package:restage_shared/restage_shared.dart'
    show
        CapabilityManifest,
        CapabilitySidecar,
        FlowContentHash,
        ScreenArtifact,
        Surface;

const String _authoredDartGlob = 'lib/**.dart';
const JsonEncoder _capabilitySidecarEncoder = JsonEncoder.withIndent('  ');

@immutable
final class TrackedPackageSurfaceCompilation {
  TrackedPackageSurfaceCompilation({
    required this.publicationBundle,
    required Map<String, String> generatedParts,
    required List<Issue> issues,
  })  : generatedParts = Map.unmodifiable(Map.of(generatedParts)),
        issues = List.unmodifiable(issues);

  final RestageSurfacePublicationBundle publicationBundle;
  final Map<String, String> generatedParts;
  final List<Issue> issues;

  bool get isValid => publicationBundle.valid && issues.isEmpty;
}

/// Scans only tracked build assets and invokes the package compiler's resolved
/// frontends and strict artifact adapters.
///
/// [plan] is the calling builder's own resolved placement. Build Runner has
/// no cross-builder options channel, so every placement-affected Restage
/// builder key accepts the same options with the same defaults; two callers
/// resolving different placement for one package is a configuration error and
/// is reported as one.
Future<TrackedPackageSurfaceCompilation> compileTrackedPackageSurfaces(
  BuildStep buildStep, {
  RestageOutputPlacementPlan? plan,
}) async {
  final cache = await buildStep.fetchResource(_trackedCompilationResource);
  return cache.get(
    buildStep,
    plan ?? RestageOutputPlacementPlan.defaults,
  );
}

Future<TrackedPackageSurfaceCompilation> _compileTrackedPackageSurfaces(
  BuildStep buildStep,
  RestageOutputPlacementPlan plan,
) async {
  final issues = <Issue>[];
  // The roster builder owns discovery; this lane consumes that exact production
  // seam.
  // ignore: invalid_use_of_visible_for_testing_member
  final roster = await collectRestageSourceRoster(buildStep, plan: plan);
  issues.addAll(roster.issues);
  if (issues.isNotEmpty) return _invalidCompilation(issues);

  final assets = await buildStep
      .findAssets(Glob(_authoredDartGlob))
      .where(isAuthoredDartLibraryAsset)
      .toList()
    ..sort((left, right) => left.path.compareTo(right.path));
  final flows = <NormalizedFlowSource>[];
  final rendered = <CompiledSurfaceArtifact>[];
  final contracts = <ResolvedStandaloneScreenContract>[];
  final legacyContracts = <LegacyStandaloneScreenContract>[];
  final precompiledFlows = <CompiledFlowArtifact>[];
  final canonicalPaywallJobs = <_CanonicalPaywallJob>[];
  final flowJobs = <_FlowCompilationJob>[];
  final sourcesByLibrary = <String, List<RestageSourceDeclaration>>{};
  for (final source in roster.declarations) {
    sourcesByLibrary.putIfAbsent(source.libraryIdentity, () => []).add(source);
  }
  final sourcesByDeclarationIdentity = _sourcesByDeclarationIdentity(
    roster,
    issues,
  );
  if (issues.isNotEmpty) return _invalidCompilation(issues);
  for (final assetId in assets) {
    final LibraryElement library;
    try {
      library = await buildStep.resolver.libraryFor(
        assetId,
        allowSyntaxErrors: true,
      );
    } on NonLibraryAssetException {
      continue;
    }

    final flowInspection = await inspectFlowDefinitions(
      library,
      assetId,
      legacySurface: _legacySurfaceFor(assetId.path),
    );
    issues.addAll(flowInspection.issues);
    flows.addAll(flowInspection.flows);
    if (flowInspection.flows.any((flow) => flow.graph == null)) {
      flowJobs.add(
        _FlowCompilationJob(
          assetId: assetId,
          library: library,
          flows: flowInspection.flows,
        ),
      );
    }

    final screenInspection = await inspectCanonicalScreenDeclarations(
      library,
      assetId,
    );
    issues.addAll(screenInspection.issues);
    if (screenInspection.screens.isNotEmpty) {
      final compilation = await compileResolvedScreens(
        buildStep,
        screenInspection.screens,
      );
      issues.addAll(compilation.issues);
      for (final screen in compilation.screens) {
        final capabilities = _effectiveScreenCapabilities(
          authoredMinClient: screen.input.minClient,
          derivedCapabilities: screen.capabilities,
        );
        final capabilitySidecar = _effectiveCapabilitySidecar(
          existing: screen.capabilitySidecar,
          blob: screen.blob,
          derivedCapabilities: screen.capabilities,
          effectiveCapabilities: capabilities,
        );
        rendered.add(
          CompiledSurfaceArtifact(
            declaration: screen.input.declaration,
            blob: screen.blob,
            capabilitySidecar: capabilitySidecar,
            flowArtifactPath: '${screen.input.id}.rfw',
            rfwText: utf8.encode(screen.text),
          ),
        );
        final surface = screen.input.surface;
        if (surface == null) continue;
        // Hashed once here, from the exact same bytes that become this
        // library's bundle entries two lines above — never a second,
        // independent serialization of the same content. Only needed when
        // this package resolves bundled_runtime: true; the emitter fails
        // loudly rather than silently omitting the locator in that case.
        final bundleEntryMetadata = ResolvedScreenBundleEntryMetadata(
          blobSha256: CapabilitySidecar.hashBlob(screen.blob),
          blobByteLength: screen.blob.length,
          sidecarSha256: CapabilitySidecar.hashBlob(capabilitySidecar),
          sidecarByteLength: capabilitySidecar.length,
        );
        final contract = inspectStandaloneScreenContract(
          ResolvedStandaloneScreenContractInput(
            assetId: assetId,
            screen: screen.input.declaration,
            surface: surface,
            slug: screen.input.id,
            contractVersion: screen.input.version,
            capabilities: capabilities,
            plan: plan,
            bundleEntryMetadata: bundleEntryMetadata,
          ),
        );
        issues.addAll(contract.issues);
        if (contract.contract != null) contracts.add(contract.contract!);
      }
    }

    for (final source in sourcesByLibrary[library.identifier] ??
        const <RestageSourceDeclaration>[]) {
      if (source.kind != RestageRosterSourceKind.screen || source.isCanonical) {
        continue;
      }
      final declaration = _resolvedClassForSource(library, source);
      if (declaration == null) {
        issues.add(_lostDeclarationIssue(source));
        continue;
      }
      final blob = await _readClaimBytes(
        buildStep,
        source,
        roles: const {'binary'},
        issues: issues,
      );
      final sidecarBytes = await _readClaimBytes(
        buildStep,
        source,
        roles: const {'capability'},
        issues: issues,
      );
      final text = await _readClaimBytes(
        buildStep,
        source,
        roles: const {'text'},
        issues: issues,
      );
      if (blob == null || sidecarBytes == null || text == null) continue;
      final sidecar = _decodeCapabilitySidecar(
        sidecarBytes,
        source: source,
        issues: issues,
      );
      if (sidecar == null || source.surface == null) continue;
      rendered.add(
        CompiledSurfaceArtifact(
          declaration: declaration,
          blob: blob,
          capabilitySidecar: sidecarBytes,
          flowArtifactPath: '${source.effectiveId}.rfw',
          rfwText: text,
        ),
      );
      final contract = inspectLegacyStandaloneScreenContract(
        LegacyStandaloneScreenContractInput(
          assetId: assetId,
          screen: declaration,
          surface: source.surface!,
          slug: source.effectiveId,
          contractVersion: source.version,
          capabilities: sidecar.manifest,
        ),
      );
      issues.addAll(contract.issues);
      if (contract.contract != null) legacyContracts.add(contract.contract!);
    }

    final paywalls = await visitPaywallSources(library, assetId);
    issues.addAll(paywalls.issues);
    final canonicalPaywalls = paywalls.sources
        .where((source) => source.isCanonical)
        .toList(growable: false);
    if (canonicalPaywalls.isNotEmpty) {
      canonicalPaywallJobs.add(
        _CanonicalPaywallJob(
          assetId: assetId,
          library: library,
          sources: canonicalPaywalls,
        ),
      );
    }
    for (final paywall
        in paywalls.sources.where((source) => !source.isCanonical)) {
      final declaration = library.classes
          .where((candidate) => candidate.name == paywall.className)
          .firstOrNull;
      if (declaration == null) {
        issues.add(
          Issue(
            code: IssueCode.analyzerResolutionFailed,
            message: 'Legacy paywall ${paywall.id} lost its resolved class '
                'identity during package compilation.',
            location: '${assetId.path}#${paywall.className}',
          ),
        );
        continue;
      }
      try {
        final facts = await PaywallArtifactAdapter.readForSource(
          buildStep,
          paywall,
        );
        rendered.add(
          CompiledSurfaceArtifact.fromPaywallAdapter(
            declaration: declaration,
            facts: facts,
            flowArtifactPath: p.posix.basename(facts.adapter.blob.path),
          ),
        );
      } on Object catch (error) {
        issues.add(
          Issue(
            code: IssueCode.missingScreenDescriptor,
            message: 'Legacy paywall ${paywall.id} has an incomplete '
                'compiled artifact family: $error',
            location: '${assetId.path}#${paywall.className}',
          ),
        );
      }
    }
  }

  await _compileCanonicalPaywalls(
    buildStep,
    jobs: canonicalPaywallJobs,
    rendered: rendered,
    sourcesByDeclarationIdentity: sourcesByDeclarationIdentity,
    issues: issues,
  );
  final classFlowScreens = <ResolvedClassFlowScreen>[];
  for (final artifact in rendered) {
    final source = sourcesByDeclarationIdentity[artifact.declarationIdentity];
    if (source == null) {
      issues.add(
        Issue(
          code: IssueCode.analyzerResolutionFailed,
          message: 'Rendered source ${artifact.declarationIdentity} is absent '
              'from the source roster during class-flow compilation.',
          location: artifact.declarationIdentity,
        ),
      );
      continue;
    }
    final sidecar = _decodeCapabilitySidecar(
      artifact.capabilitySidecar,
      source: source,
      issues: issues,
    );
    if (sidecar == null) continue;
    classFlowScreens.add(
      ResolvedClassFlowScreen(
        declaration: artifact.declaration,
        surface: source.surface,
        id: artifact.flowScreenId ?? source.effectiveId,
        artifactPath: artifact.flowArtifactPath,
        version: source.version,
        minClient: sidecar.manifest.builtInFloor,
        blob: artifact.blob,
        canonicalPaywallId:
            source.kind == RestageRosterSourceKind.paywall && source.isCanonical
                ? source.effectiveId
                : null,
      ),
    );
  }

  if (issues.isEmpty) {
    await _compileCanonicalClassFlowDocuments(
      buildStep,
      flows: flows,
      jobs: flowJobs,
      screens: classFlowScreens,
      sourcesByDeclarationIdentity: sourcesByDeclarationIdentity,
      precompiledFlows: precompiledFlows,
      issues: issues,
    );
  }
  for (final job in flowJobs) {
    final classFlows =
        job.flows.where((flow) => flow.graph == null).toList(growable: false);
    for (final flow in classFlows.where((flow) => !flow.isCanonical)) {
      final source = sourcesByDeclarationIdentity[flow.declarationIdentity];
      if (source == null) {
        issues.add(
          Issue(
            code: IssueCode.analyzerResolutionFailed,
            message: 'Legacy flow ${flow.declarationIdentity} is absent from '
                'the source roster during package compilation.',
            location: flow.declarationIdentity,
          ),
        );
        continue;
      }
      final bytes = await _readClaimBytes(
        buildStep,
        source,
        roles: const {'flow'},
        issues: issues,
      );
      if (bytes == null) continue;
      // The flow document is borrowed from the per-surface builder's exact
      // emitted bytes, so those never move. Only the generated reference is
      // recompiled here, because a library's one generated part has a single
      // writer and this is the channel that reaches it.
      final recompiled = await compileResolvedClassFlows(
        buildStep,
        library: job.library,
        assetId: job.assetId,
        legacySurface: flow.surface,
        includeCanonical: false,
        declarationIdentities: {flow.declarationIdentity},
      );
      precompiledFlows.add(
        CompiledFlowArtifact(
          declaration: flow.declaration,
          flowDocumentBytes: bytes,
          generatedPart: recompiled.flows.length == 1
              ? recompiled.flows.single.generatedPart
              : null,
        ),
      );
    }
  }

  if (issues.isNotEmpty) return _invalidCompilation(issues);
  final result = compilePackageSurfacePublications(
    PackageSurfaceCompilationInput(
      roster: roster,
      flows: flows,
      renderedSources: rendered,
      standaloneScreens: contracts,
      legacyStandaloneScreens: legacyContracts,
      precompiledFlows: precompiledFlows,
    ),
  );
  issues.addAll(result.issues);
  final bundle = result.bundle;
  if (issues.isNotEmpty || bundle == null) return _invalidCompilation(issues);
  final manifestFiles = bundle.manifestFiles;
  final aggregateOwnedManifestFiles = bundle.aggregateOwnedManifestFiles;
  final ownedOutputs = <String, List<int>>{
    for (final entry in bundle.aggregateOwnedOutputFiles.entries)
      if (!manifestFiles.containsKey(entry.key)) entry.key: entry.value,
  };
  for (final entry in bundle.generatedParts.entries) {
    if (ownedOutputs.containsKey(entry.key)) {
      throw StateError(
        'Package surface compilation produced two ancillary outputs at '
        '${entry.key}.',
      );
    }
    ownedOutputs[entry.key] = utf8.encode(entry.value);
  }
  return TrackedPackageSurfaceCompilation(
    publicationBundle: RestageSurfacePublicationBundle.valid(
      manifest: bundle.manifest,
      artifacts: aggregateOwnedManifestFiles,
      borrowedArtifacts: bundle.borrowedManifestFiles,
      ownedOutputs: ownedOutputs,
      artifactLibraryPaths: bundle.artifactLibraryPaths,
    ),
    generatedParts: bundle.generatedParts,
    issues: const [],
  );
}

final Resource<_TrackedCompilationCache> _trackedCompilationResource =
    Resource<_TrackedCompilationCache>(_TrackedCompilationCache.new);

final class _TrackedCompilationCache {
  final Map<String, Future<TrackedPackageSurfaceCompilation>> _byPackage = {};

  Future<TrackedPackageSurfaceCompilation> get(
    BuildStep buildStep,
    RestageOutputPlacementPlan plan,
  ) async {
    await registerRestagePlacementSignature(buildStep, plan);
    return _byPackage.putIfAbsent(
      buildStep.inputId.package,
      () => _compileTrackedPackageSurfaces(buildStep, plan),
    );
  }
}

/// Fixed aggregate builder consumed by the outputs builder, which owns bundle
/// and artifact placement.
@internal
final class PackageSurfaceCompilerBuilder implements Builder {
  const PackageSurfaceCompilerBuilder(this.options);

  final BuilderOptions options;

  @override
  Map<String, List<String>> get buildExtensions => const {
        r'$package$': [kRestageSurfacePublicationCompilerBundlePath],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final compilation = await compileTrackedPackageSurfaces(
      buildStep,
      plan: RestageOutputPlacementPlan.fromBuilderOptions(options),
    );
    for (final issue in compilation.issues) {
      log.severe(issue.toLogString());
    }
    await buildStep.writeAsString(
      AssetId(
        buildStep.inputId.package,
        kRestageSurfacePublicationCompilerBundlePath,
      ),
      compilation.publicationBundle.encodeCanonicalJson(),
    );
  }
}

Future<void> _compileCanonicalClassFlowDocuments(
  BuildStep buildStep, {
  required List<NormalizedFlowSource> flows,
  required List<_FlowCompilationJob> jobs,
  required List<ResolvedClassFlowScreen> screens,
  required Map<String, RestageSourceDeclaration> sourcesByDeclarationIdentity,
  required List<CompiledFlowArtifact> precompiledFlows,
  required List<Issue> issues,
}) async {
  final hasCanonicalClassFlow = jobs.any(
    (job) => job.flows.any(
      (flow) => flow.isCanonical && flow.graph == null,
    ),
  );
  if (!hasCanonicalClassFlow) return;

  final canonicalByIdentity = <NormalizedFlowIdentity, NormalizedFlowSource>{};
  for (final flow in flows.where((flow) => flow.isCanonical)) {
    final previous = canonicalByIdentity[flow.identity];
    if (previous != null &&
        previous.declarationIdentity != flow.declarationIdentity) {
      issues.add(
        Issue(
          code: IssueCode.duplicateId,
          message: 'Canonical flow identity ${flow.surface.wireName}/'
              '${flow.id} resolves to more than one analyzer declaration.',
          location: flow.declarationIdentity,
        ),
      );
      continue;
    }
    canonicalByIdentity[flow.identity] = flow;
  }

  final jobsByDeclarationIdentity = <String, _FlowCompilationJob>{};
  final dependenciesByDeclarationIdentity =
      <String, ResolvedClassFlowDependency>{};
  for (final job in jobs) {
    final classFlows = job.flows
        .where((flow) => flow.isCanonical && flow.graph == null)
        .toList(growable: false);
    if (classFlows.isEmpty) continue;
    final dependencyResult = await inspectResolvedClassFlowDependencies(
      library: job.library,
      assetId: job.assetId,
      legacySurface: classFlows.first.surface,
      includeLegacy: false,
    );
    issues.addAll(dependencyResult.issues);
    for (final dependency in dependencyResult.flows) {
      final previous =
          dependenciesByDeclarationIdentity[dependency.declarationIdentity];
      if (previous != null) {
        issues.add(
          Issue(
            code: IssueCode.duplicateId,
            message: 'Class-shaped flow ${dependency.declarationIdentity} '
                'was inspected more than once.',
            location: job.assetId.path,
          ),
        );
        continue;
      }
      dependenciesByDeclarationIdentity[dependency.declarationIdentity] =
          dependency;
      jobsByDeclarationIdentity[dependency.declarationIdentity] = job;
    }
  }
  if (issues.isNotEmpty) return;

  for (final flow in canonicalByIdentity.values) {
    final dependencies = flow.graph?.childFlows.keys ??
        dependenciesByDeclarationIdentity[flow.declarationIdentity]
            ?.childIdentities;
    if (dependencies == null) {
      issues.add(
        Issue(
          code: IssueCode.analyzerResolutionFailed,
          message: 'Class-shaped flow ${flow.declarationIdentity} lost its '
              'resolved dependency set during aggregate compilation.',
          location: flow.declarationIdentity,
        ),
      );
      continue;
    }
    for (final dependency in dependencies) {
      if (canonicalByIdentity.containsKey(dependency)) continue;
      issues.add(
        Issue(
          code: IssueCode.missingScreenDescriptor,
          message: 'Flow ${flow.surface.wireName}/${flow.id} references '
              'unavailable aggregate child flow '
              '${dependency.surface.wireName}/${dependency.id}.',
          location: flow.declarationIdentity,
        ),
      );
    }
  }
  if (issues.isNotEmpty) return;

  final documents = <NormalizedFlowIdentity, List<int>>{};
  final pending = Map<NormalizedFlowIdentity, NormalizedFlowSource>.of(
    canonicalByIdentity,
  );
  while (pending.isNotEmpty) {
    var madeProgress = false;
    final ordered = pending.values.toList()
      ..sort((left, right) {
        final bySurface =
            left.surface.wireName.compareTo(right.surface.wireName);
        return bySurface != 0 ? bySurface : left.id.compareTo(right.id);
      });
    for (final flow in ordered) {
      final dependencies = flow.graph?.childFlows.keys ??
          dependenciesByDeclarationIdentity[flow.declarationIdentity]!
              .childIdentities;
      if (!dependencies.every(documents.containsKey)) continue;

      if (flow.graph != null) {
        final source = sourcesByDeclarationIdentity[flow.declarationIdentity];
        if (source == null) {
          issues.add(
            Issue(
              code: IssueCode.analyzerResolutionFailed,
              message: 'Canonical flow ${flow.declarationIdentity} is '
                  'absent from the source roster.',
              location: flow.declarationIdentity,
            ),
          );
          continue;
        }
        final artifacts = _screenArtifactsForNormalizedFlow(
          flow,
          screens,
          sourcesByDeclarationIdentity,
          issues,
        );
        if (artifacts == null) continue;
        final compilation = compileCanonicalFlowArtifact(
          flow: flow,
          source: source,
          screenArtifacts: artifacts,
          childFlowDocuments: documents,
        );
        issues.addAll(compilation.issues);
        final bytes = compilation.compilation?.flowDocumentBytes;
        if (bytes == null) continue;
        documents[flow.identity] = bytes;
      } else {
        final job = jobsByDeclarationIdentity[flow.declarationIdentity];
        if (job == null) {
          issues.add(
            Issue(
              code: IssueCode.analyzerResolutionFailed,
              message: 'Class-shaped flow ${flow.declarationIdentity} lost '
                  'its aggregate compilation job.',
              location: flow.declarationIdentity,
            ),
          );
          continue;
        }
        final compilation = await compileResolvedClassFlows(
          buildStep,
          library: job.library,
          assetId: job.assetId,
          legacySurface: flow.surface,
          includeLegacy: false,
          resolvedScreens: screens,
          childFlowDocuments: documents,
          declarationIdentities: {flow.declarationIdentity},
        );
        issues.addAll(compilation.issues);
        if (compilation.flows.length != 1) {
          if (compilation.issues.isEmpty) {
            issues.add(
              Issue(
                code: IssueCode.analyzerResolutionFailed,
                message: 'Expected exactly one aggregate class-flow '
                    'document for ${flow.declarationIdentity}; found '
                    '${compilation.flows.length}.',
                location: flow.declarationIdentity,
              ),
            );
          }
          continue;
        }
        final compiled = compilation.flows.single;
        documents[flow.identity] = compiled.flowDocumentBytes;
        precompiledFlows.add(
          CompiledFlowArtifact(
            declaration: compiled.declaration,
            flowDocumentBytes: compiled.flowDocumentBytes,
            generatedPart: compiled.generatedPart,
          ),
        );
      }
      pending.remove(flow.identity);
      madeProgress = true;
    }
    if (issues.isNotEmpty) return;
    if (madeProgress) continue;

    final blocked = pending.keys.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    issues.add(
      Issue(
        code: IssueCode.unsupportedFlowRuntimeFeature,
        message: 'Canonical subflow cycle prevents aggregate compilation of '
            '${blocked.map(
                  (identity) => '${identity.surface.wireName}/${identity.id}',
                ).join(', ')}.',
        location: blocked.first.key,
      ),
    );
    return;
  }
}

Map<String, ScreenArtifact>? _screenArtifactsForNormalizedFlow(
  NormalizedFlowSource flow,
  List<ResolvedClassFlowScreen> screens,
  Map<String, RestageSourceDeclaration> sourcesByDeclarationIdentity,
  List<Issue> issues,
) {
  final result = <String, ScreenArtifact>{};
  for (final reference in flow.graph!.screens.values) {
    final candidates = screens
        .where(
          (screen) =>
              screen.declarationIdentity == reference.declarationIdentity,
        )
        .toList(growable: false);
    if (candidates.length != 1) {
      issues.add(
        Issue(
          code: IssueCode.missingScreenDescriptor,
          message: 'Flow ${flow.id} screen ${reference.id} must resolve to '
              'one exact aggregate artifact for '
              '${reference.declarationIdentity}; found ${candidates.length}.',
          location: flow.declarationIdentity,
        ),
      );
      continue;
    }
    final screen = candidates.single;
    final source = sourcesByDeclarationIdentity[reference.declarationIdentity];
    if (source == null) {
      issues.add(
        Issue(
          code: IssueCode.missingScreenDescriptor,
          message: 'Flow ${flow.id} screen ${reference.id} is absent from '
              'the aggregate source roster.',
          location: flow.declarationIdentity,
        ),
      );
      continue;
    }
    final sourceKindMatches = reference.isPaywall
        ? source.kind == RestageRosterSourceKind.paywall &&
            screen.canonicalPaywallId == source.effectiveId
        : source.kind == RestageRosterSourceKind.screen &&
            source.effectiveId == reference.id &&
            screen.canonicalPaywallId == null;
    if (!source.isCanonical ||
        source.declarationIdentity != reference.declarationIdentity ||
        !sourceKindMatches ||
        screen.id != reference.id ||
        source.version != reference.version ||
        source.minClient != reference.minClient ||
        screen.version != source.version ||
        screen.minClient < source.minClient) {
      issues.add(
        Issue(
          code: IssueCode.annotationEvaluationFailed,
          message: 'Flow ${flow.id} screen ${reference.id} does not match '
              'its roster-owned authored identity, version, or minimum '
              'client facts.',
          location: flow.declarationIdentity,
        ),
      );
      continue;
    }
    result[reference.id] = ScreenArtifact(
      path: screen.artifactPath,
      version: screen.version,
      schemaVersion: 1,
      minClient: screen.minClient,
      contentHash: FlowContentHash.compute(screen.blob),
    );
  }
  return issues.isEmpty ? result : null;
}

Future<void> _compileCanonicalPaywalls(
  BuildStep buildStep, {
  required List<_CanonicalPaywallJob> jobs,
  required List<CompiledSurfaceArtifact> rendered,
  required Map<String, RestageSourceDeclaration> sourcesByDeclarationIdentity,
  required List<Issue> issues,
}) async {
  String? canonicalPaywallIdFor(ClassElement declaration) {
    final identity =
        '${declaration.library.identifier}#${declaration.name ?? '<unnamed>'}';
    final source = sourcesByDeclarationIdentity[identity];
    if (source == null ||
        source.kind != RestageRosterSourceKind.paywall ||
        !source.isCanonical) {
      return null;
    }
    return source.effectiveId;
  }

  final compiledById = <String, _CanonicalCompiledPaywall>{};
  for (final job in jobs) {
    final compilation = await compileResolvedPaywalls(
      buildStep,
      library: job.library,
      assetId: job.assetId,
      sources: job.sources,
      canonicalPaywallIdFor: canonicalPaywallIdFor,
    );
    issues.addAll(compilation.issues);
    for (final compiled in compilation.paywalls) {
      final declaration = job.library.classes
          .where(
            (candidate) => candidate.name == compiled.source.className,
          )
          .firstOrNull;
      if (declaration == null) {
        issues.add(
          Issue(
            code: IssueCode.analyzerResolutionFailed,
            message: 'Canonical paywall ${compiled.source.id} lost its '
                'resolved class identity during package compilation.',
            location: '${job.assetId.path}#${compiled.source.className}',
          ),
        );
        continue;
      }
      final previous = compiledById[compiled.source.id];
      if (previous != null) {
        issues.add(
          Issue(
            code: IssueCode.duplicateId,
            message: 'Canonical paywall id ${compiled.source.id} resolves '
                'to more than one analyzer declaration.',
            location: job.assetId.path,
          ),
        );
        continue;
      }
      compiledById[compiled.source.id] = _CanonicalCompiledPaywall(
        assetId: job.assetId,
        declaration: declaration,
        artifacts: compiled,
      );
    }
  }
  if (issues.isNotEmpty) return;

  final navigation = compilePaywallNavigationFlows(
    packageName: buildStep.inputId.package,
    sourceAssets: {
      for (final entry in compiledById.entries) entry.key: entry.value.assetId,
    },
    navigationPlans: {
      for (final entry in compiledById.entries)
        if (entry.value.artifacts.navigationPlan case final plan?)
          entry.key: plan,
    },
    adapterBlobs: {
      for (final entry in compiledById.entries)
        entry.key: entry.value.artifacts.adapterBlob,
    },
    adapterCapabilitySidecars: {
      for (final entry in compiledById.entries)
        entry.key: entry.value.artifacts.adapterCapabilitySidecar,
    },
  );
  issues.addAll(navigation.issues);
  if (issues.isNotEmpty) return;

  final adapterFiles = <String, List<int>>{
    for (final entry in compiledById.entries)
      'assets/paywalls/screens/paywall_${entry.key}.rfw':
          entry.value.artifacts.adapterBlob,
    for (final entry in compiledById.entries)
      'assets/paywalls/screens/paywall_${entry.key}.capability.json':
          entry.value.artifacts.adapterCapabilitySidecar,
  };
  for (final entry in compiledById.entries) {
    final id = entry.key;
    final compiled = entry.value.artifacts;
    final files = <String, List<int>>{...adapterFiles};
    final standaloneBlob = compiled.standaloneBlob;
    final standaloneSidecar = compiled.standaloneCapabilitySidecar;
    if ((standaloneBlob == null) != (standaloneSidecar == null)) {
      issues.add(
        Issue(
          code: IssueCode.missingScreenDescriptor,
          message: 'Canonical paywall $id emitted a partial standalone '
              'artifact pair.',
          location: entry.value.assetId.path,
        ),
      );
      continue;
    }
    if (standaloneBlob != null && standaloneSidecar != null) {
      files['assets/paywalls/$id.rfw'] = standaloneBlob;
      files['assets/paywalls/$id.capability.json'] = standaloneSidecar;
    }
    final flowBytes = navigation.documents[id];
    if (flowBytes != null) files['assets/paywalls/$id.flow.json'] = flowBytes;
    try {
      final facts = PaywallArtifactAdapter.fromFiles(
        slug: id,
        standaloneBlobPath: 'assets/paywalls/$id.rfw',
        standaloneCapabilityPath: 'assets/paywalls/$id.capability.json',
        adapterBlobPath: 'assets/paywalls/screens/paywall_$id.rfw',
        adapterCapabilityPath:
            'assets/paywalls/screens/paywall_$id.capability.json',
        flowDocumentPath: 'assets/paywalls/$id.flow.json',
        files: files,
      );
      rendered.add(
        CompiledSurfaceArtifact.fromPaywallAdapter(
          declaration: entry.value.declaration,
          facts: facts,
          flowArtifactPath: 'paywall_$id.rfw',
          rfwText: compiled.standaloneText == null
              ? null
              : utf8.encode(compiled.standaloneText!),
          navigationPlan: compiled.navigationPlan,
        ),
      );
    } on Object catch (error) {
      issues.add(
        Issue(
          code: IssueCode.missingScreenDescriptor,
          message: 'Canonical paywall $id has an incomplete compiled '
              'artifact family: $error',
          location: entry.value.assetId.path,
        ),
      );
    }
  }
}

Map<String, RestageSourceDeclaration> _sourcesByDeclarationIdentity(
  RestageSourceRoster roster,
  List<Issue> issues,
) {
  final result = <String, RestageSourceDeclaration>{};
  for (final source in roster.declarations) {
    final previous = result[source.declarationIdentity];
    if (previous == null) {
      result[source.declarationIdentity] = source;
      continue;
    }
    issues.add(
      Issue(
        code: IssueCode.duplicateId,
        message: 'Source roster contains multiple declarations for resolved '
            'identity ${source.declarationIdentity}.',
        location: source.span.location,
      ),
    );
  }
  return result;
}

CapabilityManifest _effectiveScreenCapabilities({
  required int authoredMinClient,
  required CapabilityManifest derivedCapabilities,
}) {
  final effectiveFloor = authoredMinClient > derivedCapabilities.builtInFloor
      ? authoredMinClient
      : derivedCapabilities.builtInFloor;
  return CapabilityManifest(
    builtInFloor: effectiveFloor,
    requiredLibraries: derivedCapabilities.requiredLibraries,
  );
}

List<int> _effectiveCapabilitySidecar({
  required List<int> existing,
  required List<int> blob,
  required CapabilityManifest derivedCapabilities,
  required CapabilityManifest effectiveCapabilities,
}) {
  if (derivedCapabilities.builtInFloor == effectiveCapabilities.builtInFloor) {
    return existing;
  }
  return utf8.encode(
    _capabilitySidecarEncoder.convert(
      CapabilitySidecar(
        blobSha256: CapabilitySidecar.hashBlob(blob),
        manifest: effectiveCapabilities,
      ).toJson(),
    ),
  );
}

ClassElement? _resolvedClassForSource(
  LibraryElement library,
  RestageSourceDeclaration source,
) =>
    library.classes
        .where(
          (candidate) =>
              '${library.identifier}#${candidate.name ?? '<unnamed>'}' ==
              source.declarationIdentity,
        )
        .firstOrNull;

Issue _lostDeclarationIssue(RestageSourceDeclaration source) => Issue(
      code: IssueCode.analyzerResolutionFailed,
      message: 'Roster source ${source.effectiveId} lost its analyzer-resolved '
          'declaration identity during package compilation.',
      location: source.span.location,
    );

Future<List<int>?> _readClaimBytes(
  BuildStep buildStep,
  RestageSourceDeclaration source, {
  required Set<String> roles,
  required List<Issue> issues,
}) async {
  final paths = source.outputs
      .where((output) => roles.contains(output.role))
      .map((output) => output.path)
      .toSet()
      .toList()
    ..sort();
  if (paths.length != 1) {
    issues.add(
      Issue(
        code: IssueCode.missingScreenDescriptor,
        message: 'Roster source ${source.effectiveId} requires exactly one '
            '${roles.toList()..sort()} output; found ${paths.length}.',
        location: source.span.location,
      ),
    );
    return null;
  }
  final id = AssetId(buildStep.inputId.package, paths.single);
  if (!await buildStep.canRead(id)) {
    issues.add(
      Issue(
        code: IssueCode.missingScreenDescriptor,
        message: 'Roster source ${source.effectiveId} is missing generated '
            'output ${id.path}.',
        location: source.span.location,
      ),
    );
    return null;
  }
  return buildStep.readAsBytes(id);
}

CapabilitySidecar? _decodeCapabilitySidecar(
  List<int> bytes, {
  required RestageSourceDeclaration source,
  required List<Issue> issues,
}) {
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) throw const FormatException('expected JSON object');
    return CapabilitySidecar.fromJson(Map<String, dynamic>.from(decoded));
  } on Object catch (error) {
    issues.add(
      Issue(
        code: IssueCode.malformedTranslatorOutput,
        message: 'Invalid capability sidecar for ${source.effectiveId}: '
            '$error',
        location: source.span.location,
      ),
    );
    return null;
  }
}

final class _CanonicalPaywallJob {
  const _CanonicalPaywallJob({
    required this.assetId,
    required this.library,
    required this.sources,
  });

  final AssetId assetId;
  final LibraryElement library;
  final List<PaywallSourceFound> sources;
}

final class _FlowCompilationJob {
  const _FlowCompilationJob({
    required this.assetId,
    required this.library,
    required this.flows,
  });

  final AssetId assetId;
  final LibraryElement library;
  final List<NormalizedFlowSource> flows;
}

final class _CanonicalCompiledPaywall {
  const _CanonicalCompiledPaywall({
    required this.assetId,
    required this.declaration,
    required this.artifacts,
  });

  final AssetId assetId;
  final ClassElement declaration;
  final CompiledPaywallArtifacts artifacts;
}

TrackedPackageSurfaceCompilation _invalidCompilation(List<Issue> rawIssues) {
  final issues = List<Issue>.of(rawIssues)
    ..sort((left, right) {
      final byLocation = left.location.compareTo(right.location);
      if (byLocation != 0) return byLocation;
      final byCode = left.code.name.compareTo(right.code.name);
      if (byCode != 0) return byCode;
      return left.message.compareTo(right.message);
    });
  return TrackedPackageSurfaceCompilation(
    publicationBundle: RestageSurfacePublicationBundle.invalid(
      issues.map((issue) => issue.toLogString()),
    ),
    generatedParts: const {},
    issues: issues,
  );
}

Surface? _legacySurfaceFor(String path) {
  final segments = p.posix.split(path);
  if (segments.length < 3 || segments.first != 'lib') return null;
  return switch (segments[1]) {
    'onboarding' => Surface.onboarding,
    'message' => Surface.message,
    'survey' => Surface.survey,
    _ => null,
  };
}
