import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/api.dart';

import 'auth.dart';

/// Run [body] against an authenticated backend client, mapping every failure
/// to a clean [CallToolResult] and closing any client this helper created.
///
/// This is the single auth/error/close seam every tool shares. It resolves the
/// authenticated client from the shared cached credential, runs the tool body,
/// and translates errors:
///
/// - a missing or unusable credential and an insecure stored endpoint surface
///   their own user-facing messages;
/// - a backend error is decoded to a legible, domain-specific sentence when the
///   response carries a typed payload, else a generic "status N";
/// - a transport failure surfaces the socket message;
/// - anything unexpected is mapped to a fixed generic message. The original
///   throwable and its stack trace are NEVER forwarded to the client — an
///   unexpected throwable can embed sensitive content (a corrupt credential's
///   decode error includes the file's bytes), so only its runtime type is
///   written to stderr as a breadcrumb, and stderr is not the protocol channel.
///
/// [action] is a gerund phrase naming the operation (e.g. `listing paywalls`)
/// used in the generic messages.
Future<CallToolResult> withApi({
  required FileCredentialStore store,
  http.Client? httpClient,
  required String action,
  required Future<CallToolResult> Function(RestageApi api) body,
}) {
  return guardErrors(action, () async {
    RestageApi? api;
    try {
      api = await resolveAuthenticatedApi(store: store, httpClient: httpClient);
      return await body(api);
    } finally {
      // Only close clients we created; an injected client is the caller's.
      if (httpClient == null) api?.close();
    }
  });
}

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

/// Run [body] and translate every failure to a clean [CallToolResult].
///
/// This is the defensive error boundary shared by every tool — including the
/// auth tools, which manage their own credential lifecycle and so cannot use
/// [withApi]'s auth resolution. The typed `on` clauses map known failures to
/// user-facing messages; the trailing catch maps anything unexpected to a fixed
/// generic message and NEVER forwards the throwable or its stack trace (an
/// unexpected throwable can embed sensitive content — a corrupt credential's
/// decode error includes the file's bytes). Only the runtime type is written to
/// stderr, which is not the protocol channel.
Future<CallToolResult> guardErrors(
  String action,
  Future<CallToolResult> Function() body,
) async {
  try {
    try {
      return await body();
    } on NotSignedInException catch (e) {
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
      return mcpError(legibleApiError(e, action));
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

/// Translate a backend [RestageApiException] to a legible, secret-free message.
///
/// When the response body is a typed exception payload, the decoded variant
/// carries only domain identifiers (slugs, a resource name) — never secret
/// material — so surfacing them is safe and far more useful to an agent than a
/// bare status code. Falls back to the status code for anything else.
String legibleApiError(RestageApiException e, String action) {
  // Decode defensively. A recognized className with a wrong-typed `data` field
  // makes a decoder's unchecked cast throw. That throw would occur inside
  // guardErrors' `on RestageApiException` clause and ESCAPE the enclosing try —
  // a throw in a catch clause is not caught by its siblings — reaching the
  // framework's catch-all, which forwards the stack trace to the client. Treat
  // any decode failure as "untyped": fall through to the status-code message.
  //
  // Two sealed families cover the typed backend errors: the endpoint-agnostic
  // generic exceptions (auth / project / app) and the paywall-specific ones.
  // Consult both decoders so every typed error maps to its legible sentence.
  GenericTypedException? generic;
  PaywallException? paywall;
  try {
    generic = decodeGenericTypedException(e.body);
    paywall = decodeTypedException(e.body);
  } catch (_) {
    generic = null;
    paywall = null;
  }
  switch (generic) {
    case UnauthorizedAccess(:final resource):
      final scope = resource.isEmpty ? '' : " for '$resource'";
      return 'Not permitted — the signed-in account lacks the required '
          'role$scope.';
    case ProjectNotFound(:final projectSlug):
      return "No project '$projectSlug' was found.";
    case AppNotFound(:final appSlug, :final projectSlug):
      return "No app '$appSlug' was found in project '$projectSlug'.";
    case null:
      break;
  }
  switch (paywall) {
    case PaywallNotFound(:final paywallSlug):
      return "No paywall '$paywallSlug' was found.";
    case EnvironmentNotFound(:final environmentSlug):
      return "No environment '$environmentSlug' was found.";
    case PublishConflict(:final paywallSlug, :final environmentSlug):
      return "A concurrent publish conflicted for paywall '$paywallSlug' in "
          "environment '$environmentSlug'. Please try again.";
    case null:
      break;
  }
  // Paywalls publish/list through the generic surface endpoint, so its typed
  // exceptions surface here. Decode them defensively (same unchecked-cast
  // hazard as above) and present the same paywall-facing phrasing — otherwise
  // a missing paywall / publish conflict would degrade to a bare status code.
  SurfaceException? surfaceTyped;
  try {
    surfaceTyped = decodeSurfaceTypedException(e.body);
  } catch (_) {
    surfaceTyped = null;
  }
  switch (surfaceTyped) {
    case SurfaceNotFound(:final surfaceSlug):
      return "No paywall '$surfaceSlug' was found.";
    case SurfacePublishConflict(:final surfaceSlug, :final environmentSlug):
      return "A concurrent publish conflicted for paywall '$surfaceSlug' in "
          "environment '$environmentSlug'. Please try again.";
    case SurfaceEnvironmentNotFound(:final environmentSlug):
      return "No environment '$environmentSlug' was found.";
    case SurfaceRollbackUnsupported(:final surfaceSlug):
      return "Rollback isn't supported for paywall '$surfaceSlug'.";
    case SurfaceVersionNotFound(:final surfaceSlug, :final toVersion):
      return "No version $toVersion was found for paywall '$surfaceSlug'.";
    case null:
      return 'The Restage backend returned an error (status ${e.statusCode}).';
  }
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
}
