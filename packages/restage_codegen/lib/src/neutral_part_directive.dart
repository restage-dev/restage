// The one place an authored `part` directive is checked against the resolved
// physical location of a library's generated Restage part.
//
// Every producer and validator resolves that location through the shared
// placement plan, so a package configuring a non-default layout gets a
// diagnostic naming the exact URI it must declare rather than a hardcoded one.

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/surface_publication/output_placement.dart';

/// Filename suffix of the one generated Dart part an authored library owns.
///
/// The name is neutral across declaration kinds: a library holding a screen,
/// a flow, or both contributes to this single part.
const String kNeutralGeneratedPartSuffix = '.restage.g.dart';

/// Every output-claim role that names a library's one generated Dart part.
///
/// A library's screen declarations, its flow declarations and the deprecated
/// `*Source` frontend all contribute to the same physical part, so each of
/// their claims names it under its own role. Artifact claims key on separate
/// role names and are unaffected.
const Set<String> kGeneratedPartRoles = <String>{
  'screen-descriptor',
  'flow-descriptor',
  'descriptor',
};

/// Superseded per-kind generated part suffixes.
///
/// Retained only so a source still declaring one gets a diagnostic naming its
/// replacement instead of a bare "missing part" message.
const List<String> kSupersededGeneratedPartSuffixes = [
  '.rsscreen.g.dart',
  '.rsflow.g.dart',
];

/// A stable, human-readable signature of the placement decisions [plan]
/// encodes.
///
/// Build Runner has no cross-builder options channel, so every
/// placement-affected Restage builder key accepts the same options with the
/// same defaults. Two builders resolving different signatures for one package
/// is a configuration error, and this is what such a report names.
String restagePlacementSignature(RestageOutputPlacementPlan plan) => <String>[
      'source_output_layout=${plan.sourceOutputLayout.name}',
      'inspection_report=${plan.inspectionReport}',
      'bundled_runtime=${plan.bundledRuntime}',
      'dart_output_root=${plan.dartOutputRoot ?? '-'}',
      'output_root=${plan.outputRoot ?? '-'}',
    ].join(', ');

/// The exact `part` URI [libraryPath] must declare under [plan].
String neutralPartUri(RestageOutputPlacementPlan plan, String libraryPath) {
  final placement = plan.forLibrary(libraryPath);
  return placement.partUriFor(placement.neutralPartPath);
}

/// The package-relative physical path of [libraryPath]'s generated part.
String neutralPartPath(RestageOutputPlacementPlan plan, String libraryPath) =>
    plan.forLibrary(libraryPath).neutralPartPath;

/// Validates [unit]'s `part` directives against the plan-resolved location of
/// [libraryPath]'s generated part.
///
/// Returns an empty list when the required URI is declared. Otherwise returns
/// one issue naming the exact URI required, and, when the library still
/// declares a superseded generated part, the URI being replaced.
List<Issue> neutralPartDirectiveIssues({
  required CompilationUnit unit,
  required String libraryPath,
  required RestageOutputPlacementPlan plan,
}) {
  final required = neutralPartUri(plan, libraryPath);
  final declared = <String>[
    for (final directive in unit.directives.whereType<PartDirective>())
      if (directive.uri.stringValue case final uri?) uri,
  ];
  if (declared.contains(required)) return const [];

  final superseded = declared.firstWhere(
    (uri) => kSupersededGeneratedPartSuffixes.any(uri.endsWith),
    orElse: () => '',
  );
  return [
    Issue(
      code: IssueCode.missingPartDirective,
      message: superseded.isEmpty
          ? "Missing `part '$required';` directive."
          : "Replace `part '$superseded';` with `part '$required';` — one "
              'generated part now carries every Restage declaration in this '
              'library.',
      location: libraryPath,
    ),
  ];
}

/// [neutralPartDirectiveIssues] for a caller holding the authored source text
/// rather than a parsed unit.
///
/// Only the directives are read, so the source is parsed without resolution
/// and syntax errors are tolerated: a library whose body does not yet analyze
/// still gets told which `part` it is missing.
List<Issue> neutralPartDirectiveIssuesForSource({
  required String sourceText,
  required String libraryPath,
  required RestageOutputPlacementPlan plan,
}) =>
    neutralPartDirectiveIssues(
      unit: parseString(
        content: sourceText,
        path: libraryPath,
        throwIfDiagnostics: false,
      ).unit,
      libraryPath: libraryPath,
      plan: plan,
    );
