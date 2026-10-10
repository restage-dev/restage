import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dart_mcp/server.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:restage_cli/api.dart';
import 'package:restage_cli/restage_cli.dart' show NonInteractive, RestageCli;
import 'package:stream_channel/stream_channel.dart';

import 'api_runner.dart';
import 'build_tools.dart';
import 'experimental_gate.dart';
import 'in_flight_gate.dart';
import 'operation_tools.dart';
import 'project_tools.dart';
import 'surface_funnel_tool.dart';
import 'surface_routing_tool.dart';
import 'surface_tools.dart';
import 'tool_support.dart';

/// Backend origin used for in-server login when no credential exists yet.
/// Overridable at build time via `--define`; falls back to localhost.
const _defaultLoginEndpoint = String.fromEnvironment(
  'RESTAGE_DEFAULT_ENDPOINT',
  defaultValue: 'http://localhost:8080/',
);

/// How long a single `restage_login` poll call blocks before returning a
/// "still waiting" prompt — kept well under typical MCP-host request timeouts.
const _loginPollBudget = Duration(seconds: 30);

/// The server version reported to MCP hosts. Keep in sync with `pubspec.yaml`.
const restageMcpVersion = '0.1.0';

/// The Restage MCP server.
///
/// Exposes the Restage backend to an MCP host over the tools capability,
/// reusing the CLI's HTTP/auth/credential layer. Authentication comes from the
/// shared cached credential written by `restage login`.
base class RestageMcpServer extends MCPServer with ToolsSupport {
  /// Builds the server over [channel], usually stdio.
  ///
  /// Defaults to stored credentials and one HTTP client for its lifetime.
  /// Login dependencies are injectable; [cliRunner] replaces the in-process CLI.
  /// Input closure waits for pending tool responses.
  ///
  /// This embedding API is experimental and follows the MCP framework's types.
  /// Use the `restage_mcp` executable for the standard integration.
  @experimental
  factory RestageMcpServer.fromStreamChannel(
    StreamChannel<String> channel, {
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
    Future<void> Function(Duration)? sleep,
    Future<void> Function(String)? openBrowser,
    Uri? loginEndpoint,
    DateTime Function()? now,
    ExperimentActivationApi? experimentActivationApi,
    Map<String, String>? environment,
    CliRunner? cliRunner,
  }) {
    final gate = InFlightGate();
    return RestageMcpServer._(
      gate,
      channel.changeStream(gate.holdCloseUntilDrained),
      credentialStore: credentialStore,
      httpClient: httpClient,
      sleep: sleep,
      openBrowser: openBrowser,
      loginEndpoint: loginEndpoint,
      now: now,
      experimentActivationApi: experimentActivationApi,
      environment: environment,
      cliRunner: cliRunner,
    );
  }

  RestageMcpServer._(
    this._gate,
    super.channel, {
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
    Future<void> Function(Duration)? sleep,
    Future<void> Function(String)? openBrowser,
    Uri? loginEndpoint,
    DateTime Function()? now,
    ExperimentActivationApi? experimentActivationApi,
    Map<String, String>? environment,
    CliRunner? cliRunner,
  }) : _credentialStore = credentialStore,
       _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null,
       _environment = environment,
       _sleep = sleep ?? _defaultSleep,
       _openBrowser = openBrowser ?? _defaultOpenBrowser,
       _loginEndpoint = loginEndpoint,
       _now = now ?? DateTime.now,
       super.fromStreamChannel(
         implementation: Implementation(
           name: 'restage',
           version: restageMcpVersion,
         ),
         instructions:
             'Manage Restage surfaces (paywalls, onboarding, messages, '
             'surveys) and configuration. Sign in with restage_login (or '
             'reuse an existing `restage login` session).',
       ) {
    // _scrubbed removes the secrets this server holds (the session token and
    // the in-flight device grant) from every result.
    final injectedCli = cliRunner;
    final tools = ToolContext(
      store: _store,
      httpClient: _httpClient,
      runCli: injectedCli == null
          ? _runCli
          : (args, {required stdout, required stderr, target}) =>
                injectedCli(args, stdout: stdout, stderr: stderr),
    );
    for (final (tool, handler) in <ToolEntry>[
      (_loginTool, _handleLogin),
      (_whoamiTool, _handleWhoami),
      (_logoutTool, _handleLogout),
      ...operationTools(tools),
      ...surfaceTools(tools),
      ...routingTools(tools),
      ...buildTools(tools),
      ...projectTools(tools),
      (
        readSurfaceFunnelTool,
        (request) => handleReadSurfaceFunnel(tools, request),
      ),
      // Experimental tools call routes production does not serve yet, and an
      // MCP client's only signal about what it may call is the tool list.
      if (experimentalToolsEnabled(environment))
        ...experimentTools(tools, activation: experimentActivationApi),
    ]) {
      final (adapted, filled) = withProjectConfig(tools, (tool, handler));
      registerTool(adapted, _scrubbed(filled));
    }
  }

  @override
  Future<void> shutdown() async {
    await super.shutdown();
    if (_ownsHttpClient) _httpClient.close();
  }

  /// Wrap [handler] so its result passes through the held-secret value funnel
  /// ([_scrubHeldSecrets]) before reaching the client.
  Future<CallToolResult> Function(CallToolRequest) _scrubbed(
    Future<CallToolResult> Function(CallToolRequest) handler,
  ) {
    return (request) =>
        _gate.track(() async => _scrubHeldSecrets(await handler(request)));
  }

  /// Remove the secrets this server holds — the stored session token (the full
  /// `keyId:key` and the bare key part) and any in-flight device grant — from
  /// [result]. Both are high-entropy values that can never legitimately appear
  /// in a tool result, so this cannot corrupt honest output. The single,
  /// uniform value funnel for every auth path.
  Future<CallToolResult> _scrubHeldSecrets(CallToolResult result) async {
    final secrets = <String>{};
    try {
      final credential = await _store.read();
      final authToken = credential?.authToken ?? '';
      if (authToken.isNotEmpty) {
        secrets.add(authToken);
        final colon = authToken.indexOf(':');
        if (colon >= 0 && colon + 1 < authToken.length) {
          secrets.add(authToken.substring(colon + 1));
        }
      }
      // A corrupt credentials file makes read() throw (its message can embed
      // the file's bytes). The funnel runs OUTSIDE the handler's guardErrors, so
      // it must swallow that — the handler already failed closed on the same
      // corrupt file (a clean error with no secret), leaving nothing to scrub.
    } on Object {
      // Intentionally ignored — see above.
    }
    final deviceCode = _pendingLogin?.deviceCode ?? '';
    if (deviceCode.isNotEmpty) secrets.add(deviceCode);
    return secrets.isEmpty ? result : scrubValues(result, secrets);
  }

  final InFlightGate _gate;
  final FileCredentialStore? _credentialStore;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final Map<String, String>? _environment;
  final Future<void> Function(Duration) _sleep;
  final Future<void> Function(String) _openBrowser;
  final Uri? _loginEndpoint;
  final DateTime Function() _now;

  /// The in-flight device-authorization attempt, if any. Holds the device-code
  /// secret in process memory only — it is never returned to the client.
  _PendingLogin? _pendingLogin;

  static final _loginTool = Tool(
    name: 'restage_login',
    description:
        'Sign in to Restage with the device-authorization flow. Call it once '
        'to start: it returns a verification URL and a short code and opens '
        'your browser. Approve there, THEN call restage_login AGAIN to '
        'complete sign-in. If a session is already active, it says so instead.',
    inputSchema: Schema.object(properties: {}),
  );

  static final _whoamiTool = Tool(
    name: 'restage_whoami',
    description:
        'Report whether a Restage session is active and, if so, the '
        'signed-in account.',
    inputSchema: Schema.object(properties: {}),
  );

  static final _logoutTool = Tool(
    name: 'restage_logout',
    description:
        'Sign out: revoke the stored Restage session and remove the local '
        'credential.',
    inputSchema: Schema.object(properties: {}),
  );

  /// The shared credential store — the injected one in tests, else the
  /// default shared on-disk location.
  FileCredentialStore get _store =>
      _credentialStore ?? FileCredentialStore.atDefaultLocation();

  /// Run [body] against [endpoint] (optionally authed with [credential]) on
  /// the server's client.
  Future<T> _withRawApi<T>(
    Uri endpoint, {
    Credential? credential,
    required Future<T> Function(RestageApi api) body,
  }) async {
    final api = RestageApi(
      endpoint: endpoint,
      credential: credential,
      httpClient: _httpClient,
    );
    return body(api);
  }

  /// The in-process CLI, never prompting: stdin is the protocol channel.
  Future<int> _runCli(
    List<String> args, {
    required StringSink stdout,
    required StringSink stderr,
  }) => RestageCli(
    stdout: stdout,
    stderr: stderr,
    credentialStore: _credentialStore,
    httpClient: _httpClient,
    hasTerminal: () => false,
    interactiveFactory: (_) => const NonInteractive(),
    environment: _environment,
    selectorSyntax: SelectorSyntax.mcp,
  ).run(args);

  // ---- Auth: device-code login + whoami + logout ----

  /// Handle `restage_login` — the stateful, idempotent device-code flow.
  ///
  /// One slot, last-start-wins: a valid in-flight attempt is polled; otherwise
  /// (no attempt, an expired attempt, or already signed in) it short-circuits
  /// or starts fresh. The device-code secret never leaves this process.
  Future<CallToolResult> _handleLogin(CallToolRequest request) {
    return guardErrors('signing in', () async {
      final pending = _pendingLogin;
      if (pending != null && _now().isBefore(pending.expiresAt)) {
        return _pollPendingLogin(pending);
      }
      _pendingLogin = null; // no attempt, or an expired one — start fresh.

      final existing = await _store.read();
      if (existing != null) {
        final email = await _signedInEmail(existing);
        if (email != null) {
          return jsonResult(<String, Object?>{
            'status': 'already_signed_in',
            'email': email,
            'message':
                'Already signed in as $email. Run restage_logout first to '
                'switch accounts.',
          });
        }
      }
      return _startLogin();
    });
  }

  /// Start a new device authorization, stash it, open the browser best-effort,
  /// and return the verification URL + user code (never the device code).
  Future<CallToolResult> _startLogin() {
    final endpoint = _resolveLoginEndpoint();
    return _withRawApi(
      endpoint,
      body: (api) async {
        final start = await AuthApi(api).startDeviceAuthorization();
        // Fail closed on a malformed authorization response BEFORE storing it,
        // opening the browser, or surfacing it. (1) The verification URL is
        // handed to the OS browser opener — reject anything but https / loopback
        // http so a buggy/hostile backend can't drive `open`/`xdg-open` to a
        // file:// or custom-scheme target. (2) Refuse if the (public) userCode
        // or verificationUri alias the (secret) deviceCode — a backend leaking
        // its own grant into a field we surface.
        final verificationUri = Uri.tryParse(start.verificationUri);
        if (verificationUri == null ||
            !isAcceptableTransport(verificationUri)) {
          return mcpError(
            'Sign-in could not start: the server returned an unsupported '
            'verification URL. Please try again.',
          );
        }
        if (start.deviceCode.isNotEmpty &&
            (start.userCode.contains(start.deviceCode) ||
                start.verificationUri.contains(start.deviceCode))) {
          return mcpError(
            'Sign-in could not start: the server returned a malformed '
            'authorization response. Please try again.',
          );
        }
        final pending = _PendingLogin(
          deviceCode: start.deviceCode,
          userCode: start.userCode,
          verificationUri: start.verificationUri,
          expiresAt: _now().add(Duration(seconds: start.expiresInSeconds)),
          pollIntervalSeconds: start.pollIntervalSeconds,
          endpoint: endpoint,
        );
        _pendingLogin = pending;
        await _openBrowserBestEffort(start.verificationUri);
        return _authorizationPendingResult(
          pending,
          leadMessage: 'Action required:',
        );
      },
    );
  }

  /// Poll an in-flight attempt up to the per-call budget, honoring the server's
  /// back-off. Persists the credential on success.
  Future<CallToolResult> _pollPendingLogin(_PendingLogin pending) {
    return _withRawApi(
      pending.endpoint,
      body: (api) async {
        final auth = AuthApi(api);
        final deadline = _now().add(_loginPollBudget);
        // Floor the interval at 1s so a hostile/buggy backend returning 0 (or a
        // negative) cannot turn the bounded poll into a tight loop that never
        // crosses the deadline (and hammers the backend).
        var interval = Duration(seconds: max(1, pending.pollIntervalSeconds));
        while (true) {
          // The whole grant has expired — give up and clear the attempt.
          if (!_now().isBefore(pending.expiresAt)) {
            _pendingLogin = null;
            return _expiredResult();
          }
          final result = await auth.exchangeDeviceCode(pending.deviceCode);
          switch (result.status) {
            case DeviceAuthorizationStatus.success:
              await _persistCredential(pending.endpoint, result);
              final deviceCode = pending.deviceCode;
              _pendingLogin = null;
              var email = result.userInfo?.email;
              // Defense-in-depth: never surface an email that aliases a secret
              // — the deviceCode the backend generated or the minted key — even
              // if a backend places it in the email field. Sign-in still
              // completes; only the aliased value is withheld.
              if (email != null &&
                  _emailAliasesSecret(email, deviceCode, result)) {
                email = null;
              }
              return jsonResult(<String, Object?>{
                'status': 'signed_in',
                'email': email,
                'message': email == null
                    ? 'Signed in.'
                    : 'Signed in as $email.',
              });
            case DeviceAuthorizationStatus.expired:
              _pendingLogin = null;
              return _expiredResult();
            case DeviceAuthorizationStatus.notFound:
              _pendingLogin = null;
              return jsonResult(<String, Object?>{
                'status': 'failed',
                'message':
                    'The sign-in attempt could not be completed. Call '
                    'restage_login again to start over.',
              });
            case DeviceAuthorizationStatus.pending:
              // Honour the server's back-off (RFC 8628 slow_down), floored at
              // 1s for the same forward-progress guarantee.
              if (result.pollIntervalSeconds != null) {
                interval = Duration(
                  seconds: max(1, result.pollIntervalSeconds!),
                );
              }
              // If the next poll would exceed our per-call budget, return and
              // KEEP the attempt so a re-call resumes the same grant.
              if (!_now().add(interval).isBefore(deadline)) {
                return _authorizationPendingResult(
                  pending,
                  leadMessage: 'Still waiting for approval.',
                );
              }
              await _sleep(interval);
          }
        }
      },
    );
  }

  /// Quietly resolve the signed-in email, or null when the stored credential is
  /// missing/stale/unreachable (so login proceeds to a fresh sign-in).
  Future<String?> _signedInEmail(Credential credential) async {
    try {
      return await _withRawApi(
        Uri.parse(credential.endpoint),
        credential: credential,
        body: (api) async => (await AuthApi(api).whoami())?.email,
      );
    } on Object {
      return null;
    }
  }

  Future<void> _persistCredential(
    Uri endpoint,
    DeviceAuthorizationResult result,
  ) async {
    final keyId = result.keyId;
    final key = result.key;
    if (keyId == null || key == null) {
      throw StateError('Backend reported success without a credential.');
    }
    await _store.write(
      Credential(
        endpoint: endpoint.toString(),
        kind: CredentialKind.authKey,
        authToken: '$keyId:$key',
      ),
    );
  }

  /// Whether [email] contains a secret a backend should never place there: the
  /// [deviceCode] it generated, the minted key, or the `keyId:key` token.
  /// Containment (not equality) so an aliased value embedded in a larger string
  /// is still caught.
  static bool _emailAliasesSecret(
    String email,
    String deviceCode,
    DeviceAuthorizationResult result,
  ) {
    if (deviceCode.isNotEmpty && email.contains(deviceCode)) return true;
    final key = result.key;
    if (key != null && key.isNotEmpty && email.contains(key)) return true;
    final keyId = result.keyId;
    if (keyId != null && key != null && email.contains('$keyId:$key')) {
      return true;
    }
    return false;
  }

  /// Build an authorization-pending result re-surfacing the (non-secret)
  /// verification URL + user code and the call-again instruction.
  CallToolResult _authorizationPendingResult(
    _PendingLogin pending, {
    required String leadMessage,
  }) {
    return jsonResult(<String, Object?>{
      'status': 'authorization_pending',
      'verificationUri': pending.verificationUri,
      'userCode': pending.userCode,
      'message':
          '$leadMessage open ${pending.verificationUri}, enter code '
          '${pending.userCode}, and approve in your browser. THEN call '
          'restage_login again to complete sign-in.',
    });
  }

  CallToolResult _expiredResult() => jsonResult(<String, Object?>{
    'status': 'expired',
    'message':
        'The sign-in attempt expired before it was approved. Call '
        'restage_login again to start over.',
  });

  /// Open [url] best-effort; a failure is non-fatal (the URL is in the result).
  Future<void> _openBrowserBestEffort(String url) async {
    try {
      await _openBrowser(url);
    } on Object {
      // Best-effort: the verification URL is already in the response.
    }
  }

  Uri _resolveLoginEndpoint() {
    final injected = _loginEndpoint;
    if (injected != null) return injected;
    final env = Platform.environment['RESTAGE_BACKEND_URL'];
    if (env != null && env.isNotEmpty) return Uri.parse(env);
    return Uri.parse(_defaultLoginEndpoint);
  }

  /// Handle `restage_whoami`.
  Future<CallToolResult> _handleWhoami(CallToolRequest request) {
    return guardErrors('checking the session', () async {
      final credential = await _store.read();
      if (credential == null) {
        return jsonResult(<String, Object?>{'signedIn': false});
      }
      return _withRawApi(
        Uri.parse(credential.endpoint),
        credential: credential,
        body: (api) async {
          final user = await AuthApi(api).whoami();
          return user == null
              ? jsonResult(<String, Object?>{'signedIn': false})
              : jsonResult(<String, Object?>{
                  'signedIn': true,
                  'id': user.id,
                  'email': user.email,
                });
        },
      );
    });
  }

  /// Handle `restage_logout` — best-effort server revoke, always remove local.
  Future<CallToolResult> _handleLogout(CallToolRequest request) {
    return guardErrors('signing out', () async {
      final credential = await _store.read();
      if (credential == null) {
        return jsonResult(<String, Object?>{'signedOut': true});
      }
      try {
        await _withRawApi(
          Uri.parse(credential.endpoint),
          credential: credential,
          body: (api) async {
            try {
              await AuthApi(api).logout();
            } on RestageApiException {
              // Server revoke failed; remove the local credential anyway.
            }
          },
        );
      } on InsecureEndpointException {
        // Never send the credential to an insecure endpoint; still remove it
        // locally so the user is not stranded.
      }
      await _store.delete();
      return jsonResult(<String, Object?>{'signedOut': true});
    });
  }
}

/// An in-flight device-authorization attempt. The [deviceCode] is the pre-auth
/// grant secret and is held only here — never returned to the client.
class _PendingLogin {
  _PendingLogin({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresAt,
    required this.pollIntervalSeconds,
    required this.endpoint,
  });

  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final DateTime expiresAt;
  final int pollIntervalSeconds;
  final Uri endpoint;
}

/// Default poll delay — a real wait in production.
Future<void> _defaultSleep(Duration d) => Future<void>.delayed(d);

/// Default browser opener — best-effort `open` / `xdg-open` / `start`.
Future<void> _defaultOpenBrowser(String url) async {
  final String executable;
  final List<String> args;
  if (Platform.isMacOS) {
    executable = 'open';
    args = <String>[url];
  } else if (Platform.isWindows) {
    executable = 'cmd';
    args = <String>['/c', 'start', '', url];
  } else {
    executable = 'xdg-open';
    args = <String>[url];
  }
  try {
    await Process.run(executable, args);
  } on ProcessException {
    // Best-effort; the caller surfaces the URL regardless.
  }
}
