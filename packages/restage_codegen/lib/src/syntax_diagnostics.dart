import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/error/error.dart';
import 'package:restage_codegen/src/issue.dart';

/// Collects build-failing [Issue]s for genuine *syntactic* errors (scanner /
/// parser errors) in the units of [resolved].
///
/// Builders resolve Dart sources with `allowSyntaxErrors: true` so a malformed
/// input does not crash the build with an opaque resolver exception. That
/// tolerance can let a malformed token whose parser error-recovery yields a
/// structurally-valid widget tree ship a clean blob with the bad token
/// silently dropped — e.g. an incomplete hex literal `0x` recovering to `0`,
/// or an unterminated string recovering to a closed one. This surfaces those
/// syntactic errors as actionable diagnostics so the author fixes the source
/// rather than shipping a degraded blob.
///
/// Only [DiagnosticType.SYNTACTIC_ERROR] diagnostics are reported. Resolution /
/// compile-time errors (an unresolved import, a not-yet-generated part) are the
/// expected class `allowSyntaxErrors: true` exists to tolerate, so they are
/// deliberately excluded — flagging them would re-break the legitimate build
/// steps the tolerance protects.
///
/// [sourcePath] is the package-relative path of the input asset, used to build
/// readable issue locations.
List<Issue> syntacticErrorIssues(
  ResolvedLibraryResult resolved, {
  required String sourcePath,
}) {
  final issues = <Issue>[];
  for (final unit in resolved.units) {
    for (final diagnostic in unit.diagnostics) {
      if (diagnostic.diagnosticCode.type != DiagnosticType.SYNTACTIC_ERROR) {
        continue;
      }
      final location = unit.lineInfo.getLocation(diagnostic.offset);
      // `Diagnostic.message` is the human-readable text; `problemMessage` is
      // a `DiagnosticMessage` object, so interpolating it directly would emit
      // an opaque object rendering instead of the analyzer's actual message.
      issues.add(
        Issue(
          code: IssueCode.malformedSourceInput,
          message: 'Syntax error: ${diagnostic.message} Fix the '
              'malformed source — codegen otherwise recovers from the bad '
              'token and may silently drop the affected value from the '
              'emitted blob.',
          location: '$sourcePath@'
              '${location.lineNumber}:${location.columnNumber}',
        ),
      );
    }
  }
  return issues;
}
