import 'package:analyzer/error/error.dart' show DiagnosticCode;
import 'package:meta/meta.dart';

/// Analyzer diagnostic code type for compiler diagnostics.
typedef IssueCode = DiagnosticCode;

/// One internal compiler diagnostic attached to IR.
@immutable
final class DiagnosticIR {
  /// Creates a compiler diagnostic.
  const DiagnosticIR({
    required this.code,
    required this.message,
    required this.location,
    required this.severity,
    this.target,
  });

  /// Stable diagnostic code.
  final IssueCode code;

  /// Human-readable diagnostic message.
  final String message;

  /// Source or catalog location.
  final String location;

  /// Diagnostic severity.
  final DiagnosticSeverity severity;

  /// Optional target within the location.
  final String? target;
}

/// Severity values for internal compiler diagnostics.
enum DiagnosticSeverity {
  /// Informational diagnostic.
  info,

  /// Warning diagnostic.
  warning,

  /// Error diagnostic.
  error,
}
