import 'dart:async';
import 'dart:io' as io;

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/commands/doctor_command.dart';
import 'package:restage_cli/src/commands/init_command.dart';
import 'package:restage_cli/src/commands/login_command.dart';
import 'package:restage_cli/src/commands/logout_command.dart';
import 'package:restage_cli/src/commands/paywall_command.dart';
import 'package:restage_cli/src/commands/preview_command.dart';
import 'package:restage_cli/src/commands/surface_command.dart';
import 'package:restage_cli/src/commands/whoami_command.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_cli/src/preview/binary_discovery.dart';

/// Backend origin baked in at build time via `--define`. Falls back to
/// localhost for local development; production builds inject the
/// deployment URL.
const _defaultEndpointFromBuild = String.fromEnvironment(
  'RESTAGE_DEFAULT_ENDPOINT',
  defaultValue: 'http://localhost:8080/',
);

/// Top-level entry for the `restage` binary.
///
/// Constructs a [CommandRunner] for the binary, dispatches the command,
/// and returns a numeric exit code:
///
/// - `0` — success.
/// - `1` — user error (bad usage, unknown command, missing argument).
/// - `2` — system error (unreachable host, I/O failure, internal bug).
///
/// Output is routed through the injected [_stdout] / [_stderr] sinks so
/// the CLI is unit-testable without spawning a subprocess. Production
/// callers pass `dart:io` `stdout` / `stderr`; tests pass [StringBuffer].
///
/// Hooks for the credential store, HTTP client, sleep delay, and
/// browser opener are exposed so end-to-end tests can drive the
/// device-authorization flow against a fake backend.
class RestageCli {
  /// Build a CLI bound to the given sinks and optional dependency
  /// overrides. Defaults to in-memory buffers and real
  /// [FileCredentialStore] / `http.Client` instances.
  RestageCli({
    StringSink? stdout,
    StringSink? stderr,
    FileCredentialStore? credentialStore,
    Uri? defaultEndpoint,
    http.Client? httpClient,
    Future<void> Function(Duration)? sleep,
    Future<void> Function(String)? openBrowser,
    Interactive Function(ArgResults globalResults)? interactiveFactory,
    PreviewBinaryLocator? previewBinaryLocator,
    PreviewLauncher? previewLauncher,
  }) : _stdout = stdout ?? StringBuffer(),
       _stderr = stderr ?? StringBuffer(),
       _credentialStore = credentialStore,
       _defaultEndpoint =
           defaultEndpoint ?? Uri.parse(_defaultEndpointFromBuild),
       _httpClient = httpClient,
       _sleep = sleep,
       _openBrowser = openBrowser,
       _interactiveFactory = interactiveFactory ?? _defaultInteractiveFactory,
       _previewBinaryLocator = previewBinaryLocator ?? _defaultPreviewLocator,
       _previewLauncher = previewLauncher ?? _defaultPreviewLauncher;

  final StringSink _stdout;
  final StringSink _stderr;
  final FileCredentialStore? _credentialStore;
  final Uri _defaultEndpoint;
  final http.Client? _httpClient;
  final Future<void> Function(Duration)? _sleep;
  final Future<void> Function(String)? _openBrowser;
  final Interactive Function(ArgResults globalResults) _interactiveFactory;
  final PreviewBinaryLocator _previewBinaryLocator;
  final PreviewLauncher _previewLauncher;

  /// Dispatch [args] through the runner and return the exit code.
  Future<int> run(List<String> args) async {
    final runner = CommandRunner<int>(
      'restage',
      'Restage — the developer surface for building, previewing, '
          'and publishing paywalls.',
    );
    // Global flag: switches every interactive prompt to its
    // non-interactive form. `--yes` is the conventional alias.
    runner.argParser
      ..addFlag(
        'non-interactive',
        negatable: false,
        help:
            'Skip every interactive prompt. Required values default; '
            'unsupplied values without a default exit non-zero with a '
            'clear "required: --foo <value>" message.',
      )
      ..addFlag(
        'yes',
        abbr: 'y',
        negatable: false,
        help: 'Alias for --non-interactive.',
      );

    // Parse the runner-level globals once so the factory can read them
    // before command dispatch. Falling back to an empty parse on
    // unknown args keeps `--help` / unknown-command paths working.
    final globalResults = _tryParseGlobals(runner.argParser, args);
    final interactive = _interactiveFactory(globalResults);

    // The credential-store path resolution can fail with [StateError]
    // when neither HOME nor APPDATA is set (e.g. a stripped-down CI
    // container). Resolve lazily — `restage --help` and unknown-command
    // errors must still work in that environment; the failure only
    // surfaces when a command actually reads or writes credentials.
    runner
      ..addCommand(
        LoginCommand(
          stdout: _stdout,
          stderr: _stderr,
          credentialStore: _credentialStore,
          defaultEndpoint: _defaultEndpoint,
          httpClient: _httpClient,
          sleep: _sleep,
          openBrowser: _openBrowser,
          interactive: interactive,
        ),
      )
      ..addCommand(
        LogoutCommand(
          stdout: _stdout,
          stderr: _stderr,
          credentialStore: _credentialStore,
          httpClient: _httpClient,
        ),
      )
      ..addCommand(
        WhoamiCommand(
          stdout: _stdout,
          stderr: _stderr,
          credentialStore: _credentialStore,
          httpClient: _httpClient,
        ),
      )
      ..addCommand(
        PaywallCommand(
          stdout: _stdout,
          stderr: _stderr,
          interactive: interactive,
          credentialStore: _credentialStore,
          httpClient: _httpClient,
        ),
      )
      ..addCommand(
        SurfaceCommand(
          stdout: _stdout,
          stderr: _stderr,
          interactive: interactive,
          credentialStore: _credentialStore,
          httpClient: _httpClient,
        ),
      )
      ..addCommand(
        InitCommand(stdout: _stdout, stderr: _stderr, interactive: interactive),
      )
      ..addCommand(DoctorCommand(stdout: _stdout, stderr: _stderr))
      ..addCommand(
        PreviewCommand(
          stdout: _stdout,
          stderr: _stderr,
          locator: _previewBinaryLocator,
          launcher: _previewLauncher,
        ),
      );
    try {
      final result = await runZoned(
        () => runner.run(args),
        zoneSpecification: ZoneSpecification(
          print: (_, _, _, line) => _stdout.writeln(line),
        ),
      );
      return result ?? 0;
    } on UsageException catch (e) {
      _stderr
        ..writeln(e.message)
        ..writeln()
        ..writeln(e.usage);
      return 1;
    }
  }

  /// Parse the runner-level globals from [args].
  ///
  /// Globals are always positional-free, so this collects the leading
  /// args up to the first non-flag (i.e. the subcommand name) and runs
  /// those through [parser]. The runner re-parses with the full grammar
  /// at dispatch time and surfaces any real error there.
  ArgResults _tryParseGlobals(ArgParser parser, List<String> args) {
    final globals = <String>[];
    for (final arg in args) {
      if (!arg.startsWith('-')) break;
      globals.add(arg);
    }
    try {
      return parser.parse(globals);
    } on FormatException {
      return parser.parse(const <String>[]);
    }
  }
}

/// Default factory: a [NonInteractive] when `--non-interactive` / `--yes`
/// is set, otherwise a [RealInteractive] wired to the process's stdin /
/// stdout.
Interactive _defaultInteractiveFactory(ArgResults globalResults) {
  final nonInteractive =
      (globalResults['non-interactive'] as bool? ?? false) ||
      (globalResults['yes'] as bool? ?? false);
  if (nonInteractive) return const NonInteractive();
  return RealInteractive(
    readLine: () async => io.stdin.readLineSync(),
    stdout: io.stdout,
  );
}

/// Default preview binary locator. Wraps the [locateRestagePreviewBinary]
/// helper, supplying the process's real environment / platform.
String? _defaultPreviewLocator({
  Map<String, String>? environment,
  bool? isWindows,
}) =>
    locateRestagePreviewBinary(environment: environment, isWindows: isWindows);

/// Default preview launcher.
///
/// Spawns [binary] detached so the wrapper exits immediately while the
/// desktop window stays open. The blob path is forwarded as the
/// `RESTAGE_PREVIEW_BLOB` environment variable; the preview app reads
/// this at runtime as a fallback to the compile-time
/// `String.fromEnvironment('RESTAGE_PREVIEW_BLOB')` value.
Future<int> _defaultPreviewLauncher({
  required String binary,
  required String blobPath,
}) async {
  await io.Process.start(
    binary,
    const <String>[],
    mode: io.ProcessStartMode.detachedWithStdio,
    environment: {...io.Platform.environment, 'RESTAGE_PREVIEW_BLOB': blobPath},
  );
  return 0;
}
