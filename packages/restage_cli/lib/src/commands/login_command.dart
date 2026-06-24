import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/auth_api.dart';
import 'package:restage_cli/src/api/auth_models.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/credentials/credential.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';

/// Default sleep — `Future.delayed` in production.
Future<void> _defaultSleep(Duration d) => Future<void>.delayed(d);

/// Default browser opener — best-effort `open`/`xdg-open`/`start`.
/// Failure is logged via the [stderr] sink and otherwise swallowed; the
/// CLI's flow falls back to "open this URL yourself".
Future<void> _defaultOpenBrowser(String url) async {
  String executable;
  List<String> args;
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
    // Caller decides what to print; the launch path is best-effort.
  }
}

/// Sign in via the device-authorization flow.
///
/// Calls `auth.startDeviceAuthorization`, prints the verification URL
/// and user code, optionally opens the browser, then polls
/// `auth.exchangeDeviceCode` until the grant resolves. On success the
/// returned credential is persisted to the local credential store.
class LoginCommand extends Command<int> {
  /// Construct a login command.
  LoginCommand({
    required StringSink stdout,
    required StringSink stderr,
    required Uri defaultEndpoint,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
    Future<void> Function(Duration)? sleep,
    Future<void> Function(String)? openBrowser,
    Interactive? interactive,
  }) : _stdout = stdout,
       _stderr = stderr,
       _credentialStore = credentialStore,
       _defaultEndpoint = defaultEndpoint,
       _httpClient = httpClient,
       _sleep = sleep ?? _defaultSleep,
       _openBrowser = openBrowser ?? _defaultOpenBrowser,
       _interactive = interactive ?? const NonInteractive() {
    argParser
      ..addOption(
        'endpoint',
        help:
            'Backend origin to authenticate against. Defaults to the '
            'production deployment.',
      )
      ..addFlag(
        'open',
        help: 'Open the verification URL in the system browser.',
        defaultsTo: true,
      )
      ..addFlag(
        'no-browser',
        negatable: false,
        help:
            'Do not attempt to open the verification URL in a browser. '
            'Use for headless or remote sessions.',
      );
  }

  final StringSink _stdout;
  final StringSink _stderr;
  final FileCredentialStore? _credentialStore;
  final Uri _defaultEndpoint;
  final http.Client? _httpClient;
  final Future<void> Function(Duration) _sleep;
  final Future<void> Function(String) _openBrowser;
  final Interactive _interactive;

  @override
  String get name => 'login';

  @override
  String get description =>
      'Sign in via the device-authorization flow and store the '
      'credential locally.';

  @override
  Future<int> run() async {
    final endpoint = _resolveEndpoint();
    final store = _credentialStore ?? FileCredentialStore.atDefaultLocation();
    final RestageApi api;
    try {
      api = RestageApi(endpoint: endpoint, httpClient: _httpClient);
    } on InsecureEndpointException catch (e) {
      _stderr.writeln(e.toString());
      return 1;
    }
    try {
      final auth = AuthApi(api);

      final DeviceAuthorizationStart start;
      try {
        start = await auth.startDeviceAuthorization();
      } on RestageApiException catch (e) {
        _stderr.writeln('Could not contact the backend: ${e.body}');
        return 2;
      }

      _stdout
        ..writeln('To finish signing in, visit:')
        ..writeln('  ${start.verificationUri}')
        ..writeln()
        ..writeln('and enter the verification code:')
        ..writeln('  ${start.userCode}')
        ..writeln();

      final noBrowser = argResults?['no-browser'] as bool? ?? false;
      final openFlag = argResults?['open'] as bool? ?? true;
      if (!noBrowser && openFlag) {
        if (_isSafeVerificationUri(start.verificationUri)) {
          try {
            await _openBrowser(start.verificationUri);
          } on Object {
            _stdout.writeln(
              "Couldn't open a browser automatically — open the URL above "
              'manually.',
            );
          }
        } else {
          // Never hand an untrusted scheme to the system opener. The URL is
          // still printed above for the user to open deliberately.
          _stdout.writeln(
            'The verification URL uses an unexpected scheme and will not be '
            'opened automatically — open the URL above manually.',
          );
        }
      }

      final spinner = _interactive.spinner(
        _spinnerMessage(start.userCode, elapsed: Duration.zero),
      )..start();

      final stopwatch = Stopwatch()..start();
      var pollInterval = Duration(seconds: start.pollIntervalSeconds);
      try {
        while (true) {
          await _sleep(pollInterval);
          spinner.update(
            _spinnerMessage(start.userCode, elapsed: stopwatch.elapsed),
          );
          final DeviceAuthorizationResult result;
          try {
            result = await auth.exchangeDeviceCode(start.deviceCode);
          } on RestageApiException catch (e) {
            spinner.stop();
            _stderr.writeln('Could not contact the backend: ${e.body}');
            return 2;
          }
          switch (result.status) {
            case DeviceAuthorizationStatus.pending:
              // Honour the server's per-poll back-off when it asks for a
              // longer interval (RFC 8628 `slow_down` semantics).
              if (result.pollIntervalSeconds != null) {
                pollInterval = Duration(seconds: result.pollIntervalSeconds!);
              }
              continue;
            case DeviceAuthorizationStatus.success:
              spinner.stop();
              await _persistCredential(store, endpoint, result);
              final email = result.userInfo?.email;
              _stdout.writeln(
                email == null ? 'Signed in.' : 'Signed in as $email.',
              );
              return 0;
            case DeviceAuthorizationStatus.expired:
              spinner.stop();
              _stderr.writeln(
                'The sign-in attempt expired before it was approved. Run '
                '`restage login` again.',
              );
              return 1;
            case DeviceAuthorizationStatus.notFound:
              spinner.stop();
              _stderr.writeln(
                'The sign-in attempt could not be completed. Run `restage '
                'login` again.',
              );
              return 1;
          }
        }
      } finally {
        spinner.stop();
      }
    } finally {
      if (_httpClient == null) api.close();
    }
  }

  /// Whether [verificationUri] is safe to hand to the system browser opener.
  ///
  /// The URL is server-supplied, so its scheme is validated before launch:
  /// only `https://` (and `http://` against a loopback host, for local
  /// development) is accepted. This reuses the same transport policy the API
  /// client applies to credential-bearing requests.
  bool _isSafeVerificationUri(String verificationUri) {
    final Uri uri;
    try {
      uri = Uri.parse(verificationUri);
    } on FormatException {
      return false;
    }
    return isAcceptableTransport(uri);
  }

  String _spinnerMessage(String userCode, {required Duration elapsed}) {
    final seconds = elapsed.inSeconds;
    return 'Waiting for approval — code $userCode (${seconds}s elapsed)';
  }

  Uri _resolveEndpoint() {
    final fromFlag = argResults?['endpoint'] as String?;
    if (fromFlag != null && fromFlag.isNotEmpty) return Uri.parse(fromFlag);
    final fromEnv = Platform.environment['RESTAGE_BACKEND_URL'];
    if (fromEnv != null && fromEnv.isNotEmpty) return Uri.parse(fromEnv);
    return _defaultEndpoint;
  }

  Future<void> _persistCredential(
    FileCredentialStore store,
    Uri endpoint,
    DeviceAuthorizationResult result,
  ) async {
    final keyId = result.keyId;
    final key = result.key;
    if (keyId == null || key == null) {
      // Guard against a half-formed credential reaching disk.
      throw StateError('Backend returned success without AuthKey credentials.');
    }
    await store.write(
      Credential(
        endpoint: endpoint.toString(),
        kind: CredentialKind.authKey,
        authToken: '$keyId:$key',
      ),
    );
  }
}
