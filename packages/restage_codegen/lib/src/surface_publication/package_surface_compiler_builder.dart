// Package-level production adapter for canonical surface compilation.
// ignore_for_file: public_member_api_docs

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:restage_codegen/src/analytics_id_control.dart';
import 'package:restage_codegen/src/catalog_loader.dart';
import 'package:restage_codegen/src/codegen_builder.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_codegen/src/measurement/measurement_configuration.dart';
import 'package:restage_codegen/src/measurement/measurement_publication_planner.dart';
import 'package:restage_codegen/src/measurement/measurement_route_emission.dart';
import 'package:restage_codegen/src/measurement/measurement_source_discovery.dart';
import 'package:restage_codegen/src/onboarding/flow_builder.dart';
import 'package:restage_codegen/src/onboarding/flow_definition_frontend.dart';
import 'package:restage_codegen/src/onboarding/onboarding_helpers.dart';
import 'package:restage_codegen/src/onboarding/onboarding_source_visitor.dart';
import 'package:restage_codegen/src/onboarding/screen_builder.dart';
import 'package:restage_codegen/src/paywall_flow_builder.dart';
import 'package:restage_codegen/src/production_helpers.dart';
import 'package:restage_codegen/src/restage_source_prefilter.dart';
import 'package:restage_codegen/src/restage_source_roster.dart';
import 'package:restage_codegen/src/restage_source_roster_builder.dart';
import 'package:restage_codegen/src/source_visitor.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/surface_publication/legacy_screen_contract_adapter.dart';
import 'package:restage_codegen/src/surface_publication/output_placement.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler.dart';
import 'package:restage_codegen/src/surface_publication/paywall_artifact_adapter.dart';
import 'package:restage_codegen/src/surface_publication/placement_registry.dart';
import 'package:restage_codegen/src/surface_publication/preserved_outputs.dart';
import 'package:restage_codegen/src/surface_publication/screen_contract_reference_emitter.dart';
import 'package:restage_codegen/src/widget_classifier.dart';
import 'package:restage_shared/restage_shared.dart'
    show
        CapabilityManifest,
        CapabilitySidecar,
        FlowContentHash,
        ScreenArtifact,
        Surface,
        SurfacePayloadKind,
        SurfacePublicationArtifactRole,
        SurfacePublicationManifest,
        SurfaceSourceKind;
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

const JsonEncoder _capabilitySidecarEncoder = JsonEncoder.withIndent('  ');

@immutable
final class TrackedPackageSurfaceCompilation {
  TrackedPackageSurfaceCompilation({
    required this.publicationBundle,
    required this.measurementCompilerOutput,
    required this.analyticsIdControlOutput,
    required Map<String, String> generatedParts,
    required List<Issue> issues,
  })  : generatedParts = Map.unmodifiable(Map.of(generatedParts)),
        issues = List.unmodifiable(issues);

  final RestageSurfacePublicationBundle publicationBundle;
  final RestageMeasurementCompilerOutputV1 measurementCompilerOutput;
  final AnalyticsIdControlOutputV1 analyticsIdControlOutput;
  final Map<String, String> generatedParts;
  final List<Issue> issues;

  bool get isValid => publicationBundle.valid && issues.isEmpty;
}

final class _AppFactoryNoticeCensus {
  final Map<String, Issue> _canonicalIssues = {};
  final Set<String> _deprecatedKeys = {};

  void add(Issue issue, bool isCanonical) {
    final key = issue.buildNoticeKey;
    if (!isCanonical) {
      _deprecatedKeys.add(key);
      return;
    }
    final existing = _canonicalIssues[key];
    if (existing == null ||
        issue.toLogString().compareTo(existing.toLogString()) < 0) {
      _canonicalIssues[key] = issue;
    }
  }

  void emit(Set<String> buildNoticeKeys) {
    final keys = _canonicalIssues.keys
        .where((key) => !_deprecatedKeys.contains(key))
        .toList()
      ..sort();
    for (final key in keys) {
      logBuildNoticeOnce(log, buildNoticeKeys, _canonicalIssues[key]!);
    }
  }
}

/// Scans only tracked build assets and invokes the package compiler's resolved
/// frontends and strict artifact adapters.
///
/// [plan] is the calling builder's own resolved placement, and [builderKey]
/// is its `build.yaml` key (diagnostics only). Build Runner has no
/// cross-builder options channel, so every placement-affected Restage
/// builder key accepts the same options with the same defaults; two callers
/// resolving different placement for one package is a configuration error and
/// is reported as one, naming both keys.
Future<TrackedPackageSurfaceCompilation> compileTrackedPackageSurfaces(
  BuildStep buildStep, {
  required String builderKey,
  required MeasurementCompilerPolicyInput measurementPolicy,
  RestageOutputPlacementPlan? plan,
}) async {
  final cache = await buildStep.fetchResource(_trackedCompilationResource);
  return cache.get(
    buildStep,
    plan ?? RestageOutputPlacementPlan.defaults,
    measurementPolicy,
    builderKey: builderKey,
  );
}

Future<TrackedPackageSurfaceCompilation> _compileTrackedPackageSurfaces(
  BuildStep buildStep,
  RestageOutputPlacementPlan plan,
  MeasurementCompilerPolicyInput measurementPolicy,
  bool measurementEnabled,
) async {
  final issues = <Issue>[];
  final buildNoticeKeys = <String>{};
  final appFactoryNotices = _AppFactoryNoticeCensus();
  // One selection, shared with the roster below: this compiler and the roster
  // cannot disagree about which libraries can declare a surface, and the
  // package's sources are read once instead of twice.
  final assets = await selectRestageSurfaceCandidates(buildStep);
  // The roster builder owns discovery; this compiler consumes that exact
  // production seam.
  // ignore: invalid_use_of_visible_for_testing_member
  final roster = await collectRestageSourceRoster(
    buildStep,
    plan: plan,
    candidates: assets,
  );
  issues.addAll(roster.issues);
  if (issues.isNotEmpty) return _invalidCompilation(issues);
  final flows = <NormalizedFlowSource>[];
  final rendered = <CompiledSurfaceArtifact>[];
  final contracts = <ResolvedStandaloneScreenContract>[];
  final legacyContracts = <LegacyStandaloneScreenContract>[];
  final precompiledFlows = <CompiledFlowArtifact>[];
  final paywallJobs = <_PaywallCompilationJob>[];
  final measurementScreenInputs = <ResolvedScreenCompilationInput>[];
  final provisionalAnalyticsIdControlCaptures = <AnalyticsIdControlCapture>[];
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
    measurementScreenInputs.addAll(screenInspection.screens);
    if (screenInspection.screens.isNotEmpty) {
      final compilation = await compileResolvedScreens(
        buildStep,
        screenInspection.screens,
        buildNoticeKeys: buildNoticeKeys,
        appFactoryNoticeCollector: appFactoryNotices.add,
      );
      issues.addAll(compilation.issues);
      for (final screen in compilation.screens) {
        provisionalAnalyticsIdControlCaptures.addAll(
          screen.analyticsIdDeclarations.map(
            (declaration) => AnalyticsIdControlCapture(
              sourceDeclarationIdentity: screen.input.declarationIdentity,
              capture: declaration,
            ),
          ),
        );
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
        final source =
            sourcesByDeclarationIdentity[screen.input.declarationIdentity];
        if (source == null) {
          issues.add(
            Issue(
              code: IssueCode.analyzerResolutionFailed,
              message: 'Compiled screen lost its roster source.',
              location: screen.input.declarationIdentity,
            ),
          );
          continue;
        }
        rendered.add(
          CompiledSurfaceArtifact(
            declaration: screen.input.declaration,
            blob: screen.blob,
            capabilitySidecar: capabilitySidecar,
            flowArtifactPath: '${screen.input.id}.rfw',
            rfwText: utf8.encode(screen.text),
            rfwCatalogOccurrenceSetsByOutputRole:
                _rfwCatalogOccurrenceSetsForSourceOutputRoles(
              source: source,
              outputRoles: const {'screen-blob', 'binary'},
              occurrenceSet: screen.rfwCatalogOccurrenceSet,
            ),
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
            rootParams: screen.input.build.rootParams,
            constructorParams: screen.input.build.constructorParams,
            mountConstructorProblem: screen.input.build.mountConstructorProblem,
            plan: plan,
            bundleEntryMetadata: bundleEntryMetadata,
          ),
        );
        issues.addAll(contract.issues);
        final resolved = contract.contract;
        if (resolved != null) {
          final message = resolved.mountOmissionMessage;
          if (message != null) log.warning(message);
          contracts.add(resolved);
        }
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
      final visited = await visitOnboardingSources(library, assetId);
      issues.addAll(visited.issues);
      final legacySource = visited.sources
          .where((candidate) => candidate.className == declaration.name)
          .firstOrNull;
      if (legacySource == null) {
        issues.add(
          Issue(
            code: IssueCode.analyzerResolutionFailed,
            message: 'Legacy screen ${source.effectiveId} has no resolved '
                'RFW occurrence evidence.',
            location: source.declarationIdentity,
          ),
        );
        continue;
      }
      final legacyInput = ResolvedScreenCompilationInput(
        assetId: assetId,
        declaration: declaration,
        id: legacySource.id,
        version: legacySource.version,
        minClient: legacySource.minClient,
        surface: source.surface,
        build: legacySource.build,
        isCanonical: false,
      );
      measurementScreenInputs.add(legacyInput);
      final legacyCompilation = await compileResolvedScreens(
        buildStep,
        [legacyInput],
        buildNoticeKeys: buildNoticeKeys,
        appFactoryNoticeCollector: appFactoryNotices.add,
      );
      issues.addAll(legacyCompilation.issues);
      if (legacyCompilation.screens.length != 1) continue;
      final legacyOccurrenceSet =
          legacyCompilation.screens.single.rfwCatalogOccurrenceSet;
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
          rfwCatalogOccurrenceSetsByOutputRole:
              _rfwCatalogOccurrenceSetsForSourceOutputRoles(
            source: source,
            outputRoles: const {'screen-blob', 'binary'},
            occurrenceSet: legacyOccurrenceSet,
          ),
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
    if (paywalls.sources.isNotEmpty) {
      paywallJobs.add(
        _PaywallCompilationJob(
          assetId: assetId,
          library: library,
          sources: paywalls.sources,
        ),
      );
    }
    for (final paywall in paywalls.sources.where(
      (source) => !source.isCanonical,
    )) {
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

  await _compilePaywalls(
    buildStep,
    jobs: paywallJobs,
    retainSource: (source) => source.isCanonical,
    rendered: rendered,
    sourcesByDeclarationIdentity: sourcesByDeclarationIdentity,
    analyticsIdControlCaptures: provisionalAnalyticsIdControlCaptures,
    issues: issues,
    buildNoticeKeys: buildNoticeKeys,
    appFactoryNoticeCollector: appFactoryNotices.add,
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
          generatedTopLevelSymbols: recompiled.flows.length == 1
              ? recompiled.flows.single.generatedTopLevelSymbols
              : const {},
        ),
      );
    }
  }

  if (issues.isNotEmpty) {
    appFactoryNotices.emit(buildNoticeKeys);
    return _invalidCompilation(issues);
  }
  final frozenRfwCatalogOccurrenceSetsByArtifactPath =
      _rfwCatalogOccurrenceSetsByArtifactPath(
    roster: roster,
    renderedSources: rendered,
  );
  final provisionalResult = compilePackageSurfacePublications(
    PackageSurfaceCompilationInput(
      roster: roster,
      flows: flows,
      renderedSources: rendered,
      standaloneScreens: contracts,
      legacyStandaloneScreens: legacyContracts,
      precompiledFlows: precompiledFlows,
      rfwCatalogOccurrenceSetsByArtifactPath:
          frozenRfwCatalogOccurrenceSetsByArtifactPath,
    ),
  );
  issues.addAll(provisionalResult.issues);
  final provisionalBundle = provisionalResult.bundle;
  if (issues.isNotEmpty || provisionalBundle == null) {
    appFactoryNotices.emit(buildNoticeKeys);
    return _invalidCompilation(issues);
  }
  if (!measurementEnabled) {
    appFactoryNotices.emit(buildNoticeKeys);
    return _validCompilation(
      provisionalBundle,
      RestageMeasurementCompilerOutputV1.empty(),
      AnalyticsIdControlOutputV1(
        packageName: buildStep.inputId.package,
        publications: const [],
      ),
    );
  }
  final priorMeasurementOutput = await _readPriorMeasurementOutput(
    buildStep,
    issues,
  );
  if (priorMeasurementOutput == null) {
    appFactoryNotices.emit(buildNoticeKeys);
    return _invalidCompilation(issues);
  }
  final catalog = await loadMergedCatalog(buildStep);
  final discoveries = await _discoverMeasurementSources(
    buildStep,
    screens: measurementScreenInputs,
    paywallJobs: paywallJobs,
    catalog: catalog,
    issues: issues,
  );
  final publicationInputs = _measurementPlanningInputs(
    provisionalBundle.manifest,
    roster: roster,
    discoveriesByDeclarationIdentity: discoveries,
    rfwCatalogOccurrenceSetsByArtifactPath:
        frozenRfwCatalogOccurrenceSetsByArtifactPath,
    issues: issues,
  );
  _validateFlowMeasurementClosures(
    publicationInputs,
    flows: flows,
    issues: issues,
  );
  if (issues.isNotEmpty) {
    appFactoryNotices.emit(buildNoticeKeys);
    return _invalidCompilation(
      issues,
      measurementCompilerOutput: priorMeasurementOutput,
    );
  }
  final measurementAssembly = MeasurementPublicationPlanner.plan(
    publications: publicationInputs,
    priorOutput: priorMeasurementOutput,
    policy: measurementPolicy,
  );
  if (!measurementAssembly.isValid) {
    final measurementIssues = [
      for (final error in measurementAssembly.errors)
        Issue(
          code: IssueCode.annotationEvaluationFailed,
          message: error,
          location: kRestageMeasurementCompilerOutputPath,
        ),
    ];
    appFactoryNotices.emit(buildNoticeKeys);
    return _invalidCompilation(
      measurementIssues,
      measurementCompilerOutput: RestageMeasurementCompilerOutputV1(
        valid: false,
        errors: measurementAssembly.errors,
        policy: measurementPolicy,
        nextIdentitySequence: measurementAssembly.nextIdentitySequence,
        ledgerNodes: measurementAssembly.ledgerNodes,
        acceptedRelocations: priorMeasurementOutput.acceptedRelocations,
        acceptedIntroductions: measurementAssembly.pendingIntroductions,
        proposals: measurementAssembly.proposals,
        publications: const [],
      ),
    );
  }

  final emissionPlans = <String, MeasurementRouteEmissionPlan>{};
  for (final publication in publicationInputs) {
    final routePlan =
        measurementAssembly.routePlansByKey[publication.selector.key];
    if (routePlan == null) continue;
    for (final sourceArtifact in publication.sourceArtifacts) {
      final identity =
          sourceArtifact.discovery.sourceProvenance!.resolvedSourceIdentity;
      final plan = MeasurementRouteEmissionPlan.fromDiscovery(
        discovery: sourceArtifact.discovery,
        routePlan: routePlan,
        codeIdentityByStructuralOccurrenceKey:
            measurementAssembly.codeIdentityByStructuralOccurrenceKey,
      );
      emissionPlans.putIfAbsent(identity, () => plan);
    }
  }
  final paywallRouteOwnership = _paywallRouteOwnership(
    publicationInputs,
    roster: roster,
    issues: issues,
  );
  final frozenRfwCatalogOccurrenceSetsByDeclarationIdentity =
      _rfwCatalogOccurrenceSetsByDeclarationIdentity(rendered);
  final frozenScreenRfwCatalogOccurrenceSetsByDeclarationIdentity =
      _rfwCatalogOccurrenceSetsForOutputRoles(
    frozenRfwCatalogOccurrenceSetsByDeclarationIdentity,
    const {'screen-blob', 'binary'},
  );
  final frozenPaywallAdapterRfwCatalogOccurrenceSetsByDeclarationIdentity =
      _rfwCatalogOccurrenceSetsForOutputRoles(
    frozenRfwCatalogOccurrenceSetsByDeclarationIdentity,
    const {'flow-screen-blob', 'flow-screen-binary'},
  );

  final finalRendered = <CompiledSurfaceArtifact>[];
  final finalAnalyticsIdControlCaptures = <AnalyticsIdControlCapture>[];
  final finalContracts = <ResolvedStandaloneScreenContract>[];
  final finalLegacyContracts = <LegacyStandaloneScreenContract>[];
  await _appendResolvedScreens(
    buildStep,
    inputs: measurementScreenInputs,
    routePlans: emissionPlans,
    rfwCatalogOccurrenceSetsByDeclarationIdentity:
        frozenScreenRfwCatalogOccurrenceSetsByDeclarationIdentity,
    placement: plan,
    rendered: finalRendered,
    contracts: finalContracts,
    legacyContracts: finalLegacyContracts,
    sourcesByDeclarationIdentity: sourcesByDeclarationIdentity,
    analyticsIdControlCaptures: finalAnalyticsIdControlCaptures,
    issues: issues,
    buildNoticeKeys: buildNoticeKeys,
    appFactoryNoticeCollector: appFactoryNotices.add,
  );
  await _compilePaywalls(
    buildStep,
    jobs: paywallJobs,
    rendered: finalRendered,
    sourcesByDeclarationIdentity: sourcesByDeclarationIdentity,
    measurementRoutePlans: emissionPlans,
    measurementRouteOwnership: paywallRouteOwnership,
    adapterRfwCatalogOccurrenceSetsByDeclarationIdentity:
        frozenPaywallAdapterRfwCatalogOccurrenceSetsByDeclarationIdentity,
    standaloneRfwCatalogOccurrenceSetsByDeclarationIdentity:
        frozenScreenRfwCatalogOccurrenceSetsByDeclarationIdentity,
    analyticsIdControlCaptures: finalAnalyticsIdControlCaptures,
    issues: issues,
    buildNoticeKeys: buildNoticeKeys,
    appFactoryNoticeCollector: appFactoryNotices.add,
  );
  appFactoryNotices.emit(buildNoticeKeys);
  final finalClassFlowScreens = _resolvedClassFlowScreens(
    finalRendered,
    sourcesByDeclarationIdentity: sourcesByDeclarationIdentity,
    issues: issues,
  );
  final finalPrecompiledFlows = <CompiledFlowArtifact>[];
  if (issues.isEmpty) {
    await _compileCanonicalClassFlowDocuments(
      buildStep,
      flows: flows,
      jobs: flowJobs,
      screens: finalClassFlowScreens,
      sourcesByDeclarationIdentity: sourcesByDeclarationIdentity,
      precompiledFlows: finalPrecompiledFlows,
      issues: issues,
    );
    await _compileLegacyClassFlowDocuments(
      buildStep,
      jobs: flowJobs,
      screens: finalClassFlowScreens,
      sourcesByDeclarationIdentity: sourcesByDeclarationIdentity,
      precompiledFlows: finalPrecompiledFlows,
      issues: issues,
    );
  }
  if (issues.isNotEmpty) {
    return _invalidCompilation(
      issues,
      measurementCompilerOutput: priorMeasurementOutput,
    );
  }

  final finalizedDraftResult = compilePackageSurfacePublications(
    PackageSurfaceCompilationInput(
      roster: roster,
      flows: flows,
      renderedSources: finalRendered,
      standaloneScreens: finalContracts,
      legacyStandaloneScreens: finalLegacyContracts,
      precompiledFlows: finalPrecompiledFlows,
      measurementRoutePlansByPublicationKey:
          measurementAssembly.routePlansByKey,
      measurementPresentationPlansByPublicationKey:
          measurementAssembly.presentationPlansByKey,
      rfwCatalogOccurrenceSetsByArtifactPath:
          frozenRfwCatalogOccurrenceSetsByArtifactPath,
    ),
  );
  issues.addAll(finalizedDraftResult.issues);
  final finalizedDraftBundle = finalizedDraftResult.bundle;
  if (issues.isNotEmpty || finalizedDraftBundle == null) {
    return _invalidCompilation(
      issues,
      measurementCompilerOutput: priorMeasurementOutput,
    );
  }

  final carrierDraftDigestsByPublicationKey = <String, String>{
    for (final publication in finalizedDraftBundle.measurementPublications)
      if (publication.draft.routes.isNotEmpty ||
          publication.draft.presentationRoutes.isNotEmpty)
        publication.selector.key: publication.draft.canonicalDigest.hex,
  };
  final carrierDraftDigestsByDeclarationIdentity =
      _measurementCarrierDraftDigestsByDeclarationIdentity(
    roster: roster,
    carrierDraftDigestsByPublicationKey: carrierDraftDigestsByPublicationKey,
  );
  final carrierPrecompiledFlows = <CompiledFlowArtifact>[];
  if (issues.isEmpty) {
    await _compileCanonicalClassFlowDocuments(
      buildStep,
      flows: flows,
      jobs: flowJobs,
      screens: finalClassFlowScreens,
      sourcesByDeclarationIdentity: sourcesByDeclarationIdentity,
      precompiledFlows: carrierPrecompiledFlows,
      generatedSourceCarrierDraftDigestsByDeclarationIdentity:
          carrierDraftDigestsByDeclarationIdentity,
      issues: issues,
    );
    await _compileLegacyClassFlowDocuments(
      buildStep,
      jobs: flowJobs,
      screens: finalClassFlowScreens,
      sourcesByDeclarationIdentity: sourcesByDeclarationIdentity,
      precompiledFlows: carrierPrecompiledFlows,
      generatedSourceCarrierDraftDigestsByDeclarationIdentity:
          carrierDraftDigestsByDeclarationIdentity,
      issues: issues,
    );
  }
  if (issues.isNotEmpty) {
    return _invalidCompilation(
      issues,
      measurementCompilerOutput: priorMeasurementOutput,
    );
  }

  final result = compilePackageSurfacePublications(
    PackageSurfaceCompilationInput(
      roster: roster,
      flows: flows,
      renderedSources: finalRendered,
      standaloneScreens: finalContracts,
      legacyStandaloneScreens: finalLegacyContracts,
      precompiledFlows: carrierPrecompiledFlows,
      measurementRoutePlansByPublicationKey:
          measurementAssembly.routePlansByKey,
      measurementPresentationPlansByPublicationKey:
          measurementAssembly.presentationPlansByKey,
      rfwCatalogOccurrenceSetsByArtifactPath:
          frozenRfwCatalogOccurrenceSetsByArtifactPath,
      generatedSourceCarrierDraftDigestsByPublicationKey:
          carrierDraftDigestsByPublicationKey,
    ),
  );
  issues.addAll(result.issues);
  final bundle = result.bundle;
  if (issues.isNotEmpty || bundle == null) {
    return _invalidCompilation(
      issues,
      measurementCompilerOutput: priorMeasurementOutput,
    );
  }
  final measurementCompilerOutput = RestageMeasurementCompilerOutputV1(
    valid: true,
    errors: const [],
    policy: measurementPolicy,
    nextIdentitySequence: measurementAssembly.nextIdentitySequence,
    ledgerNodes: measurementAssembly.ledgerNodes,
    acceptedRelocations: priorMeasurementOutput.acceptedRelocations,
    acceptedIntroductions: measurementAssembly.pendingIntroductions,
    proposals: const [],
    publications: bundle.measurementPublications,
  );
  if (!_sameAnalyticsIdControlCaptures(
    provisionalAnalyticsIdControlCaptures,
    finalAnalyticsIdControlCaptures,
  )) {
    issues.add(
      Issue(
        code: IssueCode.invalidAnalyticsId,
        message: 'analyticsId captures changed between frozen and final RFW '
            'compilation.',
        location: buildStep.inputId.path,
      ),
    );
  }
  if (issues.isNotEmpty) {
    return _invalidCompilation(
      issues,
      measurementCompilerOutput: priorMeasurementOutput,
    );
  }
  final analyticsIdControl = buildAnalyticsIdControlOutput(
    packageName: buildStep.inputId.package,
    scopes: _analyticsIdControlScopes(measurementCompilerOutput),
    captures: finalAnalyticsIdControlCaptures,
    presentationMaterializations:
        bundle.measurementPresentationMaterializations,
    location: buildStep.inputId.path,
  );
  issues.addAll(analyticsIdControl.issues);
  if (issues.isNotEmpty) {
    return _invalidCompilation(
      issues,
      measurementCompilerOutput: priorMeasurementOutput,
    );
  }
  return _validCompilation(
    bundle,
    measurementCompilerOutput,
    analyticsIdControl.output,
  );
}

bool _sameAnalyticsIdControlCaptures(
  Iterable<AnalyticsIdControlCapture> first,
  Iterable<AnalyticsIdControlCapture> second,
) {
  Map<(String, fmt.RfwCatalogOccurrenceHandle, String), int> counts(
    Iterable<AnalyticsIdControlCapture> values,
  ) {
    final result = <(String, fmt.RfwCatalogOccurrenceHandle, String), int>{};
    for (final value in values) {
      final key = (
        value.sourceDeclarationIdentity,
        value.capture.presentationHandle,
        value.capture.analyticsId,
      );
      result.update(key, (count) => count + 1, ifAbsent: () => 1);
    }
    return result;
  }

  final firstCounts = counts(first);
  final secondCounts = counts(second);
  if (firstCounts.length != secondCounts.length) return false;
  return firstCounts.entries.every(
    (entry) => secondCounts[entry.key] == entry.value,
  );
}

Map<String, String> _measurementCarrierDraftDigestsByDeclarationIdentity({
  required RestageSourceRoster roster,
  required Map<String, String> carrierDraftDigestsByPublicationKey,
}) {
  final result = <String, String>{};
  for (final source in roster.declarations) {
    MeasurementPublicationSelectorV1? selector;
    switch (source.kind) {
      case RestageRosterSourceKind.screen:
        final surface = source.surface;
        if (surface != null) {
          selector = MeasurementPublicationSelectorV1(
            surface: surface,
            slug: source.effectiveId,
            sourceKind: SurfaceSourceKind.screen,
            contractVersion: source.version,
          );
        }
      case RestageRosterSourceKind.flow:
        final surface = source.surface;
        if (surface != null) {
          selector = MeasurementPublicationSelectorV1(
            surface: surface,
            slug: source.effectiveId,
            sourceKind: SurfaceSourceKind.flowGraph,
          );
        }
      case RestageRosterSourceKind.paywall:
        // Paywalls carry their exact provenance on the resolved payload path,
        // not on a generated Dart descriptor.
        break;
    }
    final digest = selector == null
        ? null
        : carrierDraftDigestsByPublicationKey[selector.key];
    if (digest != null) result[source.declarationIdentity] = digest;
  }
  return Map<String, String>.unmodifiable(result);
}

List<AnalyticsIdControlPublicationScope> _analyticsIdControlScopes(
  RestageMeasurementCompilerOutputV1 output,
) =>
    List<AnalyticsIdControlPublicationScope>.unmodifiable([
      for (final publication in output.publications)
        AnalyticsIdControlPublicationScope.fromCompilerPublication(publication),
    ]);

TrackedPackageSurfaceCompilation _validCompilation(
  PackageSurfaceCompilationBundle bundle,
  RestageMeasurementCompilerOutputV1 measurementCompilerOutput,
  AnalyticsIdControlOutputV1 analyticsIdControlOutput,
) {
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
    measurementCompilerOutput: measurementCompilerOutput,
    analyticsIdControlOutput: analyticsIdControlOutput,
    generatedParts: bundle.generatedParts,
    issues: const [],
  );
}

final Resource<_TrackedCompilationCache> _trackedCompilationResource =
    Resource<_TrackedCompilationCache>(_TrackedCompilationCache.new);

final class _TrackedCompilationCache {
  final Map<String, Future<TrackedPackageSurfaceCompilation>> _byPackage = {};
  final Map<String, Future<MeasurementConfigurationResult>>
      _measurementConfigurationByPackage = {};
  final Map<String, ({String cacheKey, String builderKey})>
      _measurementPolicyByPackage = {};

  Future<TrackedPackageSurfaceCompilation> get(
    BuildStep buildStep,
    RestageOutputPlacementPlan plan,
    MeasurementCompilerPolicyInput measurementPolicy, {
    required String builderKey,
  }) async {
    await registerRestagePlacementSignature(
      buildStep,
      plan,
      builderKey: builderKey,
    );
    final package = buildStep.inputId.package;
    final measurementConfigurationCandidates =
        await selectRestageMeasurementConfigurationCandidates(buildStep);
    // Every consumer registers these inputs, including on cache hits.
    await registerMeasurementConfigurationDependencies(
      buildStep,
      measurementConfigurationCandidates,
    );
    final measurementConfiguration =
        await _measurementConfigurationByPackage.putIfAbsent(
      package,
      () => resolveMeasurementConfiguration(
        buildStep,
        candidates: measurementConfigurationCandidates,
      ),
    );
    if (!measurementConfiguration.isValid) {
      return _invalidCompilation(measurementConfiguration.issues);
    }
    final policyKey = measurementPolicy.cacheKey;
    final registeredPolicy = _measurementPolicyByPackage.putIfAbsent(
      package,
      () => (cacheKey: policyKey, builderKey: builderKey),
    );
    if (registeredPolicy.cacheKey != policyKey) {
      return _invalidCompilation([
        Issue(
          code: IssueCode.conflictingTargetConfig,
          message: 'Measurement policy options conflict for package $package: '
              '${registeredPolicy.builderKey} resolved '
              '[${registeredPolicy.cacheKey}] while '
              '$builderKey resolved [$policyKey]. Every Restage builder key '
              'for a package must carry identical Measurement policy options.',
          location: package,
        ),
      ]);
    }
    return _byPackage.putIfAbsent(
      package,
      () => _compileTrackedPackageSurfaces(
        buildStep,
        plan,
        measurementPolicy,
        measurementConfiguration.enabled,
      ),
    );
  }
}

typedef MeasurementCompilerLedgerWriter = Future<void> Function({
  required String package,
  required RestageMeasurementCompilerOutputV1 output,
});

/// Fixed aggregate builder consumed by the outputs builder, which owns bundle
/// and artifact placement.
@internal
final class PackageSurfaceCompilerBuilder implements Builder {
  const PackageSurfaceCompilerBuilder(
    this.options, {
    MeasurementCompilerLedgerWriter ledgerWriter =
        _persistMeasurementCompilerLedgerSource,
    PriorGeneratedOutputReader priorOutputReader = readPriorGeneratedOutputs,
  })  : _ledgerWriter = ledgerWriter,
        _priorOutputReader = priorOutputReader;

  final BuilderOptions options;
  final MeasurementCompilerLedgerWriter _ledgerWriter;
  final PriorGeneratedOutputReader _priorOutputReader;

  @override
  Map<String, List<String>> get buildExtensions => const {
        r'$package$': [
          kRestageSurfacePublicationCompilerBundlePath,
          kRestageMeasurementCompilerOutputPath,
          kRestageAnalyticsIdControlOutputPath,
        ],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final plan = RestageOutputPlacementPlan.fromBuilderOptions(options);
    final compilation = await compileTrackedPackageSurfaces(
      buildStep,
      plan: plan,
      measurementPolicy: MeasurementCompilerPolicyInput.fromBuilderOptions(
        options,
      ),
      builderKey: 'restage_codegen:restage_package_surface_compiler',
    );
    for (final issue in compilation.issues) {
      log.severe(issue.toLogString());
    }
    if (compilation.isValid) {
      await _ledgerWriter(
        package: buildStep.inputId.package,
        output: compilation.measurementCompilerOutput,
      );
    } else {
      // A refused build materializes nothing, so the outputs it would
      // otherwise lose are captured here for the builders that own them.
      final preserved = await buildStep.fetchResource(
        restagePreservedOutputsResource,
      );
      preserved.capture(
        buildStep.inputId.package,
        await _priorOutputReader(buildStep.inputId.package, plan),
      );
    }
    await Future.wait([
      buildStep.writeAsString(
        AssetId(
          buildStep.inputId.package,
          kRestageSurfacePublicationCompilerBundlePath,
        ),
        compilation.publicationBundle.encodeCanonicalJson(),
      ),
      buildStep.writeAsString(
        AssetId(
          buildStep.inputId.package,
          kRestageMeasurementCompilerOutputPath,
        ),
        compilation.measurementCompilerOutput.encodeCanonicalJson(),
      ),
      buildStep.writeAsString(
        AssetId(
          buildStep.inputId.package,
          kRestageAnalyticsIdControlOutputPath,
        ),
        compilation.analyticsIdControlOutput.encodeJson(),
      ),
    ]);
  }
}

Future<RestageMeasurementCompilerOutputV1?> _readPriorMeasurementOutput(
  BuildStep buildStep,
  List<Issue> issues,
) async {
  final asset = AssetId(
    buildStep.inputId.package,
    kRestageMeasurementCompilerLedgerSourcePath,
  );
  if (!await buildStep.canRead(asset)) {
    return RestageMeasurementCompilerOutputV1.empty();
  }
  try {
    final output = RestageMeasurementCompilerOutputV1.fromCanonicalBytes(
      await buildStep.readAsBytes(asset),
    );
    if (!output.valid) {
      throw const FormatException(
        'The committed Measurement ledger source must be a valid compiler '
        'state. Resolve its proposals without replacing the last valid state.',
      );
    }
    return output;
  } on Object catch (error) {
    issues.add(
      Issue(
        code: IssueCode.malformedTranslatorOutput,
        message: 'The build-owned Measurement compiler state is invalid: '
            '$error',
        location: kRestageMeasurementCompilerLedgerSourcePath,
      ),
    );
    return null;
  }
}

Future<void> _persistMeasurementCompilerLedgerSource({
  required String package,
  required RestageMeasurementCompilerOutputV1 output,
}) async {
  final packageLib = await Isolate.resolvePackageUri(
    Uri.parse('package:$package/'),
  );
  if (packageLib == null || packageLib.scheme != 'file') return;
  final root = packageLib.resolve('../');
  final file = File.fromUri(
    root.resolve(kRestageMeasurementCompilerLedgerSourcePath),
  );
  writeMeasurementCompilerLedgerSource(
    file: file,
    bytes: output.canonicalBytes,
  );
}

@visibleForTesting
void writeMeasurementCompilerLedgerSource({
  required File file,
  required List<int> bytes,
  int? processId,
}) {
  if (file.existsSync()) {
    final existing = file.readAsBytesSync();
    if (existing.length == bytes.length &&
        existing.indexed.every((entry) => bytes[entry.$1] == entry.$2)) {
      return;
    }
  }
  file.parent.createSync(recursive: true);
  final temporary = File('${file.path}.tmp.${processId ?? pid}');
  try {
    temporary
      ..writeAsBytesSync(bytes, flush: true)
      ..renameSync(file.path);
  } finally {
    if (temporary.existsSync()) temporary.deleteSync();
  }
}

Future<Map<String, MeasurementSourceDiscoveryResult>>
    _discoverMeasurementSources(
  BuildStep buildStep, {
  required List<ResolvedScreenCompilationInput> screens,
  required List<_PaywallCompilationJob> paywallJobs,
  required Catalog catalog,
  required List<Issue> issues,
}) async {
  final discoveries = <String, MeasurementSourceDiscoveryResult>{};

  Future<void> addDiscovery({
    required String declarationIdentity,
    required MeasurementSourceDiscoveryInput input,
  }) async {
    final discovery = MeasurementSourceDiscovery.discover(input);
    if (discovery.disposition !=
        MeasurementSourceDiscoveryDisposition.accepted) {
      // Omitting the whole surface preserves its unmeasured output.
      log.warning(
        'Measurement is unavailable for $declarationIdentity: '
        '${discovery.rejectionReason}. The surface compiles unmeasured.',
      );
      return;
    }
    if (discoveries.putIfAbsent(declarationIdentity, () => discovery) !=
        discovery) {
      issues.add(
        Issue(
          code: IssueCode.duplicateId,
          message: 'Measurement source discovery repeated resolved '
              'declaration $declarationIdentity.',
          location: declarationIdentity,
        ),
      );
    }
  }

  if (screens.isNotEmpty) {
    final helpers = HelperRegistry()..registerAll(onboardingHelpers);
    final classification = await classifyReferencedCustomWidgets(
      rootExpressions: screens.expand((screen) => screen.build.collectorRoots),
      catalog: catalog,
      helpers: helpers,
      astNodeFor: (fragment) =>
          buildStep.resolver.astNodeFor(fragment, resolve: true),
    );
    for (final screen in screens) {
      await addDiscovery(
        declarationIdentity: screen.declarationIdentity,
        input: MeasurementSourceDiscoveryInput(
          authority: MeasurementSourceAuthority.screen,
          sourceClass: screen.declaration,
          rootExpression: screen.build.rootExpression,
          catalog: catalog,
          inlinedCustomWidgetBlueprints: classification.blueprints,
          inlinedCustomWidgetCollectionRefusals:
              classification.collectionRefusals,
          rootLocalBindings: screen.build.localBindings,
        ),
      );
    }
  }

  if (paywallJobs.isNotEmpty) {
    final helpers = productionPaywallHelperRegistry();
    final sources = [
      for (final job in paywallJobs)
        for (final source in job.sources) (job: job, source: source),
    ];
    final classification = await classifyReferencedCustomWidgets(
      rootExpressions:
          sources.expand((entry) => entry.source.build.collectorRoots),
      catalog: catalog,
      helpers: helpers,
      astNodeFor: (fragment) =>
          buildStep.resolver.astNodeFor(fragment, resolve: true),
    );
    for (final entry in sources) {
      final declaration = entry.job.library.classes
          .where(
            (candidate) => candidate.name == entry.source.className,
          )
          .firstOrNull;
      if (declaration == null) {
        issues.add(
          Issue(
            code: IssueCode.analyzerResolutionFailed,
            message: 'Measurement discovery lost paywall class '
                '${entry.source.className}.',
            location: entry.job.assetId.path,
          ),
        );
        continue;
      }
      final identity =
          '${entry.job.library.identifier}#${entry.source.className}';
      await addDiscovery(
        declarationIdentity: identity,
        input: MeasurementSourceDiscoveryInput(
          authority: MeasurementSourceAuthority.paywall,
          sourceClass: declaration,
          rootExpression: entry.source.rootExpression,
          catalog: catalog,
          inlinedCustomWidgetBlueprints: classification.blueprints,
          inlinedCustomWidgetCollectionRefusals:
              classification.collectionRefusals,
          rootLocalBindings: entry.source.build.localBindings,
        ),
      );
    }
  }
  return discoveries;
}

Map<String, fmt.ResolvedRfwCatalogOccurrenceSet>
    _rfwCatalogOccurrenceSetsByArtifactPath({
  required RestageSourceRoster roster,
  required Iterable<CompiledSurfaceArtifact> renderedSources,
}) {
  final sourcesByDeclarationIdentity = {
    for (final source in roster.declarations)
      source.declarationIdentity: source,
  };
  final occurrenceSets = <String, fmt.ResolvedRfwCatalogOccurrenceSet>{};
  for (final rendered in renderedSources) {
    final source = sourcesByDeclarationIdentity[rendered.declarationIdentity];
    if (source == null) continue;
    for (final output in source.outputs) {
      final occurrenceSet =
          rendered.rfwCatalogOccurrenceSetsByOutputRole[output.role];
      if (occurrenceSet == null) continue;
      final existing = occurrenceSets.putIfAbsent(
        output.path,
        () => occurrenceSet,
      );
      if (!identical(existing, occurrenceSet)) {
        throw StateError(
          'One emitted RFW artifact path has conflicting frozen occurrences',
        );
      }
    }
  }
  return Map.unmodifiable(occurrenceSets);
}

Map<String, Map<String, fmt.ResolvedRfwCatalogOccurrenceSet>>
    _rfwCatalogOccurrenceSetsByDeclarationIdentity(
  Iterable<CompiledSurfaceArtifact> renderedSources,
) {
  final occurrenceSets =
      <String, Map<String, fmt.ResolvedRfwCatalogOccurrenceSet>>{};
  for (final rendered in renderedSources) {
    final byRole = occurrenceSets.putIfAbsent(
      rendered.declarationIdentity,
      () => <String, fmt.ResolvedRfwCatalogOccurrenceSet>{},
    );
    for (final entry in rendered.rfwCatalogOccurrenceSetsByOutputRole.entries) {
      final existing = byRole.putIfAbsent(entry.key, () => entry.value);
      if (!identical(existing, entry.value)) {
        throw StateError(
          'One source declaration output role has conflicting frozen RFW '
          'occurrences',
        );
      }
    }
  }
  return Map<String,
      Map<String, fmt.ResolvedRfwCatalogOccurrenceSet>>.unmodifiable(
    <String, Map<String, fmt.ResolvedRfwCatalogOccurrenceSet>>{
      for (final entry in occurrenceSets.entries)
        entry.key:
            Map<String, fmt.ResolvedRfwCatalogOccurrenceSet>.unmodifiable(
          entry.value,
        ),
    },
  );
}

Map<String, fmt.ResolvedRfwCatalogOccurrenceSet>
    _rfwCatalogOccurrenceSetsForOutputRoles(
  Map<String, Map<String, fmt.ResolvedRfwCatalogOccurrenceSet>>
      occurrenceSetsByDeclarationIdentity,
  Set<String> outputRoles,
) {
  final result = <String, fmt.ResolvedRfwCatalogOccurrenceSet>{};
  for (final entry in occurrenceSetsByDeclarationIdentity.entries) {
    final matches = entry.value.entries
        .where((role) => outputRoles.contains(role.key))
        .toList(growable: false);
    if (matches.isEmpty) continue;
    if (matches.length != 1) {
      throw StateError(
        'One source declaration has multiple frozen RFW sets for one '
        'resolved output form',
      );
    }
    result[entry.key] = matches.single.value;
  }
  return Map<String, fmt.ResolvedRfwCatalogOccurrenceSet>.unmodifiable(result);
}

Map<String, fmt.ResolvedRfwCatalogOccurrenceSet>
    _rfwCatalogOccurrenceSetsForSourceOutputRoles({
  required RestageSourceDeclaration source,
  required Set<String> outputRoles,
  required fmt.ResolvedRfwCatalogOccurrenceSet occurrenceSet,
}) {
  final matches = source.outputs
      .where((output) => outputRoles.contains(output.role))
      .toList(growable: false);
  if (matches.isEmpty) return const {};
  return Map<String, fmt.ResolvedRfwCatalogOccurrenceSet>.unmodifiable({
    for (final output in matches) output.role: occurrenceSet,
  });
}

Map<String, fmt.ResolvedRfwCatalogOccurrenceSet>
    _rfwCatalogOccurrenceSetsForPaywallOutputRoles({
  required RestageSourceDeclaration source,
  required fmt.ResolvedRfwCatalogOccurrenceSet adapterOccurrenceSet,
  fmt.ResolvedRfwCatalogOccurrenceSet? standaloneOccurrenceSet,
}) {
  final result = <String, fmt.ResolvedRfwCatalogOccurrenceSet>{
    ..._rfwCatalogOccurrenceSetsForSourceOutputRoles(
      source: source,
      outputRoles: const {'flow-screen-blob', 'flow-screen-binary'},
      occurrenceSet: adapterOccurrenceSet,
    ),
  };
  if (standaloneOccurrenceSet != null) {
    result.addAll(
      _rfwCatalogOccurrenceSetsForSourceOutputRoles(
        source: source,
        outputRoles: const {'screen-blob', 'binary'},
        occurrenceSet: standaloneOccurrenceSet,
      ),
    );
  }
  return Map.unmodifiable(result);
}

/// Output roles that can appear as a screen-blob publication artifact.
const _measurementScreenBlobOutputRoles = <String>{
  'screen-blob',
  'binary',
  'flow-screen-blob',
  'flow-screen-binary',
};

List<MeasurementPublicationPlanningInput> _measurementPlanningInputs(
  SurfacePublicationManifest manifest, {
  required RestageSourceRoster roster,
  required Map<String, MeasurementSourceDiscoveryResult>
      discoveriesByDeclarationIdentity,
  required Map<String, fmt.ResolvedRfwCatalogOccurrenceSet>
      rfwCatalogOccurrenceSetsByArtifactPath,
  required List<Issue> issues,
}) {
  final sourcesByOutputPath = <String, RestageSourceDeclaration>{};
  for (final source in roster.declarations.where(
    (source) =>
        source.kind == RestageRosterSourceKind.screen ||
        source.kind == RestageRosterSourceKind.paywall,
  )) {
    // Other outputs can share a generated part and are never looked up here.
    for (final output in source.outputs.where(
      (output) => _measurementScreenBlobOutputRoles.contains(output.role),
    )) {
      final previous = sourcesByOutputPath[output.path];
      if (previous != null &&
          previous.declarationIdentity != source.declarationIdentity) {
        issues.add(
          Issue(
            code: IssueCode.duplicateId,
            message: 'Measurement cannot reconcile shared source output '
                '${output.path} to one analyzer declaration.',
            location: output.path,
          ),
        );
      } else {
        sourcesByOutputPath[output.path] = source;
      }
    }
  }
  final result = <MeasurementPublicationPlanningInput>[];
  for (final entry in manifest.publications) {
    final sourceArtifacts = <MeasurementPublicationSourceArtifact>[];
    var unresolved = '';
    for (final artifact in entry.artifacts.where(
      (artifact) => artifact.role == SurfacePublicationArtifactRole.screenBlob,
    )) {
      final source = sourcesByOutputPath[artifact.path];
      final discovery = source == null
          ? null
          : discoveriesByDeclarationIdentity[source.declarationIdentity];
      final occurrenceSet =
          rfwCatalogOccurrenceSetsByArtifactPath[artifact.path];
      if (source == null || discovery == null || occurrenceSet == null) {
        unresolved = artifact.path;
        break;
      }
      sourceArtifacts.add(
        MeasurementPublicationSourceArtifact(
          artifactPath: artifact.path,
          discovery: discovery,
          presentationAnchorStructuralOccurrenceKey:
              occurrenceSet.artifactAnchorStructuralOccurrenceKey,
          presentationLocalDeclarationAnchors:
              occurrenceSet.localDeclarationAnchors,
          presentationOccurrences: occurrenceSet.occurrences,
        ),
      );
    }
    if (unresolved.isNotEmpty) {
      // Whole surface or none: partial carriers would misreport the analytics
      // Measurement exists to feed.
      log.warning(
        'Measurement is unavailable for '
        '${entry.publication.surface.wireName}/${entry.publication.slug}: '
        'no resolved source for $unresolved. '
        'The surface compiles unmeasured.',
      );
      continue;
    }
    result.add(
      MeasurementPublicationPlanningInput(
        entry: entry,
        sourceArtifacts: sourceArtifacts,
      ),
    );
  }
  return result;
}

Map<String, MeasurementPaywallRouteEmissionOwnership> _paywallRouteOwnership(
  List<MeasurementPublicationPlanningInput> publications, {
  required RestageSourceRoster roster,
  required List<Issue> issues,
}) {
  final paywallsByIdentity = {
    for (final source in roster.declarations.where(
      (source) => source.kind == RestageRosterSourceKind.paywall,
    ))
      source.declarationIdentity: source,
  };
  final ownership = <String, ({bool standalone, bool adapter})>{};
  for (final publication in publications) {
    for (final artifact in publication.sourceArtifacts) {
      final identity =
          artifact.discovery.sourceProvenance!.resolvedSourceIdentity;
      final source = paywallsByIdentity[identity];
      if (source == null) continue;
      final claims = source.outputs
          .where((output) => output.path == artifact.artifactPath)
          .toList(growable: false);
      if (claims.length != 1) {
        issues.add(
          Issue(
            code: IssueCode.missingScreenDescriptor,
            message: 'Measurement paywall artifact ${artifact.artifactPath} '
                'requires one exact roster output role; found '
                '${claims.length}.',
            location: artifact.artifactPath,
          ),
        );
        continue;
      }
      final prior = ownership[identity] ?? (standalone: false, adapter: false);
      switch (claims.single.role) {
        case 'screen-blob' || 'binary':
          ownership[identity] = (
            standalone: true,
            adapter: prior.adapter,
          );
        case 'flow-screen-blob' || 'flow-screen-binary':
          ownership[identity] = (
            standalone: prior.standalone,
            adapter: true,
          );
        default:
          issues.add(
            Issue(
              code: IssueCode.missingScreenDescriptor,
              message: 'Measurement paywall artifact '
                  '${artifact.artifactPath} resolved to unsupported roster '
                  'role ${claims.single.role}.',
              location: artifact.artifactPath,
            ),
          );
      }
    }
  }
  return {
    for (final entry in ownership.entries)
      entry.key: MeasurementPaywallRouteEmissionOwnership(
        standalone: entry.value.standalone,
        adapter: entry.value.adapter,
      ),
  };
}

void _validateFlowMeasurementClosures(
  List<MeasurementPublicationPlanningInput> publications, {
  required List<NormalizedFlowSource> flows,
  required List<Issue> issues,
}) {
  for (final publication in publications.where(
    (publication) =>
        publication.entry.publication.payloadKind == SurfacePayloadKind.flow &&
        publication.entry.publication.sourceKind == SurfaceSourceKind.flowGraph,
  )) {
    final selector = publication.selector;
    final matches = flows
        .where(
          (flow) =>
              flow.surface == selector.surface && flow.id == selector.slug,
        )
        .toList(growable: false);
    if (matches.length != 1) {
      issues.add(
        Issue(
          code: IssueCode.missingScreenDescriptor,
          message: 'Measurement flow closure requires one resolved flow for '
              '${selector.surface.wireName}/${selector.slug}; found '
              '${matches.length}.',
          location: selector.key,
        ),
      );
      continue;
    }
    final declaration = matches.single.declaration;
    if (declaration is! ClassElement) continue;
    final closure = MeasurementSourceDiscovery.closeFlowSourceV1(
      MeasurementFlowSourceClosureInput(
        flowSourceClass: declaration,
        staticArtifactDiscoveries: publication.sourceArtifacts.map(
          (artifact) => artifact.discovery,
        ),
      ),
    );
    if (closure.disposition !=
        MeasurementFlowSourceClosureDisposition.accepted) {
      issues.add(
        Issue(
          code: IssueCode.annotationEvaluationFailed,
          message: 'Measurement flow closure rejected '
              '${selector.surface.wireName}/${selector.slug}: '
              '${closure.rejectionReason}',
          location: matches.single.declarationIdentity,
        ),
      );
    }
  }
}

Future<void> _appendResolvedScreens(
  BuildStep buildStep, {
  required List<ResolvedScreenCompilationInput> inputs,
  required Map<String, MeasurementRouteEmissionPlan> routePlans,
  required Map<String, fmt.ResolvedRfwCatalogOccurrenceSet>
      rfwCatalogOccurrenceSetsByDeclarationIdentity,
  required RestageOutputPlacementPlan placement,
  required List<CompiledSurfaceArtifact> rendered,
  required List<ResolvedStandaloneScreenContract> contracts,
  required List<LegacyStandaloneScreenContract> legacyContracts,
  required Map<String, RestageSourceDeclaration> sourcesByDeclarationIdentity,
  required List<AnalyticsIdControlCapture> analyticsIdControlCaptures,
  required List<Issue> issues,
  required Set<String> buildNoticeKeys,
  required void Function(Issue issue, bool isCanonical)
      appFactoryNoticeCollector,
}) async {
  final compilation = await compileResolvedScreens(
    buildStep,
    inputs,
    measurementRoutePlans: routePlans,
    rfwCatalogOccurrenceSets: rfwCatalogOccurrenceSetsByDeclarationIdentity,
    buildNoticeKeys: buildNoticeKeys,
    appFactoryNoticeCollector: appFactoryNoticeCollector,
  );
  issues.addAll(compilation.issues);
  for (final screen in compilation.screens) {
    final source =
        sourcesByDeclarationIdentity[screen.input.declarationIdentity];
    if (source == null) {
      issues.add(
        Issue(
          code: IssueCode.analyzerResolutionFailed,
          message: 'Compiled Measurement screen lost its roster source.',
          location: screen.input.declarationIdentity,
        ),
      );
      continue;
    }
    analyticsIdControlCaptures.addAll(
      screen.analyticsIdDeclarations.map(
        (declaration) => AnalyticsIdControlCapture(
          sourceDeclarationIdentity: screen.input.declarationIdentity,
          capture: declaration,
        ),
      ),
    );
    final capabilities = _effectiveScreenCapabilities(
      authoredMinClient: screen.input.minClient,
      derivedCapabilities: screen.capabilities,
    );
    final sidecar = _effectiveCapabilitySidecar(
      existing: screen.capabilitySidecar,
      blob: screen.blob,
      derivedCapabilities: screen.capabilities,
      effectiveCapabilities: capabilities,
    );
    rendered.add(
      CompiledSurfaceArtifact(
        declaration: screen.input.declaration,
        blob: screen.blob,
        capabilitySidecar: sidecar,
        flowArtifactPath: '${screen.input.id}.rfw',
        rfwText: utf8.encode(screen.text),
        rfwCatalogOccurrenceSetsByOutputRole:
            _rfwCatalogOccurrenceSetsForSourceOutputRoles(
          source: source,
          outputRoles: const {'screen-blob', 'binary'},
          occurrenceSet: screen.rfwCatalogOccurrenceSet,
        ),
      ),
    );
    final surface = screen.input.surface;
    if (surface == null) continue;
    if (source.isCanonical) {
      final contract = inspectStandaloneScreenContract(
        ResolvedStandaloneScreenContractInput(
          assetId: screen.input.assetId,
          screen: screen.input.declaration,
          surface: surface,
          slug: screen.input.id,
          contractVersion: screen.input.version,
          capabilities: capabilities,
          rootParams: screen.input.build.rootParams,
          constructorParams: screen.input.build.constructorParams,
          mountConstructorProblem: screen.input.build.mountConstructorProblem,
          plan: placement,
          bundleEntryMetadata: ResolvedScreenBundleEntryMetadata(
            blobSha256: CapabilitySidecar.hashBlob(screen.blob),
            blobByteLength: screen.blob.length,
            sidecarSha256: CapabilitySidecar.hashBlob(sidecar),
            sidecarByteLength: sidecar.length,
          ),
        ),
      );
      issues.addAll(contract.issues);
      final resolved = contract.contract;
      if (resolved != null) {
        final message = resolved.mountOmissionMessage;
        if (message != null) log.warning(message);
        contracts.add(resolved);
      }
    } else {
      final contract = inspectLegacyStandaloneScreenContract(
        LegacyStandaloneScreenContractInput(
          assetId: screen.input.assetId,
          screen: screen.input.declaration,
          surface: surface,
          slug: screen.input.id,
          contractVersion: screen.input.version,
          capabilities: capabilities,
        ),
      );
      issues.addAll(contract.issues);
      if (contract.contract != null) legacyContracts.add(contract.contract!);
    }
  }
}

List<ResolvedClassFlowScreen> _resolvedClassFlowScreens(
  List<CompiledSurfaceArtifact> rendered, {
  required Map<String, RestageSourceDeclaration> sourcesByDeclarationIdentity,
  required List<Issue> issues,
}) {
  final result = <ResolvedClassFlowScreen>[];
  for (final artifact in rendered) {
    final source = sourcesByDeclarationIdentity[artifact.declarationIdentity];
    if (source == null) {
      issues.add(
        Issue(
          code: IssueCode.analyzerResolutionFailed,
          message: 'Rendered Measurement source is absent from the roster.',
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
    result.add(
      ResolvedClassFlowScreen(
        declaration: artifact.declaration,
        surface: source.surface,
        id: artifact.flowScreenId ?? source.effectiveId,
        artifactPath: artifact.flowArtifactPath,
        version: source.version,
        minClient: sidecar.manifest.builtInFloor,
        blob: artifact.blob,
        canonicalPaywallId: source.kind == RestageRosterSourceKind.paywall
            ? source.effectiveId
            : null,
      ),
    );
  }
  return result;
}

Future<void> _compileLegacyClassFlowDocuments(
  BuildStep buildStep, {
  required List<_FlowCompilationJob> jobs,
  required List<ResolvedClassFlowScreen> screens,
  required Map<String, RestageSourceDeclaration> sourcesByDeclarationIdentity,
  required List<CompiledFlowArtifact> precompiledFlows,
  required List<Issue> issues,
  Map<String, String> generatedSourceCarrierDraftDigestsByDeclarationIdentity =
      const {},
}) async {
  for (final job in jobs) {
    for (final flow in job.flows.where(
      (flow) => flow.graph == null && !flow.isCanonical,
    )) {
      if (!sourcesByDeclarationIdentity.containsKey(flow.declarationIdentity)) {
        issues.add(
          Issue(
            code: IssueCode.analyzerResolutionFailed,
            message: 'Legacy flow ${flow.declarationIdentity} is absent from '
                'the source roster during Measurement recompilation.',
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
        includeCanonical: false,
        resolvedScreens: screens,
        declarationIdentities: {flow.declarationIdentity},
        generatedSourceCarrierDraftDigestsByDeclarationIdentity:
            generatedSourceCarrierDraftDigestsByDeclarationIdentity,
      );
      issues.addAll(compilation.issues);
      if (compilation.flows.length != 1) {
        if (compilation.issues.isEmpty) {
          issues.add(
            Issue(
              code: IssueCode.analyzerResolutionFailed,
              message: 'Expected one Measurement-recompiled legacy flow for '
                  '${flow.declarationIdentity}; found '
                  '${compilation.flows.length}.',
              location: flow.declarationIdentity,
            ),
          );
        }
        continue;
      }
      final compiled = compilation.flows.single;
      precompiledFlows.add(
        CompiledFlowArtifact(
          declaration: compiled.declaration,
          flowDocumentBytes: compiled.flowDocumentBytes,
          generatedPart: compiled.generatedPart,
          generatedTopLevelSymbols: compiled.generatedTopLevelSymbols,
        ),
      );
    }
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
  Map<String, String> generatedSourceCarrierDraftDigestsByDeclarationIdentity =
      const {},
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
  final generatedSourceCarrierDraftDigests =
      generatedSourceCarrierDraftDigestsByDeclarationIdentity;
  final pending = Map<NormalizedFlowIdentity, NormalizedFlowSource>.of(
    canonicalByIdentity,
  );
  while (pending.isNotEmpty) {
    var madeProgress = false;
    final ordered = pending.values.toList()
      ..sort((left, right) {
        final bySurface = left.surface.wireName.compareTo(
          right.surface.wireName,
        );
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
          generatedSourceCarrierDraftDigestsByDeclarationIdentity:
              generatedSourceCarrierDraftDigests,
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
            generatedTopLevelSymbols: compiled.generatedTopLevelSymbols,
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

Future<void> _compilePaywalls(
  BuildStep buildStep, {
  required List<_PaywallCompilationJob> jobs,
  bool Function(PaywallSourceFound source)? retainSource,
  required List<CompiledSurfaceArtifact> rendered,
  required Map<String, RestageSourceDeclaration> sourcesByDeclarationIdentity,
  required List<AnalyticsIdControlCapture> analyticsIdControlCaptures,
  required List<Issue> issues,
  required Set<String> buildNoticeKeys,
  required void Function(Issue issue, bool isCanonical)
      appFactoryNoticeCollector,
  Map<String, MeasurementRouteEmissionPlan> measurementRoutePlans = const {},
  Map<String, MeasurementPaywallRouteEmissionOwnership>
      measurementRouteOwnership = const {},
  Map<String, fmt.ResolvedRfwCatalogOccurrenceSet>
      adapterRfwCatalogOccurrenceSetsByDeclarationIdentity = const {},
  Map<String, fmt.ResolvedRfwCatalogOccurrenceSet>
      standaloneRfwCatalogOccurrenceSetsByDeclarationIdentity = const {},
}) async {
  String? canonicalPaywallIdFor(ClassElement declaration) {
    final identity =
        '${declaration.library.identifier}#${declaration.name ?? '<unnamed>'}';
    final source = sourcesByDeclarationIdentity[identity];
    if (source == null || source.kind != RestageRosterSourceKind.paywall) {
      return null;
    }
    return source.effectiveId;
  }

  final compiledById = <String, _CompiledPaywall>{};
  for (final job in jobs) {
    final compilation = await compileResolvedPaywalls(
      buildStep,
      library: job.library,
      assetId: job.assetId,
      sources: job.sources,
      canonicalPaywallIdFor: canonicalPaywallIdFor,
      measurementRoutePlans: measurementRoutePlans,
      measurementRouteOwnership: measurementRouteOwnership,
      adapterRfwCatalogOccurrenceSetsByDeclarationIdentity:
          adapterRfwCatalogOccurrenceSetsByDeclarationIdentity,
      standaloneRfwCatalogOccurrenceSetsByDeclarationIdentity:
          standaloneRfwCatalogOccurrenceSetsByDeclarationIdentity,
      buildNoticeKeys: buildNoticeKeys,
      appFactoryNoticeCollector: appFactoryNoticeCollector,
      retainSource: retainSource,
    );
    issues.addAll(compilation.issues);
    for (final compiled in compilation.paywalls) {
      final sourceDeclarationIdentity =
          '${job.library.identifier}#${compiled.source.className}';
      analyticsIdControlCaptures.addAll(
        [
          ...compiled.standaloneAnalyticsIdDeclarations,
          ...compiled.adapterAnalyticsIdDeclarations,
        ].map(
          (declaration) => AnalyticsIdControlCapture(
            sourceDeclarationIdentity: sourceDeclarationIdentity,
            capture: declaration,
          ),
        ),
      );
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
      compiledById[compiled.source.id] = _CompiledPaywall(
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
    final declaration = entry.value.declaration;
    final declarationName = declaration.name ?? '<unnamed>';
    final source = sourcesByDeclarationIdentity[
        '${declaration.library.identifier}#$declarationName'];
    if (source == null) {
      issues.add(
        Issue(
          code: IssueCode.analyzerResolutionFailed,
          message: 'Compiled paywall $id lost its roster source.',
          location: entry.value.assetId.path,
        ),
      );
      continue;
    }
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
          rfwCatalogOccurrenceSetsByOutputRole:
              _rfwCatalogOccurrenceSetsForPaywallOutputRoles(
            source: source,
            adapterOccurrenceSet: compiled.adapterRfwCatalogOccurrenceSet,
            standaloneOccurrenceSet: compiled.standaloneRfwCatalogOccurrenceSet,
          ),
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

final class _PaywallCompilationJob {
  const _PaywallCompilationJob({
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

final class _CompiledPaywall {
  const _CompiledPaywall({
    required this.assetId,
    required this.declaration,
    required this.artifacts,
  });

  final AssetId assetId;
  final ClassElement declaration;
  final CompiledPaywallArtifacts artifacts;
}

TrackedPackageSurfaceCompilation _invalidCompilation(
  List<Issue> rawIssues, {
  RestageMeasurementCompilerOutputV1? measurementCompilerOutput,
}) {
  final issues = List<Issue>.of(rawIssues)
    ..sort((left, right) {
      final byLocation = left.location.compareTo(right.location);
      if (byLocation != 0) return byLocation;
      final byCode = left.code.name.compareTo(right.code.name);
      if (byCode != 0) return byCode;
      return left.message.compareTo(right.message);
    });
  final supplied = measurementCompilerOutput;
  final errors = issues.map((issue) => issue.toLogString()).toList();
  final invalidMeasurementOutput = supplied != null && !supplied.valid
      ? supplied
      : RestageMeasurementCompilerOutputV1(
          valid: false,
          errors: errors,
          policy: supplied?.policy,
          nextIdentitySequence: supplied?.nextIdentitySequence ?? 1,
          ledgerNodes: supplied?.ledgerNodes ?? const [],
          acceptedRelocations: supplied?.acceptedRelocations ?? const [],
          acceptedIntroductions: supplied?.acceptedIntroductions ?? const [],
          proposals: supplied?.proposals ?? const [],
          publications: const [],
        );
  return TrackedPackageSurfaceCompilation(
    publicationBundle: RestageSurfacePublicationBundle.invalid(
      errors,
    ),
    measurementCompilerOutput: invalidMeasurementOutput,
    analyticsIdControlOutput: AnalyticsIdControlOutputV1(
      packageName: 'invalid',
      publications: const <AnalyticsIdControlPublication>[],
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
