import 'dart:convert';

import 'package:meta/meta.dart';

/// Slim view of the backend's `PaywallSummary` — only the fields the
/// command-line surface displays. The wire payload may carry additional
/// fields; unknown fields are ignored.
@experimental
@immutable
class PaywallSummary {
  /// Construct a summary.
  const PaywallSummary({
    required this.slug,
    required this.name,
    required this.draftUpdatedAt,
    required this.publishedVersionByEnvironment,
  });

  /// Paywall slug, unique within an app.
  final String slug;

  /// Human-readable name (defaults to the slug if unset on the server).
  final String name;

  /// Wall-clock instant the draft was last saved.
  final DateTime draftUpdatedAt;

  /// One entry per environment under the resolved app. The value is the
  /// most-recent published version for the control variant, or null when
  /// the paywall has never been published to that environment.
  final Map<String, int?> publishedVersionByEnvironment;

  /// Decode from the backend's JSON-shaped wire payload. Tolerates an
  /// absent `publishedVersionByEnvironment` (treated as empty) and the
  /// trailing `__className__` discriminator the server emits.
  factory PaywallSummary.fromJson(Map<String, dynamic> json) {
    final raw =
        json['publishedVersionByEnvironment'] as Map<String, dynamic>? ?? {};
    return PaywallSummary(
      slug: json['slug']! as String,
      name: json['name']! as String,
      draftUpdatedAt: DateTime.parse(json['draftUpdatedAt']! as String),
      publishedVersionByEnvironment: <String, int?>{
        for (final entry in raw.entries) entry.key: entry.value as int?,
      },
    );
  }

  /// Encode for the `--json` output. The shape matches [fromJson].
  Map<String, dynamic> toJson() => <String, dynamic>{
    'slug': slug,
    'name': name,
    'draftUpdatedAt': draftUpdatedAt.toUtc().toIso8601String(),
    'publishedVersionByEnvironment': publishedVersionByEnvironment,
  };
}

/// Sealed hierarchy for typed errors returned by paywall endpoints. The
/// CLI catches [RestageApiException] from the transport layer, runs
/// [decodeTypedException] over the body, and surfaces these to the user
/// as legible messages.
@experimental
@immutable
sealed class PaywallException implements Exception {
  const PaywallException();
}

/// Concurrent publishes raced; the caller should retry.
@experimental
class PublishConflict extends PaywallException {
  /// Construct with the offending [paywallSlug] and [environmentSlug].
  const PublishConflict({
    required this.paywallSlug,
    required this.environmentSlug,
  });
  final String paywallSlug;
  final String environmentSlug;

  @override
  String toString() =>
      'PublishConflict(paywallSlug: $paywallSlug, environmentSlug: $environmentSlug)';
}

/// A paywall with the requested slug does not exist.
@experimental
class PaywallNotFound extends PaywallException {
  /// Construct with the missing [paywallSlug].
  const PaywallNotFound({required this.paywallSlug});
  final String paywallSlug;

  @override
  String toString() => 'PaywallNotFound(paywallSlug: $paywallSlug)';
}

/// An environment with the requested slug does not exist under the
/// resolved app.
@experimental
class EnvironmentNotFound extends PaywallException {
  /// Construct with the missing [environmentSlug].
  const EnvironmentNotFound({required this.environmentSlug});
  final String environmentSlug;

  @override
  String toString() => 'EnvironmentNotFound(environmentSlug: $environmentSlug)';
}

/// Attempt to decode [body] as one of the typed paywall exceptions.
///
/// Returns null when [body] is not a Serverpod typed-exception payload
/// (caller should fall through to the generic
/// [RestageApiException]-handling path).
///
/// Serverpod 3 returns a `SerializableException` as:
///
/// ```json
/// {"className": "<Name>", "data": {"__className__": "<Name>", ...fields}}
/// ```
@experimental
PaywallException? decodeTypedException(String body) {
  if (body.isEmpty) return null;
  final dynamic doc;
  try {
    doc = jsonDecode(body);
  } on FormatException {
    return null;
  }
  if (doc is! Map<String, dynamic>) return null;
  final className = doc['className'];
  final data = doc['data'];
  if (className is! String || data is! Map<String, dynamic>) return null;
  switch (className) {
    case 'PublishConflictException':
      return PublishConflict(
        paywallSlug: data['paywallSlug'] as String,
        environmentSlug: data['environmentSlug'] as String,
      );
    case 'PaywallNotFoundException':
      return PaywallNotFound(paywallSlug: data['paywallSlug'] as String);
    case 'EnvironmentNotFoundException':
      return EnvironmentNotFound(
        environmentSlug: data['environmentSlug'] as String,
      );
    default:
      return null;
  }
}
