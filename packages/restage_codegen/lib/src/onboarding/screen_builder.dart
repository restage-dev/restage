// Builder implementation is reached through documented factories.
// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:build/build.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:restage_codegen/src/analytics_id_lowering.dart';
import 'package:restage_codegen/src/annotation_lookup.dart';
import 'package:restage_codegen/src/capability_derivation.dart';
import 'package:restage_codegen/src/catalog_loader.dart';
import 'package:restage_codegen/src/catalog_validator.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_codegen/src/measurement/measurement_route_emission.dart';
import 'package:restage_codegen/src/onboarding/onboarding_helpers.dart';
import 'package:restage_codegen/src/rfw_emitter.dart';
import 'package:restage_codegen/src/screen_source_admission.dart';
import 'package:restage_codegen/src/source_state.dart';
import 'package:restage_codegen/src/surface_publication/output_placement.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:restage_codegen/src/widget_classifier.dart';
import 'package:restage_shared/restage_shared.dart'
    show CapabilityManifest, CapabilitySidecar, Surface;
import 'package:restage_shared/rfw_formats.dart' as fmt;

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
  })  : screens = List.unmodifiable(screens),
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
  })  : blob = Uint8List.fromList(blob),
        capabilitySidecar = Uint8List.fromList(capabilitySidecar),
        analyticsIdDeclarations = List.unmodifiable(analyticsIdDeclarations);

  final ResolvedScreenCompilationInput input;
  final String text;
  final Uint8List blob;
  final Uint8List capabilitySidecar;
  final CapabilityManifest capabilities;

  /// Frozen resolved RFW catalog calls shared by both compiler passes.
  final fmt.ResolvedRfwCatalogOccurrenceSet rfwCatalogOccurrenceSet;

  /// Labels extracted before validation and canonical encoding.
  final List<AnalyticsIdDeclaration> analyticsIdDeclarations;
}

@immutable
final class ResolvedScreenCompilationResult {
  ResolvedScreenCompilationResult({
    required List<CompiledResolvedScreen> screens,
    required List<Issue> issues,
  })  : screens = List.unmodifiable(screens),
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
  AssetId assetId,
) async {
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
    final explicitId =
        idValue == null || idValue.isNull ? null : idValue.toStringValue();
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
      sourceClass: declaration,
      library: library,
      astNodeFor: resolvedAstNodeFor,
      issues: issues,
      location: location,
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
        message: 'At most one @Screen declaration per library may omit id; '
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
  Map<String, fmt.ResolvedRfwCatalogOccurrenceSet> rfwCatalogOccurrenceSets =
      const <String, fmt.ResolvedRfwCatalogOccurrenceSet>{},
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
        buildStep.resolver.astNodeFor(fragment, resolve: true),
  );
  ExpressionTranslator translatorFor(
    MeasurementRouteEmissionPlan? measurementRoutePlan,
  ) =>
      ExpressionTranslator(
        catalog: catalog,
        helpers: helpers,
        customWidgetClassifications: classification.classifications,
        customWidgetBlueprints: classification.blueprints,
        measurementRouteEmissionPlan: measurementRoutePlan,
      );
  final compiled = <CompiledResolvedScreen>[];
  for (final source in ordered) {
    final resolved =
        await source.declaration.library.session.getResolvedLibraryByElement(
      source.declaration.library,
    );
    final lineInfo =
        resolved is ResolvedLibraryResult && resolved.units.isNotEmpty
            ? resolved.units.first.lineInfo
            : null;
    final translation = translatorFor(
      measurementRoutePlans[source.declarationIdentity],
    ).translate(
      source.build.rootExpression,
      sourcePath: source.assetId.path,
      lineInfo: lineInfo,
      rootState: source.build.state,
      rootParams: source.build.rootParams,
      rootEventHandlers: source.build.eventHandlers,
      rootLocalBindings: source.build.localBindings,
    );
    if (_collectTranslationIssues(
      issues,
      translation.issues,
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
            message: 'Final Measurement screen emission requires its frozen '
                'RFW occurrence evidence.',
            location: '${source.assetId.path}#'
                '${source.declaration.name ?? '<unnamed>'}',
          ),
        );
        continue;
      }
      final resolvedOccurrenceSet = frozenOccurrenceSet ??
          fmt.ResolvedRfwCatalogOccurrenceSet.resolve(
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
      final occurrenceRebinding =
          frozenOccurrenceSet?.rebindFinalLibrary(parsedLibrary);
      final lowering = lowerAnalyticsIds(
        text: text,
        library: parsedLibrary,
        sourceIdentifier: source.id,
        location: '${source.assetId.path}#'
            '${source.declaration.name ?? '<unnamed>'}',
        occurrenceSet:
            frozenOccurrenceSet == null ? resolvedOccurrenceSet : null,
        occurrenceRebinding: occurrenceRebinding,
      );
      issues.addAll(lowering.issues);
      if (lowering.issues.isNotEmpty) continue;
      final library = lowering.library;
      final validationIssues = validateModelAgainstCatalog(library, catalog);
      issues.addAll(validationIssues);
      if (validationIssues.isNotEmpty) continue;
      final derivation = deriveCapabilityManifest(library, catalog);
      issues.addAll(derivation.issues);
      if (derivation.issues.isNotEmpty || derivation.manifest == null) continue;
      final blob = fmt.encodeLibraryBlob(library);
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
          rfwCatalogOccurrenceSet: resolvedOccurrenceSet,
          analyticsIdDeclarations: lowering.declarations,
        ),
      );
    } on fmt.ParserException catch (error) {
      issues.add(
        Issue(
          code: IssueCode.malformedTranslatorOutput,
          message: 'Translator emitted invalid screen RFW for '
              '"${source.id}": $error.',
          location: '${source.assetId.path}#'
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
    final canonical = await inspectCanonicalScreenDeclarations(
      library,
      assetId,
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
    );
    final result = admission.visitorResult;
    final issues = [...admission.issues];

    if (!admission.participates) return;

    final stem = p.basenameWithoutExtension(assetId.path);
    for (final src in result.sources) {
      final descriptorName = '${src.className}Descriptor';
      if (_hasTopLevelDeclaration(library, descriptorName)) {
        issues.add(
          Issue(
            code: IssueCode.generatedSymbolCollision,
            message: 'Generated descriptor symbol $descriptorName already '
                'exists in ${assetId.path}.',
            location: '${assetId.path}#$descriptorName',
          ),
        );
      }
    }
    if (!admission.isAdmitted || issues.isNotEmpty) _surfaceIssues(issues);

    final catalog = await loadMergedCatalog(buildStep);
    final helpers = HelperRegistry()..registerAll(onboardingHelpers);
    final classification = await classifyReferencedCustomWidgets(
      rootExpressions:
          result.sources.expand((source) => source.build.collectorRoots),
      catalog: catalog,
      helpers: helpers,
      astNodeFor: (fragment) =>
          buildStep.resolver.astNodeFor(fragment, resolve: true),
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
        rootLocalBindings: src.build.localBindings,
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
        final occurrenceSet = fmt.ResolvedRfwCatalogOccurrenceSet.resolve(
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
        final validationIssues =
            validateModelAgainstCatalog(rfwLibrary, catalog);
        issues.addAll(validationIssues);
        if (issues.isNotEmpty) continue;

        // Derive the screen's capability manifest from the same catalog walk
        // the paywall path uses — so a custom-library onboarding/message/survey
        // screen carries its required libraries (and a derived floor) just like
        // a paywall does. A surface that references a custom library missing a
        // capability version (or an ambiguous shadowed name) fails the build
        // (fail-when-referenced), the same posture as an unknown-widget error.
        final derivation = deriveCapabilityManifest(rfwLibrary, catalog);
        if (derivation.issues.isNotEmpty) {
          issues.addAll(derivation.issues);
          continue;
        }

        final bytes = fmt.encodeLibraryBlob(rfwLibrary);
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
            message: 'Translator emitted invalid onboarding RFW for '
                '"${src.id}": $e.',
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
      plan: RestageOutputPlacementPlan.fromBuilderOptions(options),
      measurementPolicy:
          MeasurementCompilerPolicyInput.fromBuilderOptions(options),
      builderKey: 'restage_codegen:${surface.wireName}_screen_codegen',
    );
    if (!compilation.isValid) _surfaceIssues(compilation.issues);
    final publication = compilation.publicationBundle;
    final stem = p.basenameWithoutExtension(buildStep.inputId.path);
    final inputSurface = p.posix.split(buildStep.inputId.path)[1];
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
          message: 'Standalone canonical screen fallback could not find the '
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
