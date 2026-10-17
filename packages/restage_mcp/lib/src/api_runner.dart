import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:restage_cli/api.dart';

import 'auth.dart';

/// Replace every occurrence of each non-empty string in [secrets] with
/// `[redacted]` across [result]'s text content and (recursively) its structured
/// content string values, preserving structure, `isError`, and `meta`.
///
/// The server applies this to EVERY tool result over the secrets it holds (the
/// session token + the in-flight device grant) — the by-construction value
/// funnel that covers every auth path uniformly.
CallToolResult scrubValues(CallToolResult result, Set<String> secrets) {
  final needles = secrets.where((s) => s.isNotEmpty).toList();
  if (needles.isEmpty) return result;
  String scrub(String s) {
    var out = s;
    for (final needle in needles) {
      out = out.replaceAll(needle, '[redacted]');
    }
    return out;
  }

  Object? walk(Object? value) {
    if (value is String) return scrub(value);
    if (value is Map) {
      final out = <String, Object?>{};
      // Scrub map KEYS as well as values — a backend could key a map by the
      // secret. On the (degenerate) chance two keys scrub to the same string,
      // last-wins is fine: nothing leaks, and only a hostile/buggy collision
      // loses a value.
      value.forEach((key, dynamic v) => out[scrub('$key')] = walk(v));
      return out;
    }
    if (value is List) return [for (final element in value) walk(element)];
    return value;
  }

  final structured = result.structuredContent;
  return CallToolResult(
    meta: result.meta,
    content: [
      for (final c in result.content)
        if (c is TextContent) TextContent(text: scrub(c.text)) else c,
    ],
    structuredContent: structured == null
        ? null
        : walk(structured)! as Map<String, Object?>,
    isError: result.isError,
  );
}

/// Maps known failures from [body] to tool error responses.
/// Unexpected errors return a fixed message and log only their runtime type
/// to stderr; exception content and stack traces may contain secrets.
Future<CallToolResult> guardErrors(
  String action,
  Future<CallToolResult> Function() body,
) async {
  try {
    try {
      return await body();
    } on NotSignedInException catch (e) {
      return mcpError(e.toString());
    } on TargetSelectionException catch (e) {
      return mcpError(e.message);
    } on DeliveryMeasurementReviewRequired catch (e) {
      final result = jsonResult({
        'measurementReview': e.review.toJson(),
        'reviewDigest': e.review.digest.hex,
        'acknowledgementRequired': true,
        'consequence': ?deliveryMeasurementMutationConsequence(e.review),
      });
      return CallToolResult(
        isError: true,
        content: result.content,
        structuredContent: result.structuredContent,
      );
    } on DeliveryPolicyReviewRequired catch (e) {
      final result = jsonResult({
        'policyReview': e.review.toJson(),
        'reviewDigest': e.review.digest.hex,
        'acknowledgementRequired': true,
      });
      return CallToolResult(
        isError: true,
        content: result.content,
        structuredContent: result.structuredContent,
      );
    } on DeliveryManagementResponseException catch (e) {
      return mcpError(e.toString());
    } on InsecureEndpointException {
      // Never echo the endpoint. A corrupt/crafted credentials file can embed a
      // secret in the endpoint's userinfo (`<keyId>:<key>@host`), and
      // InsecureEndpointException.toString() includes the full URL — forwarding
      // it would leak that secret to the client. Return a fixed message.
      return mcpError(
        'Refusing to use the stored endpoint: it is not a secure '
        '(https or loopback http) URL. Sign in again with restage_login.',
      );
    } on RestageApiException catch (e) {
      if (decodeFitNeedsConfirmation(e.body) case final needs?) {
        return _fitResult(needs);
      }
      return mcpError(renderApiError(e, syntax: SelectorSyntax.mcp).message);
    } on SocketException catch (e) {
      // Don't forward e.message — for a DNS failure Dart embeds the host in the
      // message, and a crafted credentials file could carry secret material in
      // an accepted https host. Fixed message + a runtimeType-only breadcrumb.
      stderr.writeln('restage_mcp $action failed: ${e.runtimeType}');
      return mcpError(
        'Could not reach the Restage backend. Check your connection and try '
        'again.',
      );
    } catch (e) {
      stderr.writeln('restage_mcp $action failed: ${e.runtimeType}');
      return mcpError('An unexpected error occurred while $action.');
    }
  } catch (e) {
    // Structural backstop. A throw from inside any inner `on`/`catch` clause
    // body above (e.g. an error-mapping helper that itself throws) is NOT routed
    // to a sibling catch by Dart — it would escape to the framework's catch-all
    // and put a stack trace on the client channel. This outer catch makes the
    // "never forward a throwable/stack to the client" invariant hold BY
    // CONSTRUCTION, regardless of what any inner clause body does.
    stderr.writeln('restage_mcp $action failed: ${e.runtimeType}');
    return mcpError('An unexpected error occurred while $action.');
  }
}

/// The server's report that not every app version can show what was being
/// made live: the verdict as data, naming `acceptFit` as the way to go on.
CallToolResult _fitResult(SurfaceFitNeedsConfirmation needs) {
  final result = jsonResult({
    'needsConfirmation': {
      'verdict': needs.noneFit ? 'noneFit' : 'someFit',
      'environment': needs.environment,
      'share': needs.share,
      'builds': [
        for (final build in needs.builds)
          {
            'platform': build.platform,
            'appVersion': build.appVersion,
            'appBuildOrdinal': build.appBuildOrdinal,
            'uploaded': build.uploaded,
            'fits': build.fits,
          },
      ],
      'summary': fitConfirmationSentence(needs),
      'nextStep': 'Call again with acceptFit: true to go ahead.',
    },
  });
  return CallToolResult(
    isError: true,
    content: result.content,
    structuredContent: result.structuredContent,
  );
}

/// Backend field names that must never reach the client, matched EXACTLY (not
/// by substring, so benign neighbours like `keyPrefix` and
/// `credentialFingerprint` are preserved). The shipped backend models carry
/// none of these; this is a by-construction backstop against a buggy / hostile /
/// future backend putting a secret-named field in a verbatim-passthrough
/// response. (A secret surfaced under a *benign* key name is a different risk,
/// handled at the source — e.g. the login flow's own validation.)
const _secretFieldNames = <String>{
  'plaintext',
  'authToken',
  'keyHash',
  'credentialBundle',
  'encryptedCredential',
  'wrappedDataKey',
  'credentialKeyRef',
  'deviceCode',
};

/// Recursively drop [_secretFieldNames] entries from [value] (walking maps and
/// lists), returning a cleaned copy. Non-collection values pass through.
Object? _redactSecrets(Object? value) {
  if (value is Map) {
    final out = <String, Object?>{};
    value.forEach((key, dynamic v) {
      if (key is String && _secretFieldNames.contains(key)) return;
      out['$key'] = _redactSecrets(v);
    });
    return out;
  }
  if (value is List) {
    return [for (final element in value) _redactSecrets(element)];
  }
  return value;
}

/// Build a success result from [payload]: pretty JSON text plus the same
/// payload as structured content. Secret-named fields are redacted from BOTH —
/// the single success-output funnel, the output-side analog of [guardErrors]'
/// structural error backstop.
CallToolResult jsonResult(Map<String, Object?> payload) {
  final clean = _redactSecrets(payload)! as Map<String, Object?>;
  return CallToolResult(
    content: [
      TextContent(text: const JsonEncoder.withIndent('  ').convert(clean)),
    ],
    structuredContent: clean,
  );
}

/// Build an error result carrying [message] (and nothing else).
CallToolResult mcpError(String message) =>
    CallToolResult(isError: true, content: [TextContent(text: message)]);

/// Return a copy of [args] with the null-valued entries removed.
///
/// The backend's RPC reads a missing nullable parameter as `null`, so dropping
/// an absent optional argument is equivalent to sending it as `null` — and
/// keeps the wire body free of explicit `"key": null` noise. Used by every tool
/// that threads optional arguments (the optional `organizationId`, an optional
/// `store` filter, a write tool's omitted fields).
Map<String, dynamic> compactArgs(Map<String, dynamic> args) => {
  for (final entry in args.entries)
    if (entry.value != null) entry.key: entry.value,
};

/// Typed accessors over a tool call's arguments. The framework validates the
/// input schema before the handler runs, so a required key of the declared type
/// is present here; [str] / [reqInt] read it directly and [optInt] tolerates
/// an absent optional key.
extension ToolArgs on CallToolRequest {
  Map<String, Object?> get _args => arguments ?? const <String, Object?>{};

  /// A required string argument.
  String str(String key) => _args[key]! as String;

  /// A required integer argument.
  int reqInt(String key) => (_args[key]! as num).toInt();

  /// An optional integer argument (null when absent).
  int? optInt(String key) => (_args[key] as num?)?.toInt();

  /// An optional string argument (null when absent or explicitly null).
  String? optStr(String key) => _args[key] as String?;

  /// An optional boolean argument (null when absent).
  bool? optBool(String key) => _args[key] as bool?;
}
