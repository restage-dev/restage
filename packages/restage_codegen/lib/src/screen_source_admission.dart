// Internal admission facts are consumed only by code-generation builders.
// ignore_for_file: public_member_api_docs

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/annotation_lookup.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/onboarding/onboarding_source_visitor.dart';
import 'package:restage_codegen/src/syntax_diagnostics.dart';
import 'package:restage_codegen/src/target_routing_reader.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart' show EmitTarget;

const String _restageOrigin = 'package:restage';
const Set<String> _screenSourceAnnotations = {
  'ScreenSource',
  'OnboardingSource',
};
final RegExp _screenLibraryPath = RegExp(
  r'^lib/(onboarding|message|survey)/screens/([^/]+)\.dart$',
);

bool isRfwScreenSourceInput(AssetId assetId) =>
    _screenLibraryPath.hasMatch(assetId.path);

@immutable
final class ScreenSourceAdmission {
  ScreenSourceAdmission({
    required this.resolvedLibrary,
    required this.visitorResult,
    required List<ClassElement> annotatedClasses,
    required List<Issue> issues,
  })  : annotatedClasses = List.unmodifiable(annotatedClasses),
        issues = List.unmodifiable(issues);

  final ResolvedLibraryResult? resolvedLibrary;
  final OnboardingVisitorResult visitorResult;
  final List<ClassElement> annotatedClasses;
  final List<Issue> issues;

  bool get participates => annotatedClasses.isNotEmpty || issues.isNotEmpty;

  bool get isAdmitted =>
      issues.isEmpty &&
      annotatedClasses.length == 1 &&
      visitorResult.sources.length == 1;

  ClassElement? get admittedClass =>
      isAdmitted ? annotatedClasses.single : null;

  OnboardingScreenSourceFound? get admittedSource =>
      isAdmitted ? visitorResult.sources.single : null;
}

/// Applies the one authoritative admission contract shared by RFW and native
/// `ScreenSource` targets.
///
/// The direct source read deliberately happens here so a source that
/// participates in sibling generation is an explicit build-asset dependency,
/// not merely an analyzer side effect.
Future<ScreenSourceAdmission> inspectScreenSourceAdmission(
  BuildStep buildStep, {
  required AssetId assetId,
  required LibraryElement library,
}) async {
  final sourceText = await buildStep.readAsString(assetId);
  final sourceUnit = parseString(
    content: sourceText,
    path: assetId.path,
    throwIfDiagnostics: false,
  ).unit;
  final annotatedClasses = library.classes
      .where(
        (cls) =>
            firstAnnotationFromOriginAny(
              cls,
              _screenSourceAnnotations,
              _restageOrigin,
            ) !=
            null,
      )
      .toList(growable: false);
  final visitorResult = await visitOnboardingSources(library, assetId);
  final issues = <Issue>[...visitorResult.issues];

  final resolved = await library.session.getResolvedLibraryByElement(library);
  final resolvedLibrary = resolved is ResolvedLibraryResult ? resolved : null;
  if (resolvedLibrary != null && resolvedLibrary.units.isNotEmpty) {
    issues.addAll(
      syntacticErrorIssues(resolvedLibrary, sourcePath: assetId.path),
    );
  }

  // An ordinary Dart library is not a ScreenSource input. The RFW builders
  // historically skip such files even when they sit under a scheduled screen
  // directory, and native package indexes must retain that behavior.
  if (annotatedClasses.isEmpty && visitorResult.issues.isEmpty) {
    return ScreenSourceAdmission(
      resolvedLibrary: resolvedLibrary,
      visitorResult: visitorResult,
      annotatedClasses: annotatedClasses,
      issues: issues,
    );
  }

  final pathMatch = _screenLibraryPath.firstMatch(assetId.path);
  final stem = pathMatch?.group(2) ?? _fileStem(assetId.path);
  if (pathMatch == null) {
    issues.add(
      Issue(
        code: IssueCode.invalidScreenSourceLocation,
        message: '@ScreenSource libraries must be authored at exactly '
            '`lib/<onboarding|message|survey>/screens/<id>.dart`. Found '
            '`${assetId.path}`.',
        location: assetId.path,
      ),
    );
  }

  final expectedPart = '$stem.rsscreen.g.dart';
  if (!_hasPartDirective(sourceUnit, expectedPart)) {
    issues.add(
      Issue(
        code: IssueCode.missingPartDirective,
        message: "Missing `part '$expectedPart';` directive.",
        location: assetId.path,
      ),
    );
  }

  if (annotatedClasses.length != 1) {
    issues.add(
      Issue(
        code: IssueCode.invalidScreenSourceCount,
        message: 'A ScreenSource input library must declare exactly one '
            '@ScreenSource class; found ${annotatedClasses.length}.',
        location: assetId.path,
      ),
    );
  }

  for (final source in visitorResult.sources) {
    if (source.id == stem) continue;
    issues.add(
      Issue(
        code: IssueCode.filenameMismatch,
        message: "Screen id '${source.id}' does not match the file name "
            "'$stem.dart'.",
        location: '${assetId.path}#${source.className}',
      ),
    );
  }

  for (final cls in annotatedClasses) {
    for (final target in EmitTarget.values) {
      final routing = readWidgetTargetRouting(cls, assetId, target: target);
      issues.addAll(routing.issues);
      for (final location in routing.configuredLocations) {
        issues.add(
          Issue(
            code: IssueCode.invalidTargetConfigPlacement,
            message: '${target.name}.Config enabled is legal only on a '
                '@RestageWidget class and cannot change ScreenSource '
                'admission or output topology.',
            location: location,
          ),
        );
      }
    }
  }

  return ScreenSourceAdmission(
    resolvedLibrary: resolvedLibrary,
    visitorResult: visitorResult,
    annotatedClasses: annotatedClasses,
    issues: issues,
  );
}

String _fileStem(String path) {
  final slash = path.lastIndexOf('/');
  final filename = slash == -1 ? path : path.substring(slash + 1);
  return filename.endsWith('.dart')
      ? filename.substring(0, filename.length - '.dart'.length)
      : filename;
}

bool _hasPartDirective(CompilationUnit unit, String expectedPart) =>
    unit.directives
        .whereType<PartDirective>()
        .any((directive) => directive.uri.stringValue == expectedPart);
