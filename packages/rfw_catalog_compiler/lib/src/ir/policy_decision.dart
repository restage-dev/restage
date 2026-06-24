import 'package:meta/meta.dart';

/// One compiler policy decision retained for audit trails.
@immutable
final class PolicyDecisionIR {
  /// Creates a policy decision.
  const PolicyDecisionIR({
    required this.policy,
    required this.decision,
    required this.reason,
    this.target,
  });

  /// Policy that made the decision.
  final String policy;

  /// Decision outcome, such as `included`, `excluded`, or `overridden`.
  final String decision;

  /// Human-readable reason for the decision.
  final String reason;

  /// Optional source or catalog target affected by the decision.
  final String? target;
}
