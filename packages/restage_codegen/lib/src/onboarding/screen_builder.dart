// Internal builder implementation is reached through documented factories.
// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:convert';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:build/build.dart';
import 'package:path/path.dart' as p;
import 'package:restage_codegen/src/capability_derivation.dart';
import 'package:restage_codegen/src/catalog_loader.dart';
import 'package:restage_codegen/src/catalog_validator.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/onboarding/onboarding_helpers.dart';
import 'package:restage_codegen/src/onboarding/onboarding_source_visitor.dart';
import 'package:restage_codegen/src/rfw_emitter.dart';
import 'package:restage_codegen/src/syntax_diagnostics.dart';
import 'package:restage_codegen/src/widget_classifier.dart';
import 'package:restage_shared/restage_shared.dart' show CapabilitySidecar;
import 'package:restage_shared/rfw_formats.dart' as fmt;

const String _kSourceDir = 'lib/onboarding/screens';
const String _kOutputDir = 'assets/onboarding/screens';
const JsonEncoder _jsonEncoder = JsonEncoder.withIndent('  ');

final class OnboardingScreenBuilder implements Builder {
  OnboardingScreenBuilder(this.options);

  final BuilderOptions options;

  @override
  Map<String, List<String>> get buildExtensions => const {
        '$_kSourceDir/{{name}}.dart': [
          '$_kSourceDir/{{name}}.rsscreen.g.dart',
          '$_kOutputDir/{{name}}.rfwtxt',
          '$_kOutputDir/{{name}}.rfw',
          '$_kOutputDir/{{name}}.capability.json',
        ],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final assetId = buildStep.inputId;
    if (!await buildStep.resolver.isLibrary(assetId)) return;

    final sourceText = await buildStep.readAsString(assetId);
    final library = await buildStep.resolver.libraryFor(
      assetId,
      allowSyntaxErrors: true,
    );
    final result = await visitOnboardingSources(library, assetId);
    final issues = [...result.issues];

    // The source resolved with `allowSyntaxErrors: true`, so a malformed token
    // whose parser error-recovery yields a structurally-valid tree could
    // otherwise ship a clean blob with the bad token silently dropped — or,
    // if recovery erased the annotated class, silently skip at the no-sources
    // early-return below. Surface genuine syntactic errors here, before that
    // early-return, so a malformed screen source is always diagnosed.
    final resolved = await library.session.getResolvedLibraryByElement(library);
    if (resolved is ResolvedLibraryResult && resolved.units.isNotEmpty) {
      issues.addAll(syntacticErrorIssues(resolved, sourcePath: assetId.path));
    }

    if (result.sources.isEmpty && issues.isEmpty) return;

    final stem = p.basenameWithoutExtension(assetId.path);
    final expectedPart = '$stem.rsscreen.g.dart';
    if (!_hasPartDirective(sourceText, expectedPart)) {
      issues.add(
        Issue(
          code: IssueCode.missingPartDirective,
          message: "Missing `part '$expectedPart';` directive.",
          location: assetId.path,
        ),
      );
    }

    for (final src in result.sources) {
      if (src.id != stem) {
        issues.add(
          Issue(
            code: IssueCode.filenameMismatch,
            message: "Onboarding screen id '${src.id}' does not match the "
                "file name '$stem.dart'.",
            location: '${assetId.path}#${src.className}',
          ),
        );
      }
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
    if (issues.isNotEmpty) _surfaceIssues(issues);

    final catalog = await loadMergedCatalog(buildStep);
    final helpers = HelperRegistry()..registerAll(onboardingHelpers);
    final classification = await classifyReferencedCustomWidgets(
      rootExpressions: result.sources.map((source) => source.rootExpression),
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
    if (resolved is ResolvedLibraryResult && resolved.units.isNotEmpty) {
      lineInfo = resolved.units.first.lineInfo;
    }

    for (final src in result.sources) {
      final translation = translator.translate(
        src.rootExpression,
        sourcePath: assetId.path,
        lineInfo: lineInfo,
        rootState: src.build.state,
        rootEventHandlers: src.build.eventHandlers,
      );
      issues.addAll(translation.issues);
      if (translation.issues.isNotEmpty) continue;

      final text = emitRemoteWidgetLibrary(
        translation.dsl,
        rootWidgetName: onboardingScreenRootWidgetName,
        widgetDefinitions: translation.widgetDefinitions,
        widgetDefinitionStates: translation.widgetDefinitionStates,
        rootWidgetState: translation.rootWidgetState,
      );
      try {
        final rfwLibrary = fmt.parseLibraryFile(text, sourceIdentifier: src.id);
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
            AssetId(assetId.package, '$_kSourceDir/$stem.rsscreen.g.dart'),
            _emitDescriptor(stem, src),
          ),
          buildStep.writeAsString(
            AssetId(assetId.package, '$_kOutputDir/$stem.rfwtxt'),
            text,
          ),
          buildStep.writeAsBytes(
            AssetId(assetId.package, '$_kOutputDir/$stem.rfw'),
            bytes,
          ),
          buildStep.writeAsString(
            AssetId(assetId.package, '$_kOutputDir/$stem.capability.json'),
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
}

bool _hasPartDirective(String source, String expectedPart) {
  final pattern = RegExp(
    "part\\s+['\"]${RegExp.escape(expectedPart)}['\"]\\s*;",
  );
  return pattern.hasMatch(source);
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

String _emitDescriptor(String stem, OnboardingScreenSourceFound src) => '''
part of '$stem.dart';

abstract final class ${src.className}Descriptor {
  const ${src.className}Descriptor._();

  static const OnboardingScreenRef ref = OnboardingScreenRef(
    id: '${src.id}',
    artifactPath: '${src.id}.rfw',
    version: ${src.version},
    minClient: ${src.minClient},
  );
}
''';

Never _surfaceIssues(List<Issue> issues) {
  for (final issue in issues) {
    log.severe(issue.toLogString());
  }
  throw StateError(
    '${issues.length} codegen issue(s) detected; see log above.',
  );
}
