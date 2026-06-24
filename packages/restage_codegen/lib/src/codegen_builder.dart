import 'dart:async';
import 'dart:convert';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:build/build.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:restage_codegen/src/capability_derivation.dart';
import 'package:restage_codegen/src/catalog_loader.dart';
import 'package:restage_codegen/src/catalog_validator.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/library_visitor.dart';
import 'package:restage_codegen/src/production_helpers.dart';
import 'package:restage_codegen/src/rfw_emitter.dart';
import 'package:restage_codegen/src/source_visitor.dart';
import 'package:restage_codegen/src/syntax_diagnostics.dart';
import 'package:restage_codegen/src/widget_classifier.dart';
import 'package:restage_shared/restage_shared.dart' show CapabilitySidecar;
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Per-build container for the merged catalog. The build system creates
/// a fresh instance for each build pass via [_catalogResource]; the
/// inner cache shares one load across every paywall input in that pass
/// and is dropped automatically between passes (so `--watch` mode
/// re-reads `catalog.json` after a change).
///
/// Every consumer's [BuildStep] still registers `catalog.json` as a
/// read dependency via `canRead`, even on cache hits — without it,
/// `build_runner` would only re-trigger the first paywall input when a
/// catalog file changes, leaving subsequent paywalls stale until some
/// other input invalidates them.
/// Per-build container for the merged catalog, keyed by the input package.
/// The build system creates a fresh instance for each build pass via
/// [_catalogResource]; the inner cache shares one load across every input of a
/// given package in that pass, and is dropped automatically between passes (so
/// `--watch` mode re-reads `catalog.json` after a change). Keying by package
/// keeps each package's own custom catalog from leaking to another in a
/// multi-package build.
///
/// Every consumer's [BuildStep] still registers `catalog.json` as a read
/// dependency via `canRead`, even on cache hits — without it, `build_runner`
/// would only re-trigger the first input when a catalog file changes, leaving
/// subsequent inputs stale until some other input invalidates them.
@visibleForTesting
class CatalogPerBuildCache {
  /// Creates a per-build cache. [load] defaults to [loadMergedCatalog]; tests
  /// inject a stub to assert the cache keys by input package without real
  /// cross-package asset reads.
  CatalogPerBuildCache({Future<Catalog> Function(BuildStep)? load})
      : _load = load ?? loadMergedCatalog;

  final Future<Catalog> Function(BuildStep) _load;

  // Keyed by input package: the merged catalog is package-specific (it folds in
  // `buildStep.inputId.package`'s own custom catalog), so a single cross-pass
  // entry would serve one package's custom widgets to another in a build that
  // spans multiple packages. Within a package, BuildSteps still share one load.
  final Map<String, Future<Catalog>> _inflightByPackage = {};

  /// Returns the merged catalog for [buildStep]'s package — loaded once per
  /// package and shared across that package's BuildSteps — registering the
  /// built-in catalog reads on every call so watch-mode invalidation stays
  /// correct.
  Future<Catalog> getOrLoad(BuildStep buildStep) async {
    for (final id in builtInCatalogAssetIds.values) {
      await buildStep.canRead(id);
    }
    final package = buildStep.inputId.package;
    return _inflightByPackage[package] ??= _load(buildStep);
  }
}

final Resource<CatalogPerBuildCache> _catalogResource =
    Resource<CatalogPerBuildCache>(CatalogPerBuildCache.new);

const String _kSourceDir = 'lib/paywalls';
const String _kOutputDir = 'assets/paywalls';
const String _kOnboardingScreenOutputDir = 'assets/onboarding/screens';
const JsonEncoder _jsonEncoder = JsonEncoder.withIndent('  ');

/// Orchestrates the codegen build pass.
///
/// Two parallel input shapes are declared in `build.yaml`:
///
/// * `lib/paywalls/{{name}}.dart` — Dart authoring path. Resolves the
///   library, dispatches it to every registered [LibraryVisitor] (which
///   collect `@PaywallSource` findings on the shared [CodegenBuildState]),
///   then for each discovered paywall: validates the file stem matches
///   the annotation `id`, translates the `build()` body via
///   [ExpressionTranslator], wraps the fragment in the canonical RFW
///   library envelope, parses + encodes via the shared `rfw_formats`,
///   and writes `assets/paywalls/{{name}}.rfwtxt` + `.rfw`.
///
/// * `lib/paywalls/{{name}}.rfwtxt` — hand-authored DSL path. Parses the
///   input via the shared `rfw_formats`, encodes to the binary blob, and
///   writes `assets/paywalls/{{name}}.rfw`. Author errors surface as a
///   `malformedRawDsl` issue.
final class RestageCodegenBuilder implements Builder {
  /// Production constructor — typically reached via the
  /// `restageCodegenBuilder` factory declared in `lib/builder.dart`.
  /// Tests construct with a custom `visitors` list to exercise the
  /// registration shape.
  RestageCodegenBuilder(this.options, {List<LibraryVisitor>? visitors})
      : _visitors = visitors == null
            ? const <LibraryVisitor>[]
            : List.unmodifiable(visitors);

  /// `BuilderOptions` injected by build_runner.
  final BuilderOptions options;

  final List<LibraryVisitor> _visitors;

  @override
  Map<String, List<String>> get buildExtensions => const {
        '$_kSourceDir/{{name}}.dart': [
          '$_kOutputDir/{{name}}.rfwtxt',
          '$_kOutputDir/{{name}}.rfw',
          '$_kOutputDir/{{name}}.capability.json',
          '$_kOutputDir/{{name}}.navplan.json',
          '$_kOnboardingScreenOutputDir/paywall_{{name}}.rfw',
        ],
        '$_kSourceDir/{{name}}.rfwtxt': [
          '$_kOutputDir/{{name}}.rfw',
          '$_kOutputDir/{{name}}.capability.json',
        ],
      };

  @override
  Future<void> build(BuildStep buildStep) {
    if (buildStep.inputId.path.endsWith('.rfwtxt')) {
      return _buildFromRawDsl(buildStep);
    }
    return _buildFromDart(buildStep);
  }

  Future<void> _buildFromDart(BuildStep buildStep) async {
    final assetId = buildStep.inputId;
    if (!await buildStep.resolver.isLibrary(assetId)) return;
    final library = await buildStep.resolver.libraryFor(
      assetId,
      allowSyntaxErrors: true,
    );

    final catalogCache = await buildStep.fetchResource(_catalogResource);
    final catalog = await catalogCache.getOrLoad(buildStep);

    final state = CodegenBuildState(
      library: library,
      assetId: assetId,
      catalog: catalog,
    );
    for (final visitor in _visitors) {
      await visitor.visit(state);
    }

    // Resolve once for line info and syntactic-error detection. The source
    // resolved with `allowSyntaxErrors: true`, so a malformed token whose
    // parser-recovery yields a structurally-valid tree could otherwise ship a
    // clean blob with the bad token silently dropped — or, if recovery erased
    // the `@PaywallSource` class/annotation, silently skip at the no-sources
    // early-return below. Surface genuine syntactic errors here, before that
    // early-return, so a malformed file in the paywall source directory is
    // always diagnosed rather than dropped.
    LineInfo? lineInfo;
    final resolvedLib =
        await library.session.getResolvedLibraryByElement(library);
    if (resolvedLib is ResolvedLibraryResult && resolvedLib.units.isNotEmpty) {
      lineInfo = resolvedLib.units.first.lineInfo;
      state.issues.addAll(
        syntacticErrorIssues(resolvedLib, sourcePath: assetId.path),
      );
    } else {
      // Issue locations downgrade to byte offsets when the resolved library
      // can't be reached. The visitor pipeline has already surfaced an
      // `analyzerResolutionFailed` issue for the underlying cause; this
      // warning explains the asymmetric symptom of "issues suddenly carry
      // offsets instead of file:line:col" so debugging doesn't chase a
      // different thread.
      log.warning(
        'No LineInfo for ${assetId.path}: getResolvedLibraryByElement '
        'returned ${resolvedLib.runtimeType}. Issue locations will use '
        'byte offsets.',
      );
    }

    if (state.paywallSources.isEmpty && state.issues.isEmpty) {
      // No annotated classes and no errors — silent skip.
      return;
    }

    final stem = p.basenameWithoutExtension(assetId.path);

    // Filename-vs-id alignment. The runtime loads paywalls by id; the
    // generator names artifacts after the input file stem. Forcing the
    // two to match makes the convention explicit instead of letting an
    // author write @PaywallSource(id: 'foo') in bar.dart and get bar.rfw
    // that RestagePaywall(id: 'foo') will never find.
    for (final src in state.paywallSources) {
      if (src.id != stem) {
        state.issues.add(
          Issue(
            code: IssueCode.filenameMismatch,
            message: "Paywall id '${src.id}' does not match the file name "
                "'$stem.dart'. Rename the file to '${src.id}.dart', or "
                'change the @PaywallSource(id:) value to match.',
            location: '${assetId.path}#${src.className}',
          ),
        );
      }
    }

    // Bail before any output writes if validation already rejected the
    // input — skipping the translation loop prevents .rfwtxt / .rfw from
    // landing at a path the runtime would never look up.
    if (state.issues.isNotEmpty) {
      _surfaceIssues(state.issues);
    }

    final helpers = productionPaywallHelperRegistry();

    // Classification pre-pass — see classifyReferencedCustomWidgets.
    final classification = await classifyReferencedCustomWidgets(
      rootExpressions: state.paywallSources.map((s) => s.rootExpression),
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

    for (final src in state.paywallSources) {
      final standaloneTranslation = translator.translate(
        src.rootExpression,
        entryId: src.id,
        sourcePath: assetId.path,
        lineInfo: lineInfo,
        rootState: src.build.state,
        rootEventHandlers: src.build.eventHandlers,
        buildContextParameter: src.build.buildContextParameter,
      );
      final adapterTranslation = (standaloneTranslation.navigation != null ||
              standaloneTranslation.suppressed)
          ? translator.translate(
              src.rootExpression,
              entryId: src.id,
              sourcePath: assetId.path,
              lineInfo: lineInfo,
              rootState: src.build.state,
              rootEventHandlers: src.build.eventHandlers,
              buildContextParameter: src.build.buildContextParameter,
              flowScreenContext: true,
            )
          : standaloneTranslation;
      _addIssues(state.issues, standaloneTranslation.issues);
      _addIssues(state.issues, adapterTranslation.issues);
      // A build notice (e.g. an announced idiom auto-substitution) annotates a
      // complete, correct translation — it must not block the emit. Only a real
      // translation error (an expression that could not be lowered) skips it.
      final standaloneBlocked = standaloneTranslation.suppressed ||
          standaloneTranslation.issues.any((i) => !i.code.isBuildNotice);
      final adapterBlocked =
          adapterTranslation.issues.any((i) => !i.code.isBuildNotice);

      final writes = <Future<void>>[];
      if (!standaloneBlocked) {
        final paywallText = emitPaywallLibrary(
          standaloneTranslation.dsl,
          widgetDefinitions: standaloneTranslation.widgetDefinitions,
          widgetDefinitionStates: standaloneTranslation.widgetDefinitionStates,
          rootWidgetState: standaloneTranslation.rootWidgetState,
        );
        final rfwLibrary = _parseTranslatedLibrary(
          paywallText,
          sourceIdentifier: src.id,
          src: src,
          state: state,
        );
        if (rfwLibrary != null) {
          final validationIssues = validateModelAgainstCatalog(
            rfwLibrary,
            catalog,
          );
          if (validationIssues.isEmpty) {
            final derivation = deriveCapabilityManifest(rfwLibrary, catalog);
            if (derivation.issues.isNotEmpty) {
              // A surface referencing a custom library that declares no
              // capability version fails the build (fail-when-referenced) — the
              // same posture as an unknown-widget validation error.
              _addIssues(state.issues, derivation.issues);
            } else {
              final paywallBytes = fmt.encodeLibraryBlob(rfwLibrary);
              writes
                ..add(
                  buildStep.writeAsString(
                    AssetId(assetId.package, '$_kOutputDir/$stem.rfwtxt'),
                    paywallText,
                  ),
                )
                ..add(
                  buildStep.writeAsBytes(
                    AssetId(assetId.package, '$_kOutputDir/$stem.rfw'),
                    paywallBytes,
                  ),
                )
                ..add(
                  buildStep.writeAsString(
                    AssetId(
                      assetId.package,
                      '$_kOutputDir/$stem.capability.json',
                    ),
                    _jsonEncoder.convert(
                      CapabilitySidecar(
                        blobSha256: CapabilitySidecar.hashBlob(paywallBytes),
                        manifest: derivation.manifest!,
                      ).toJson(),
                    ),
                  ),
                );
            }
          } else {
            _addIssues(state.issues, validationIssues);
          }
        }
      }

      if (!adapterBlocked) {
        final onboardingScreenText = emitRemoteWidgetLibrary(
          adapterTranslation.dsl,
          rootWidgetName: onboardingScreenRootWidgetName,
          widgetDefinitions: adapterTranslation.widgetDefinitions,
          widgetDefinitionStates: adapterTranslation.widgetDefinitionStates,
          rootWidgetState: adapterTranslation.rootWidgetState,
        );
        final onboardingScreenLibrary = _parseTranslatedLibrary(
          onboardingScreenText,
          sourceIdentifier: 'paywall_${src.id}',
          src: src,
          state: state,
        );
        if (onboardingScreenLibrary != null) {
          final validationIssues = validateModelAgainstCatalog(
            onboardingScreenLibrary,
            catalog,
          );
          if (validationIssues.isEmpty) {
            final onboardingScreenBytes =
                fmt.encodeLibraryBlob(onboardingScreenLibrary);
            writes.add(
              buildStep.writeAsBytes(
                AssetId(
                  assetId.package,
                  '$_kOnboardingScreenOutputDir/paywall_$stem.rfw',
                ),
                onboardingScreenBytes,
              ),
            );
            // NOTE: no capability sidecar is emitted for a paywall rendered as
            // a flow screen (`paywall_<stem>.capability.json`). Its only
            // consumer is a navigation-paywall HOSTED flow publish, which is
            // deferred (the bundled flow controller reads the blob directly,
            // not a sidecar). Tracked as a follow-up to land with that.
            final navigation = adapterTranslation.navigation;
            if (navigation != null) {
              writes.add(
                buildStep.writeAsString(
                  AssetId(
                    assetId.package,
                    '$_kOutputDir/$stem.navplan.json',
                  ),
                  _jsonEncoder.convert(navigation.toJson()),
                ),
              );
            }
          } else {
            _addIssues(state.issues, validationIssues);
          }
        }
      }

      if (writes.isNotEmpty) {
        await Future.wait<void>(writes);
      }

      // Per-input-file output model: only the first valid @PaywallSource
      // contributes outputs. The visitor already deduplicates within-file
      // by id, so this break only matters when multiple distinct ids
      // coexist in one source file (unsupported on purpose).
      break;
    }

    if (state.issues.isNotEmpty) {
      _surfaceIssues(state.issues);
    }
  }

  fmt.RemoteWidgetLibrary? _parseTranslatedLibrary(
    String source, {
    required String sourceIdentifier,
    required PaywallSourceFound src,
    required CodegenBuildState state,
  }) {
    try {
      return fmt.parseLibraryFile(source, sourceIdentifier: sourceIdentifier);
    } on fmt.ParserException catch (e) {
      // Translator emitted DSL that failed to parse — codegen bug, not author
      // error. Convert to a structured issue so the author sees the file/source
      // that triggered it. This is per-artifact: one malformed library does
      // not preclude attempting the sibling standalone/adapter artifact.
      state.issues.add(
        Issue(
          code: IssueCode.malformedTranslatorOutput,
          message: 'Translator emitted DSL that failed to parse for '
              '"${src.id}" ($sourceIdentifier): $e. This is a codegen bug.',
          location: '${src.assetId.path}#${src.className}',
        ),
      );
      return null;
    }
  }

  void _addIssues(List<Issue> target, Iterable<Issue> issues) {
    final seen = {
      for (final issue in target) _issueKey(issue),
    };
    for (final issue in issues) {
      if (seen.add(_issueKey(issue))) target.add(issue);
    }
  }

  String _issueKey(Issue issue) =>
      '${issue.code.name}\u0000${issue.message}\u0000${issue.location}';

  Future<void> _buildFromRawDsl(BuildStep buildStep) async {
    final assetId = buildStep.inputId;
    final stem = p.basenameWithoutExtension(assetId.path);
    final source = await buildStep.readAsString(assetId);

    final issues = <Issue>[];
    try {
      final library = fmt.parseLibraryFile(source, sourceIdentifier: stem);

      // Catalog-validate hand-authored DSL too. The author bypassed
      // the Dart-side translator that would have caught unknown
      // widgets at construction time, so the model walk is the only
      // gate keeping unrecognised widget/property usage out of the
      // emitted blob.
      final catalogCache = await buildStep.fetchResource(_catalogResource);
      final catalog = await catalogCache.getOrLoad(buildStep);
      final validationIssues = validateModelAgainstCatalog(library, catalog);
      if (validationIssues.isNotEmpty) {
        issues.addAll(validationIssues);
      } else {
        final derivation = deriveCapabilityManifest(library, catalog);
        if (derivation.issues.isNotEmpty) {
          issues.addAll(derivation.issues);
        } else {
          final bytes = fmt.encodeLibraryBlob(library);
          await buildStep.writeAsBytes(
            AssetId(assetId.package, '$_kOutputDir/$stem.rfw'),
            bytes,
          );
          await buildStep.writeAsString(
            AssetId(assetId.package, '$_kOutputDir/$stem.capability.json'),
            _jsonEncoder.convert(
              CapabilitySidecar(
                blobSha256: CapabilitySidecar.hashBlob(bytes),
                manifest: derivation.manifest!,
              ).toJson(),
            ),
          );
        }
      }
    } on fmt.ParserException catch (e) {
      issues.add(
        Issue(
          code: IssueCode.malformedRawDsl,
          message: 'Hand-authored RFW DSL at ${assetId.path} could not be '
              'parsed: $e',
          location: assetId.path,
        ),
      );
    }

    if (issues.isNotEmpty) {
      _surfaceIssues(issues);
    }
  }

  void _surfaceIssues(List<Issue> issues) {
    // Build notices annotate a successful translation — log them, but they do
    // not fail the build. Everything else is a real error.
    final errors = <Issue>[];
    for (final issue in issues) {
      if (issue.code.isBuildNotice) {
        log.info(issue.toLogString());
      } else {
        log.severe(issue.toLogString());
        errors.add(issue);
      }
    }
    if (errors.isEmpty) return;
    throw StateError(
      '${errors.length} codegen issue(s) detected; see log above.',
    );
  }
}
