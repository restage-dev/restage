// Builder implementation is reached through documented factories.
// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:build/build.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:restage_codegen/src/surface_publication/app_widget_events.dart';
import 'package:restage_codegen/src/analytics_id_lowering.dart';
import 'package:restage_codegen/src/annotation_lookup.dart';
import 'package:restage_codegen/src/capability_derivation.dart';
import 'package:restage_codegen/src/catalog_loader.dart';
import 'package:restage_codegen/src/catalog_validator.dart';
import 'package:restage_codegen/src/frozen_occurrence_rebinding.dart';
import 'package:restage_codegen/src/dot_shorthand_expansion.dart';
import 'package:restage_codegen/src/dsl_parse_diagnostic.dart';
import 'package:restage_codegen/src/emit_utils.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/hoisting.dart';
import 'package:restage_codegen/src/islands/islands.dart';
import 'package:restage_codegen/src/design_state.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_codegen/src/measurement/measurement_route_emission.dart';
import 'package:restage_codegen/src/onboarding/onboarding_helpers.dart';
import 'package:restage_codegen/src/rfw_emitter.dart';
import 'package:restage_codegen/src/screen_source_admission.dart';
import 'package:restage_codegen/src/source_state.dart';
import 'package:restage_codegen/src/surface_publication/host_data_contract.dart';
import 'package:restage_codegen/src/surface_publication/output_location.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:restage_codegen/src/surface_publication/split_widgets.dart';
import 'package:restage_codegen/src/surface_vocabulary.dart';
import 'package:restage_codegen/src/widget_classifier.dart';
import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:restage_shared/restage_shared.dart'
    show CapabilityManifest, CapabilitySidecar, Surface, canonicalizeLibrary;
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

const JsonEncoder _jsonEncoder = JsonEncoder.withIndent('  ');
const String _restageSdkOrigin = 'package:restage';
const String _restageSharedOrigin = 'package:restage_shared';

@immutable
final class ResolvedScreenCompilationInput {
  const ResolvedScreenCompilationInput({
    required this.assetId,
    required this.declaration,
    required this.id,
    required this.version,
    required this.minClient,
    required this.surface,
    required this.build,
    required this.isCanonical,
  });

  final AssetId assetId;
  final ClassElement declaration;
  final String id;
  final int version;
  final int minClient;
  final Surface? surface;
  final SourceBuildBlueprint build;
  final bool isCanonical;

  String get declarationIdentity =>
      '${declaration.library.identifier}#${declaration.name ?? '<unnamed>'}';
}

@immutable
final class ResolvedScreenInspectionResult {
  ResolvedScreenInspectionResult({
    required List<ResolvedScreenCompilationInput> screens,
    required List<Issue> issues,
  }) : screens = List.unmodifiable(screens),
       issues = List.unmodifiable(issues);

  final List<ResolvedScreenCompilationInput> screens;
  final List<Issue> issues;
}

@immutable
final class CompiledResolvedScreen {
  CompiledResolvedScreen({
    required this.input,
    required this.text,
    required List<int> blob,
    required List<int> capabilitySidecar,
    required this.capabilities,
    required this.rfwCatalogOccurrenceSet,
    required Iterable<AnalyticsIdDeclaration> analyticsIdDeclarations,
    this.vocabulary = SurfaceVocabularyReferences.empty,
    Map<String, Object> localSeeds = const {},
    Iterable<HoistedValue> hoisted = const [],
    Iterable<PropertyInducingElement> firedEvents = const [],
    this.islands = const [],
    Iterable<AstNode> placedCustomWidgetSites = const [],
    this.split,
    Iterable<SplitWidgetInput> splitWidgets = const [],
  }) : blob = Uint8List.fromList(blob),
       placedCustomWidgetSites = List.unmodifiable(placedCustomWidgetSites),
       firedEvents = List.unmodifiable(firedEvents),
       splitWidgets = List.unmodifiable(splitWidgets),
       hoisted = List.unmodifiable(hoisted),
       capabilitySidecar = Uint8List.fromList(capabilitySidecar),
       analyticsIdDeclarations = List.unmodifiable(analyticsIdDeclarations),
       localSeeds = Map.unmodifiable(localSeeds);

  final ResolvedScreenCompilationInput input;
  final String text;
  final Uint8List blob;
  final Uint8List capabilitySidecar;
  final CapabilityManifest capabilities;

  /// The catalog widgets and icon constants this screen renders, named so a
  /// generated reference can install exactly them.
  final SurfaceVocabularyReferences vocabulary;

  /// Frozen resolved RFW catalog calls shared by both compiler passes.
  final ResolvedRfwCatalogOccurrenceSet rfwCatalogOccurrenceSet;

  /// Labels extracted before validation and canonical encoding.
  final List<AnalyticsIdDeclaration> analyticsIdDeclarations;

  /// Initial screen-local values, keyed by value name.
  final Map<String, Object> localSeeds;

  /// Values the screen's mount computes, ordered by key.
  final List<HoistedValue> hoisted;

  /// The `SurfaceEvent` constants the screen's build fires.
  final List<PropertyInducingElement> firedEvents;

  /// Widget expressions the screen's mount renders from the app.
  final List<Island> islands;

  /// Custom widget constructions the screen places by catalog entry.
  final List<AstNode> placedCustomWidgetSites;

  /// How the screen's mount takes over its shell and `State`.
  final MountSplit? split;

  /// The custom widgets its library splits: each one's delivered definition
  /// and the build its generated wrapper records.
  final List<SplitWidgetInput> splitWidgets;
}

@immutable
final class ResolvedScreenCompilationResult {
  ResolvedScreenCompilationResult({
    required List<CompiledResolvedScreen> screens,
    required List<Issue> issues,
  }) : screens = List.unmodifiable(screens),
       issues = List.unmodifiable(issues);

  final List<CompiledResolvedScreen> screens;
  final List<Issue> issues;

  bool get isValid => issues.isEmpty;
}

/// Inspects analyzer-resolved canonical `@Screen` declarations in [library].
///
/// The returned inputs retain class elements and resolved build expressions;
/// no screen identity is recovered from a type string or a directory name.
Future<ResolvedScreenInspectionResult> inspectCanonicalScreenDeclarations(
  LibraryElement library,
  AssetId assetId, {
  Catalog? catalog,
}) async {
  final screens = <ResolvedScreenCompilationInput>[];
  final issues = <Issue>[];
  final implicit = <ClassElement>[];

  for (final declaration in library.classes) {
    final annotation = firstAnnotationFromOriginAny(
      declaration,
      const {'Screen'},
      _restageSdkOrigin,
    );
    if (annotation == null) continue;
    final value = annotation.computeConstantValue();
    final className = declaration.name ?? '<unnamed>';
    final location = '${assetId.path}#$className';
    if (value == null) {
      issues.add(
        Issue(
          code: IssueCode.annotationEvaluationFailed,
          message: '@Screen on $className could not be const-evaluated.',
          location: location,
        ),
      );
      continue;
    }
    final idValue = value.getField('id');
    final explicitId = idValue == null || idValue.isNull
        ? null
        : idValue.toStringValue();
    if (explicitId != null &&
        (explicitId.isEmpty || explicitId.contains('\u0000'))) {
      issues.add(
        Issue(
          code: IssueCode.annotationEvaluationFailed,
          message: '@Screen.id must be a non-empty, NUL-free String literal.',
          location: location,
        ),
      );
      continue;
    }
    if (explicitId == null) implicit.add(declaration);
    final surfaceValue = value.getField('surface');
    final surface = surfaceValue == null || surfaceValue.isNull
        ? null
        : _surfaceFromValue(surfaceValue);
    if (surfaceValue != null && !surfaceValue.isNull && surface == null) {
      issues.add(
        Issue(
          code: IssueCode.annotationEvaluationFailed,
          message: '@Screen.surface must resolve to a Restage Surface value.',
          location: location,
        ),
      );
      continue;
    }
    final build = await extractSourceBuildBlueprint(
      catalog: catalog,
      sourceClass: declaration,
      library: library,
      astNodeFor: resolvedAstNodeFor,
      issues: issues,
      location: location,
      liftState: true,
    );
    if (build == null) continue;
    screens.add(
      ResolvedScreenCompilationInput(
        assetId: assetId,
        declaration: declaration,
        id: explicitId ?? p.basenameWithoutExtension(assetId.path),
        version: value.getField('version')?.toIntValue() ?? 1,
        minClient: value.getField('minClient')?.toIntValue() ?? 1,
        surface: surface,
        build: build,
        isCanonical: true,
      ),
    );
  }

  if (implicit.length > 1) {
    issues.add(
      Issue(
        code: IssueCode.invalidScreenSourceCount,
        message:
            'At most one @Screen declaration per library may omit id; '
            'found ${implicit.length}.',
        location: assetId.path,
      ),
    );
  }
  final seen = <String>{};
  for (final screen in screens) {
    if (seen.add(screen.id)) continue;
    issues.add(
      Issue(
        code: IssueCode.duplicateId,
        message: 'Multiple @Screen declarations share id "${screen.id}".',
        location: assetId.path,
      ),
    );
  }
  return ResolvedScreenInspectionResult(screens: screens, issues: issues);
}

/// Translates resolved screen build expressions into exact RFW and sidecar
/// bytes without writing outputs.
Future<ResolvedScreenCompilationResult> compileResolvedScreens(
  BuildStep buildStep,
  Iterable<ResolvedScreenCompilationInput> inputs, {
  Map<String, MeasurementRouteEmissionPlan> measurementRoutePlans =
      const <String, MeasurementRouteEmissionPlan>{},
  Map<String, ResolvedRfwCatalogOccurrenceSet> rfwCatalogOccurrenceSets =
      const <String, ResolvedRfwCatalogOccurrenceSet>{},
  Set<String>? buildNoticeKeys,
  void Function(Issue issue, bool isCanonical)? appFactoryNoticeCollector,
}) async {
  final ordered = inputs.toList()
    ..sort(
      (left, right) =>
          left.declarationIdentity.compareTo(right.declarationIdentity),
    );
  if (ordered.isEmpty) {
    return ResolvedScreenCompilationResult(screens: const [], issues: const []);
  }
  final issues = <Issue>[];
  final noticeKeys = buildNoticeKeys ?? <String>{};
  final catalog = await loadMergedCatalog(buildStep);
  final helpers = HelperRegistry()..registerAll(onboardingHelpers);
  final classification = await classifyReferencedCustomWidgets(
    rootExpressions: ordered.expand((source) => source.build.collectorRoots),
    catalog: catalog,
    helpers: helpers,
    astNodeFor: (fragment) =>
        resolvedNodeInLongForm(buildStep.resolver, fragment),
  );
  // Each custom widget that doesn't fully inline, split as its own root, as
  // each screen's library sees it.
  final splitsByLibrary =
      Map<LibraryElement, Future<List<SplitWidgetInput>>>.identity();
  Future<List<SplitWidgetInput>> splitsOf(LibraryElement library) =>
      splitsByLibrary[library] ??= splitWidgetsOf(
        noticeKeys: noticeKeys,
        custom: () => packageReconstruction(buildStep),
        classification: classification,
        catalog: catalog,
        surfaceLibrary: library,
        astNodeFor: (fragment) =>
            resolvedNodeInLongForm(buildStep.resolver, fragment),
        translator: ExpressionTranslator(
          catalog: catalog,
          helpers: helpers,
          customWidgetClassifications: classification.classifications,
          customWidgetBlueprints: classification.blueprints,
        ),
      );
  ExpressionTranslator translatorFor(
    MeasurementRouteEmissionPlan? measurementRoutePlan,
    List<SplitWidgetInput> splits,
  ) => ExpressionTranslator(
    catalog: catalog,
    helpers: helpers,
    customWidgetClassifications: classification.classifications,
    customWidgetBlueprints: classification.blueprints,
    splitWidgetDefinitions: splitWidgetDefinitionsOf(splits),
    measurementRouteEmissionPlan: measurementRoutePlan,
  );
  final compiled = <CompiledResolvedScreen>[];
  for (final source in ordered) {
    final resolved = await resolveLibraryInLongForm(source.declaration.library);
    final lineInfo =
        resolved is ResolvedLibraryResult && resolved.units.isNotEmpty
        ? resolved.units.first.lineInfo
        : null;
    final splits = await splitsOf(source.declaration.library);
    final routePlan = measurementRoutePlans[source.declarationIdentity];
    TranslationResult translateWith(
      SourceBuildBlueprint build,
      MeasurementRouteEmissionPlan? plan,
    ) => translatorFor(plan, splits).translate(
      build.rootExpression,
      sourcePath: source.assetId.path,
      lineInfo: lineInfo,
      rootState: build.state,
      rootParams: build.rootParams,
      rootEventHandlers: build.eventHandlers,
      rootInlined: build.inlined,
      buildContextParameter: build.buildContextParameter,
      hoistInMount: true,
      liftedState: build.liftedState,
      contentFree: build.contentFree,
      rootBuildArguments: build.buildArguments,
      surfaceId: source.id,
    );
    TranslationResult unmeasured(SourceBuildBlueprint build) =>
        translateWith(build, null);
    var build = source.build;
    // The lift is decided without measurement, as a paywall's is: a measured
    // callback refuses before its island records the State it needs.
    var probe = unmeasured(build);
    final stateNotices = <Issue>[];
    // An island that needs a lowerable State's members moves the State into
    // the mount.
    if (source.build.liftable case final lifted?
        when (probe.issues.any((issue) => !issue.code.isBuildNotice) ||
                probe.split?.recordProblem != null) &&
            probe.blocked.any(
              (element) => isInstanceMemberOf(lifted.liftedState!, element),
            )) {
      final moved = liftState(lifted, unmeasured);
      probe = moved.translation;
      build = moved.build;
      if (moved.notice case final notice?) stateNotices.add(notice);
    }
    final translation = routePlan == null
        ? probe
        : translateWith(build, routePlan);
    if (build.stateKeptInApp case final notice?) stateNotices.add(notice);
    if (_collectTranslationIssues(
      issues,
      [...stateNotices, ...translation.issues],
      buildNoticeKeys: noticeKeys,
      sourceIsCanonical: source.isCanonical,
      appFactoryNoticeCollector: appFactoryNoticeCollector,
    )) {
      continue;
    }
    final text = emitRemoteWidgetLibrary(
      translation.dsl,
      rootWidgetName: onboardingScreenRootWidgetName,
      widgetDefinitions: translation.widgetDefinitions,
      widgetDefinitionStates: translation.widgetDefinitionStates,
      rootWidgetState: translation.rootWidgetState,
      customLibraryImports: translation.referencedCustomLibraries,
    );
    try {
      final parsedLibrary = fmt.parseLibraryFile(
        text,
        sourceIdentifier: source.id,
      );
      final frozenOccurrenceSet =
          rfwCatalogOccurrenceSets[source.declarationIdentity];
      final measurementRoutePlan =
          measurementRoutePlans[source.declarationIdentity];
      if (measurementRoutePlan != null && frozenOccurrenceSet == null) {
        issues.add(
          Issue(
            code: IssueCode.missingScreenDescriptor,
            message:
                'Final Measurement screen emission requires its frozen '
                'RFW occurrence evidence.',
            location:
                '${source.assetId.path}#'
                '${source.declaration.name ?? '<unnamed>'}',
          ),
        );
        continue;
      }
      final resolvedOccurrenceSet =
          frozenOccurrenceSet ??
          ResolvedRfwCatalogOccurrenceSet.resolve(
            operations: translation.valueOperations,
            parsedLibrary: parsedLibrary,
            input: translation.rfwCatalogOccurrenceResolutionInput(
              artifactProvenance: _rfwOccurrenceSetKey(
                declarationIdentity: source.declarationIdentity,
                rootWidgetName: onboardingScreenRootWidgetName,
              ),
              sourceLibraryIdentity: source.declaration.library.identifier,
              sourceDeclarationIdentity: source.declarationIdentity,
              renderEntryNames: const [onboardingScreenRootWidgetName],
            ),
          );
      final rebound = rebindFrozenOccurrences(
        frozenOccurrenceSet,
        parsedLibrary,
        name: source.declaration.name ?? '<unnamed>',
        location:
            '${source.assetId.path}#'
            '${source.declaration.name ?? '<unnamed>'}',
        issues: issues,
      );
      if (rebound == null) continue;
      final occurrenceRebinding = rebound.rebinding;
      final lowering = lowerAnalyticsIds(
        text: text,
        library: parsedLibrary,
        sourceIdentifier: source.id,
        location:
            '${source.assetId.path}#'
            '${source.declaration.name ?? '<unnamed>'}',
        occurrenceSet: frozenOccurrenceSet == null
            ? resolvedOccurrenceSet
            : null,
        occurrenceRebinding: occurrenceRebinding,
      );
      issues.addAll(lowering.issues);
      if (lowering.issues.isNotEmpty) continue;
      final library = lowering.library;
      final screenCatalog = withSplits(catalog, translation.islands, splits);
      final validationIssues = validateModelAgainstCatalog(
        library,
        screenCatalog,
        rootLabels: {
          onboardingScreenRootWidgetName: source.declaration.name ?? source.id,
        },
        operations: translation.valueOperations,
        hostDataContract: hostDataContractOf(
          const [],
          hoisted: translation.hoisted,
        ),
      );
      issues.addAll(validationIssues);
      if (validationIssues.isNotEmpty) continue;
      final derivation = deriveCapabilityManifest(
        library,
        screenCatalog,
        hoisted: translation.hoisted,
      );
      issues.addAll(derivation.issues);
      if (derivation.issues.isNotEmpty || derivation.manifest == null) continue;
      final blob = fmt.encodeLibraryBlob(canonicalizeLibrary(library));
      final sidecar = utf8.encode(
        _jsonEncoder.convert(
          CapabilitySidecar(
            blobSha256: CapabilitySidecar.hashBlob(blob),
            manifest: derivation.manifest!,
          ).toJson(),
        ),
      );
      compiled.add(
        CompiledResolvedScreen(
          input: source,
          text: lowering.text,
          blob: blob,
          capabilitySidecar: sidecar,
          capabilities: derivation.manifest!,
          vocabulary:
              referencesOfCatalogEntries(
                derivation.referencedWidgets,
              ).union(
                SurfaceVocabularyReferences(icons: translation.iconReferences),
              ),
          rfwCatalogOccurrenceSet: resolvedOccurrenceSet,
          analyticsIdDeclarations: lowering.declarations,
          localSeeds: translation.localSeeds,
          hoisted: translation.hoisted,
          // An app widget it shows as an island fires from its own build.
          firedEvents: {
            ...translation.firedEvents,
            ...await AppWidgetEvents(
              package: source.assetId.package,
              noticeKeys: noticeKeys,
              astNodeFor: (fragment) =>
                  resolvedNodeInLongForm(buildStep.resolver, fragment),
            ).firedBy(translation.islands, translation.placedCustomWidgets),
          },
          islands: translation.islands,
          placedCustomWidgetSites: translation.placedCustomWidgetSites,
          split: translation.split,
          splitWidgets: splits,
        ),
      );
    } on fmt.ParserException catch (error) {
      issues.add(
        Issue(
          code: IssueCode.malformedTranslatorOutput,
          message:
              'Translator emitted invalid screen RFW for '
              '"${source.id}": $error '
              '${dslParseFailureDetail(
                text,
                error,
                translation.emissionSources,
              )}',
          location:
              '${source.assetId.path}#'
              '${source.declaration.name ?? '<unnamed>'}',
        ),
      );
    }
  }
  return ResolvedScreenCompilationResult(
    screens: issues.isEmpty ? compiled : const [],
    issues: issues,
  );
}

String _rfwOccurrenceSetKey({
  required String declarationIdentity,
  required String rootWidgetName,
}) {
  final value = jsonEncode([declarationIdentity, rootWidgetName]);
  return 'rfw-occurrence-v1:${crypto.sha256.convert(utf8.encode(value))}';
}

final class OnboardingScreenBuilder implements Builder {
  OnboardingScreenBuilder(
    this.options, {
    this.surface = Surface.onboarding,
  }) {
    if (!_flowSurfaces.contains(surface)) {
      throw ArgumentError.value(
        surface,
        'surface',
        'must be a flow surface (onboarding / message / survey); paywalls '
            'have dedicated builders',
      );
    }
  }

  /// The surfaces this builder may codegen for. Paywalls have dedicated
  /// builders; a new surface type must be added here deliberately.
  static const Set<Surface> _flowSurfaces = {
    Surface.onboarding,
    Surface.message,
    Surface.survey,
  };

  final BuilderOptions options;

  bool get _aggregateOwnsCanonical =>
      options.config['aggregate_canonical_owner'] == true;

  /// The flow surface (`onboarding` / `message` / `survey`) this builder
  /// instance codegens for. Defaults to [Surface.onboarding], the surface
  /// this builder originally served. The surface is carried by the source
  /// directory (`lib/<surface>/screens/...`).
  final Surface surface;

  String get _sourceDir => 'lib/${surface.wireName}/screens';
  String get _outputDir => 'assets/${surface.wireName}/screens';

  @override
  Map<String, List<String>> get buildExtensions {
    final extensions = <String, List<String>>{
      '$_sourceDir/{{name}}.dart': [
        '$_outputDir/{{name}}.rfwtxt',
        '$_outputDir/{{name}}.rfw',
        '$_outputDir/{{name}}.capability.json',
      ],
    };
    if (surface == Surface.onboarding) {
      extensions['lib/general/screens/{{name}}.dart'] = const [
        'assets/general/screens/{{name}}.rfwtxt',
        'assets/general/screens/{{name}}.rfw',
        'assets/general/screens/{{name}}.capability.json',
      ];
    }
    return extensions;
  }

  @override
  Future<void> build(BuildStep buildStep) async {
    final assetId = buildStep.inputId;
    if (!await buildStep.resolver.isLibrary(assetId)) return;

    final library = await buildStep.resolver.libraryFor(
      assetId,
      allowSyntaxErrors: true,
    );
    final catalog = await loadMergedCatalog(buildStep);
    final canonical = await inspectCanonicalScreenDeclarations(
      library,
      assetId,
      catalog: catalog,
    );
    if (canonical.issues.isNotEmpty) _surfaceIssues(canonical.issues);
    if (canonical.screens.isNotEmpty) {
      // Canonical sources are owned exclusively by the tracked package
      // compiler. This conventional builder remains a legacy compatibility
      // entrypoint and must not derive a public artifact family from a source
      // directory or filename.
      if (_aggregateOwnsCanonical) return;
      await _writeCanonicalFallback(buildStep, canonical.screens);
      return;
    }
    final admission = await inspectScreenSourceAdmission(
      buildStep,
      assetId: assetId,
      library: library,
      catalog: catalog,
    );
    final result = admission.visitorResult;
    final issues = [...admission.issues];

    if (!admission.participates) return;

    final stem = conventionalOutputStem(
      assetId.path,
      'lib/${p.posix.split(assetId.path)[1]}/screens',
    );
    for (final src in result.sources) {
      final descriptorName = '${src.className}Descriptor';
      if (_hasTopLevelDeclaration(library, descriptorName)) {
        issues.add(
          Issue(
            code: IssueCode.generatedSymbolCollision,
            message:
                'Generated descriptor symbol $descriptorName already '
                'exists in ${assetId.path}.',
            location: '${assetId.path}#$descriptorName',
          ),
        );
      }
    }
    if (!admission.isAdmitted || issues.isNotEmpty) _surfaceIssues(issues);

    final helpers = HelperRegistry()..registerAll(onboardingHelpers);
    final classification = await classifyReferencedCustomWidgets(
      rootExpressions: result.sources.expand(
        (source) => source.build.collectorRoots,
      ),
      catalog: catalog,
      helpers: helpers,
      astNodeFor: (fragment) =>
          resolvedNodeInLongForm(buildStep.resolver, fragment),
    );
    final translator = ExpressionTranslator(
      catalog: catalog,
      helpers: helpers,
      customWidgetClassifications: classification.classifications,
      customWidgetBlueprints: classification.blueprints,
    );

    LineInfo? lineInfo;
    if (admission.resolvedLibrary case final resolved?) {
      if (resolved.units.isNotEmpty) lineInfo = resolved.units.first.lineInfo;
    }

    final buildNoticeKeys = <String>{};
    for (final src in result.sources) {
      final translation = translator.translate(
        src.rootExpression,
        sourcePath: assetId.path,
        lineInfo: lineInfo,
        rootState: src.build.state,
        rootParams: src.build.rootParams,
        rootEventHandlers: src.build.eventHandlers,
        rootInlined: src.build.inlined,
      );
      if (_collectTranslationIssues(
        issues,
        translation.issues,
        buildNoticeKeys: buildNoticeKeys,
      )) {
        continue;
      }

      final text = emitRemoteWidgetLibrary(
        translation.dsl,
        rootWidgetName: onboardingScreenRootWidgetName,
        widgetDefinitions: translation.widgetDefinitions,
        widgetDefinitionStates: translation.widgetDefinitionStates,
        rootWidgetState: translation.rootWidgetState,
        customLibraryImports: translation.referencedCustomLibraries,
      );
      try {
        final parsedLibrary = fmt.parseLibraryFile(
          text,
          sourceIdentifier: src.id,
        );
        final declarationIdentity = '${library.identifier}#${src.className}';
        final occurrenceSet = ResolvedRfwCatalogOccurrenceSet.resolve(
          operations: translation.valueOperations,
          parsedLibrary: parsedLibrary,
          input: translation.rfwCatalogOccurrenceResolutionInput(
            artifactProvenance: _rfwOccurrenceSetKey(
              declarationIdentity: declarationIdentity,
              rootWidgetName: onboardingScreenRootWidgetName,
            ),
            sourceLibraryIdentity: library.identifier,
            sourceDeclarationIdentity: declarationIdentity,
            renderEntryNames: const [onboardingScreenRootWidgetName],
          ),
        );
        final lowering = lowerAnalyticsIds(
          text: text,
          library: parsedLibrary,
          sourceIdentifier: src.id,
          location: '${assetId.path}#${src.className}',
          occurrenceSet: occurrenceSet,
        );
        issues.addAll(lowering.issues);
        if (lowering.issues.isNotEmpty) continue;
        final rfwLibrary = lowering.library;
        final validationIssues = validateModelAgainstCatalog(
          rfwLibrary,
          catalog,
          rootLabels: {onboardingScreenRootWidgetName: src.className},
          operations: translation.valueOperations,
        );
        issues.addAll(validationIssues);
        if (issues.isNotEmpty) continue;

        // Derive the screen's capability manifest from the same catalog walk
        // the paywall path uses — so a custom-library onboarding/message/survey
        // screen carries its required libraries (and a derived floor) just like
        // a paywall does. A surface that references a custom library missing a
        // capability version (or an ambiguous shadowed name) fails the build
        // (fail-when-referenced), the same posture as an unknown-widget error.
        final derivation = deriveCapabilityManifest(
          rfwLibrary,
          catalog,
          hoisted: translation.hoisted,
        );
        if (derivation.issues.isNotEmpty) {
          issues.addAll(derivation.issues);
          continue;
        }

        final bytes = fmt.encodeLibraryBlob(canonicalizeLibrary(rfwLibrary));
        await Future.wait<void>([
          buildStep.writeAsString(
            AssetId(assetId.package, '$_outputDir/$stem.rfwtxt'),
            lowering.text,
          ),
          buildStep.writeAsBytes(
            AssetId(assetId.package, '$_outputDir/$stem.rfw'),
            bytes,
          ),
          buildStep.writeAsString(
            AssetId(assetId.package, '$_outputDir/$stem.capability.json'),
            _jsonEncoder.convert(
              CapabilitySidecar(
                blobSha256: CapabilitySidecar.hashBlob(bytes),
                manifest: derivation.manifest!,
              ).toJson(),
            ),
          ),
        ]);
      } on fmt.ParserException catch (e) {
        issues.add(
          Issue(
            code: IssueCode.malformedTranslatorOutput,
            message:
                'Translator emitted invalid onboarding RFW for '
                '"${src.id}": $e '
                '${dslParseFailureDetail(
                  text,
                  e,
                  translation.emissionSources,
                )}',
            location: '${assetId.path}#${src.className}',
          ),
        );
      }
      break;
    }

    if (issues.isNotEmpty) _surfaceIssues(issues);
  }

  Future<void> _writeCanonicalFallback(
    BuildStep buildStep,
    List<ResolvedScreenCompilationInput> screens,
  ) async {
    final compilation = await compileTrackedPackageSurfaces(
      buildStep,
      plan: RestageOutputLocationPlan.fromBuilderOptions(options),
      measurementPolicy: MeasurementCompilerPolicyInput.fromBuilderOptions(
        options,
      ),
      builderKey: 'restage_codegen:${surface.wireName}_screen_codegen',
    );
    if (!compilation.isValid) _surfaceIssues(compilation.issues);
    final publication = compilation.publicationBundle;
    final inputSurface = p.posix.split(buildStep.inputId.path)[1];
    final stem = conventionalOutputStem(
      buildStep.inputId.path,
      'lib/$inputSurface/screens',
    );
    final outputRoot = 'assets/$inputSurface/screens/$stem';
    final selected = screens.first;
    final effectiveSurface = selected.surface?.wireName ?? inputSurface;
    final canonicalRoot = 'assets/$effectiveSurface/screens/${selected.id}';
    final text = publication.ownedOutputs['$canonicalRoot.rfwtxt'];
    final blob = publication.artifacts['$canonicalRoot.rfw'];
    final sidecar = publication.artifacts['$canonicalRoot.capability.json'];
    if (blob == null &&
        _hasMeasurementScreenVariants(
          publication.artifacts.keys,
          canonicalRoot: canonicalRoot,
        )) {
      // Measured flow screens have one artifact per presentation context,
      // leaving no standalone family for this compatibility entrypoint.
      log.warning(
        'Standalone canonical screen artifacts are unavailable for '
        '${selected.id} under Measurement: the aggregate owns one variant '
        'per presentation context.',
      );
      return;
    }
    if (text == null || blob == null || sidecar == null) {
      _surfaceIssues([
        Issue(
          code: IssueCode.missingScreenDescriptor,
          message:
              'Standalone canonical screen fallback could not find the '
              'aggregate artifact family for ${selected.id}.',
          location: buildStep.inputId.path,
        ),
      ]);
    }
    await Future.wait<void>([
      buildStep.writeAsBytes(
        AssetId(buildStep.inputId.package, '$outputRoot.rfwtxt'),
        text,
      ),
      buildStep.writeAsBytes(
        AssetId(buildStep.inputId.package, '$outputRoot.rfw'),
        blob,
      ),
      buildStep.writeAsBytes(
        AssetId(
          buildStep.inputId.package,
          '$outputRoot.capability.json',
        ),
        sidecar,
      ),
    ]);
  }
}

bool _hasMeasurementScreenVariants(
  Iterable<String> artifactKeys, {
  required String canonicalRoot,
}) {
  final dir = p.posix.dirname(canonicalRoot);
  final id = p.posix.basename(canonicalRoot);
  return artifactKeys.any(
    (key) => key.startsWith('$dir/measurement/') && key.endsWith('/$id.rfw'),
  );
}

bool _hasTopLevelDeclaration(LibraryElement library, String name) {
  return _topLevelDeclarations(library).any(
    (element) => _elementHasName(element, name),
  );
}

Iterable<Element> _topLevelDeclarations(LibraryElement library) sync* {
  yield* library.classes;
  yield* library.enums;
  yield* library.mixins;
  yield* library.extensions;
  yield* library.extensionTypes;
  yield* library.typeAliases;
  yield* library.topLevelFunctions;
  yield* library.topLevelVariables;
  yield* library.getters;
  yield* library.setters;
}

bool _elementHasName(Element element, String name) {
  return element.name == name ||
      element.lookupName == name ||
      element.lookupName == '$name=';
}

Surface? _surfaceFromValue(DartObject value) {
  final type = value.type;
  final element = type?.element;
  if (element is! EnumElement ||
      element.name != 'Surface' ||
      !libraryUriMatchesOrigin(
        element.library.identifier,
        _restageSharedOrigin,
      )) {
    return null;
  }
  final wireName = value.getField('wireName')?.toStringValue();
  for (final surface in Surface.values) {
    if (surface.wireName == wireName) return surface;
  }
  return null;
}

Never _surfaceIssues(List<Issue> issues) {
  for (final issue in issues) {
    log.severe(issue.toLogString());
  }
  throw StateError(
    '${issues.length} codegen issue(s) detected; see log above.',
  );
}

bool _collectTranslationIssues(
  List<Issue> target,
  Iterable<Issue> additions, {
  required Set<String> buildNoticeKeys,
  bool sourceIsCanonical = false,
  void Function(Issue issue, bool isCanonical)? appFactoryNoticeCollector,
}) {
  var blocked = false;
  for (final issue in additions) {
    if (issue.code.isBuildNotice) {
      if (issue.code == IssueCode.customWidgetAppFactoryUsed &&
          appFactoryNoticeCollector != null) {
        appFactoryNoticeCollector(issue, sourceIsCanonical);
      } else {
        logBuildNoticeOnce(log, buildNoticeKeys, issue);
      }
      continue;
    }
    target.add(issue);
    blocked = true;
  }
  return blocked;
}
