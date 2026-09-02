import 'package:restage_codegen/src/issue.dart';

/// A complete, absent, or refused DSL emission.
/// Complete output always contains nonempty bytes.
sealed class DslEmission {
  const DslEmission();

  /// Creates complete, nonempty output.
  factory DslEmission.complete(String value) = CompleteDslEmission;

  /// Creates a deliberately absent optional fragment.
  const factory DslEmission.absent() = AbsentDslEmission;

  /// Creates a refusal with no output.
  const factory DslEmission.refusal() = RefusedDslEmission;
}

/// A complete emission containing DSL bytes.
final class CompleteDslEmission extends DslEmission {
  /// Creates a complete emission.
  CompleteDslEmission(String value) : value = _requireCompleteBytes(value);

  /// The complete DSL bytes.
  final String value;
}

/// A deliberately absent optional fragment.
final class AbsentDslEmission extends DslEmission {
  /// Creates an absent fragment.
  const AbsentDslEmission();
}

/// A refused emission with no DSL bytes.
final class RefusedDslEmission extends DslEmission {
  /// Creates a refused emission.
  const RefusedDslEmission();
}

String _requireCompleteBytes(String value) {
  if (value.isEmpty) {
    throw ArgumentError.value(value, 'value', 'must contain DSL bytes');
  }
  return value;
}

/// Classifies authored [value] as complete or deliberately absent.
DslEmission deliberateFragment(String value) =>
    value.isEmpty ? const DslEmission.absent() : DslEmission.complete(value);

/// Translates one required child and classifies its outcome.
DslEmission normalizePresentChild(
  List<Issue> issues,
  String Function() translate,
) {
  final issueStart = issues.length;
  final value = translate();
  return normalizePresentValue(issues, issueStart, value);
}

/// Classifies required [value] against issues added from [issueStart].
DslEmission normalizePresentValue(
  List<Issue> issues,
  int issueStart,
  String value,
) {
  final refused = value.isEmpty ||
      issues.skip(issueStart).any((issue) => !issue.code.isBuildNotice);
  return refused ? const DslEmission.refusal() : DslEmission.complete(value);
}

/// Translates one optional child and classifies its outcome.
DslEmission normalizeOptionalChild(
  List<Issue> issues,
  String Function() translate,
) {
  final issueStart = issues.length;
  final value = translate();
  if (issues.skip(issueStart).any((issue) => !issue.code.isBuildNotice)) {
    return const DslEmission.refusal();
  }
  return deliberateFragment(value);
}

/// Returns complete bytes and maps absence or refusal to no output.
String unwrapDslEmission(DslEmission emission) => switch (emission) {
      CompleteDslEmission(:final value) => value,
      AbsentDslEmission() || RefusedDslEmission() => '',
    };
