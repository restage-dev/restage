import 'dart:async';
import 'dart:io' as io;

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/commands/build_command.dart';
import 'package:restage_cli/src/commands/build_push_command.dart';
import 'package:restage_cli/src/commands/authed.dart';
import 'package:restage_cli/src/commands/measurement_page_command.dart';
import 'package:restage_cli/src/measurement/page_read.dart' show pageReads;
import 'package:restage_cli/src/commands/catalog_command.dart';
import 'package:restage_cli/src/commands/docs_command.dart';
import 'package:restage_cli/src/commands/doctor_command.dart';
import 'package:restage_cli/src/commands/delivery_command.dart';
import 'package:restage_cli/src/commands/console_command.dart';
import 'package:restage_cli/src/commands/experiment_activation_command.dart';
import 'package:restage_cli/src/commands/experiment_command.dart';
import 'package:restage_cli/src/commands/init_command.dart';
import 'package:restage_cli/src/commands/login_command.dart';
import 'package:restage_cli/src/commands/logout_command.dart';
import 'package:restage_cli/src/commands/paywall_command.dart';
import 'package:restage_cli/src/commands/programmatic_mutation_command.dart';
import 'package:restage_cli/src/commands/spec_command.dart';
import 'package:restage_cli/src/commands/status_command.dart';
import 'package:restage_cli/src/commands/surface_command.dart';
import 'package:restage_cli/src/commands/target_resolution.dart';
import 'package:restage_cli/src/commands/whoami_command.dart';
import 'package:restage_cli/src/api/default_endpoint.dart';
import 'package:restage_cli/src/api/experiment_activation_api.dart';
import 'package:restage_cli/src/api/selector_syntax.dart';
import 'package:restage_cli/src/config/restage_config.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_cli/src/render_bundles/bundle_source.dart';
import 'package:restage_cli/src/render_bundles/flutter_render_bundle_builder.dart';
import 'package:restage_cli/src/render_bundles/flutter_toolchain.dart';
import 'package:restage_cli/src/render_bundles/generated_widget_catalog.dart';
import 'package:restage_cli/src/tui/console_command_executor.dart';
import 'package:restage_cli/src/tui/console_controller.dart';
import 'package:restage_cli/src/tui/console_repository.dart';
import 'package:restage_cli/src/tui/restage_tui.dart';

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
    bool Function()? hasTerminal,
    ConsoleLauncher? consoleLauncher,
    ConsoleController Function(io.Directory? directory)?
    consoleControllerFactory,
    RenderBundleArtifactBuilder? renderBundleBuilder,
    RenderBundleCatalogProducer? renderBundleCatalog,
    BundleSourceReader? renderBundleSource,
    ReleaseRecorderOpener? renderBundleRecorderOpener,
    RenderBundlePushReceipt? renderBundleReceipt,
    FlutterToolchainResolver? renderBundleFlutterToolchain,
    ExperimentActivationApi? experimentActivationApi,
    Map<String, String>? environment,
    SelectorSyntax selectorSyntax = SelectorSyntax.cli,
    CommandTargetDefaults? targetDefaults,
    void Function(Map<String, String> selectors)? onTargetSelectors,
  }) : _stdout = stdout ?? StringBuffer(),
       _targetDefaults = targetDefaults,
       _onTargetSelectors = onTargetSelectors,
       _selectorSyntax = selectorSyntax,
       _stderr = stderr ?? StringBuffer(),
       _credentialStore = credentialStore,
       _defaultEndpoint = defaultEndpoint ?? Uri.parse(defaultRestageEndpoint),
       _httpClient = httpClient,
       _sleep = sleep,
       _openBrowser = openBrowser,
       _interactiveFactory = interactiveFactory ?? _defaultInteractiveFactory,
       _hasTerminal = hasTerminal ?? stdioHasTerminal,
       _consoleLauncher = consoleLauncher ?? runRestageConsole,
       _renderBundleBuilder = renderBundleBuilder,
       _renderBundleCatalog = renderBundleCatalog,
       _renderBundleSource = renderBundleSource,
       _renderBundleRecorderOpener = renderBundleRecorderOpener,
       _renderBundleReceipt = renderBundleReceipt,
       _renderBundleFlutterToolchain = renderBundleFlutterToolchain,
       _experimentActivationApi = experimentActivationApi,
       _environment = environment,
       _consoleControllerFactory =
           consoleControllerFactory ??
           ((directory) => ConsoleController(
             repository: DefaultConsoleRepository(
               credentialStore: credentialStore,
               httpClient: httpClient,
               directory: directory,
             ),
             operationExecutor: ConsoleCommandExecutor(
               credentialStore: credentialStore,
               httpClient: httpClient,
               directory: directory,
             ),
           ));

  final StringSink _stdout;
  final StringSink _stderr;
  final SelectorSyntax _selectorSyntax;
  final CommandTargetDefaults? _targetDefaults;
  final void Function(Map<String, String> selectors)? _onTargetSelectors;
  final FileCredentialStore? _credentialStore;
  final Uri _defaultEndpoint;
  final http.Client? _httpClient;
  final Future<void> Function(Duration)? _sleep;
  final Future<void> Function(String)? _openBrowser;
  final Interactive Function(ArgResults globalResults) _interactiveFactory;
  final bool Function() _hasTerminal;
  final ConsoleLauncher _consoleLauncher;
  final ConsoleController Function(io.Directory? directory)
  _consoleControllerFactory;
  final RenderBundleArtifactBuilder? _renderBundleBuilder;
  final RenderBundleCatalogProducer? _renderBundleCatalog;
  final BundleSourceReader? _renderBundleSource;
  final ReleaseRecorderOpener? _renderBundleRecorderOpener;
  final RenderBundlePushReceipt? _renderBundleReceipt;
  final FlutterToolchainResolver? _renderBundleFlutterToolchain;
  final ExperimentActivationApi? _experimentActivationApi;
  final Map<String, String>? _environment;

  /// Dispatch [args] through the runner and return the exit code.
  Future<int> run(List<String> arguments) async {
    final (:directory, args: unplaced) = _takeLeadingDirectory(arguments);
    // Parse the runner-level globals once so the factory can read them
    // before command dispatch. Falling back to an empty parse on
    // unknown args keeps `--help` / unknown-command paths working.
    final globalResults = _tryParseGlobals(_globalParser(), unplaced);
    final runner = commandRunner(
      interactive: _interactiveFactory(globalResults),
    );
    final args = _placeDirectory(runner, unplaced, directory);
    try {
      if (args.isEmpty && _hasTerminal()) {
        return await runConsole(
          _consoleLauncher,
          _consoleControllerFactory(null),
        );
      }
      final result = await runZoned(
        () => runner.run(_inheritTarget(runner, args)),
        zoneValues: selectorSyntaxZoneValues(_selectorSyntax),
        zoneSpecification: ZoneSpecification(
          print: (_, _, _, line) => _stdout.writeln(line),
        ),
      );
      return result ?? 0;
    } on UsageException catch (e) {
      _stderr.writeln(usageFailureMessage(runner, args, e.message));
      return 1;
    } on RestageConfigFormatException catch (e) {
      _stderr.writeln('Could not read restage_config.yaml: ${e.message}');
      return 1;
    }
  }

  List<String> _inheritTarget(CommandRunner<int> runner, List<String> args) {
    final defaults = _targetDefaults;
    if (defaults == null) return args;
    var results = runner.parse(args);
    var parser = runner.argParser;
    while (results.command != null) {
      results = results.command!;
      parser = parser.commands[results.name]!;
    }
    final selectors = defaults.selectorsFor(parser, results);
    if (selectors.isEmpty) return args;
    _onTargetSelectors?.call(selectors);
    final inherited = [
      for (final entry in selectors.entries)
        if (!results.wasParsed(entry.key)) '--${entry.key}=${entry.value}',
    ];
    return _insertOptions(args, inherited);
  }

  /// The command tree [run] dispatches through, prompting via [interactive].
  CommandRunner<int> commandRunner({
    Interactive interactive = const NonInteractive(),
  }) {
    final runner = _RestageRunner(
      'restage',
      'Restage — tools for building, previewing, and publishing Flutter '
          'surfaces.',
      defaultEndpoint: _defaultEndpoint,
    );
    _addGlobalOptions(runner.argParser);
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
        StatusCommand(
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
        CatalogCommand(
          stdout: _stdout,
          stderr: _stderr,
          credentialStore: _credentialStore,
          httpClient: _httpClient,
        ),
      )
      ..addCommand(
        BuildCommand(
          stdout: _stdout,
          stderr: _stderr,
          credentialStore: _credentialStore,
          httpClient: _httpClient,
          builder: _renderBundleBuilder,
          catalog: _renderBundleCatalog,
          source: _renderBundleSource,
          openRecorder: _renderBundleRecorderOpener,
          recordReceipt: _renderBundleReceipt,
          defaultEndpoint: _defaultEndpoint,
          environment: _environment,
          flutterToolchain: _renderBundleFlutterToolchain,
        ),
      )
      ..addCommand(
        ProgrammaticMutationCommand(
          stdout: _stdout,
          stderr: _stderr,
          interactive: interactive,
          credentialStore: _credentialStore,
          httpClient: _httpClient,
          environment: _environment,
        ),
      )
      ..addCommand(
        DeliveryCommand(
          stdout: _stdout,
          stderr: _stderr,
          interactive: interactive,
          credentialStore: _credentialStore,
          httpClient: _httpClient,
        ),
      )
      ..addCommand(
        AnalyticsCommand(
          stdout: _stdout,
          stderr: _stderr,
          interactive: interactive,
          credentialStore: _credentialStore,
          httpClient: _httpClient,
        ),
      )
      ..addCommand(
        MeasurementPageCommand(
          pageReads.singleWhere((read) => read.cliPath == 'where'),
          stdout: _stdout,
          stderr: _stderr,
          interactive: interactive,
          credentialStore: _credentialStore,
          httpClient: _httpClient,
        ),
      )
      ..addCommand(
        ExperimentCommand(
          stdout: _stdout,
          stderr: _stderr,
          interactive: interactive,
          credentialStore: _credentialStore,
          httpClient: _httpClient,
        ),
      )
      ..addCommand(
        InitCommand(
          stdout: _stdout,
          stderr: _stderr,
          interactive: interactive,
          credentialStore: _credentialStore,
          httpClient: _httpClient,
        ),
      )
      ..addCommand(
        DoctorCommand(
          stdout: _stdout,
          stderr: _stderr,
          credentialStore: _credentialStore,
          httpClient: _httpClient,
        ),
      )
      ..addCommand(
        ConsoleCommand(
          controllerFactory: _consoleControllerFactory,
          launcher: _consoleLauncher,
          interactive: interactive,
        ),
      )
      ..addCommand(
        DocsCommand(
          stdout: _stdout,
          stderr: _stderr,
          httpClient: _httpClient,
          environment: _environment,
        ),
      );
    operationCommands(
      CommandIo(
        stdout: _stdout,
        stderr: _stderr,
        interactive: interactive,
        credentialStore: _credentialStore,
        httpClient: _httpClient,
      ),
      exclude: const {'surface'},
    ).forEach(runner.addCommand);
    final experimentActivationApi = _experimentActivationApi;
    if (experimentActivationApi != null) {
      runner.addCommand(
        ExperimentActivationCommand(
          api: experimentActivationApi,
          stdout: _stdout,
          stderr: _stderr,
          interactive: interactive,
          environment: _environment,
        ),
      );
    }
    return runner;
  }

  ArgParser _globalParser() =>
      _addGlobalOptions(CommandRunner<int>('restage', '').argParser);

  // Global flag: switches every interactive prompt to its non-interactive
  // form. `--yes` is the conventional alias.
  ArgParser _addGlobalOptions(ArgParser parser) => parser
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
    )
    ..addOption(
      'directory',
      abbr: 'C',
      help:
          'Directory to start the restage_config.yaml search from, for '
          'commands that read one.',
    );

  /// Split a `-C <dir>` given before the command off [args].
  static ({String? directory, List<String> args}) _takeLeadingDirectory(
    List<String> args,
  ) {
    final rest = [...args];
    for (var index = 0; index < rest.length; index++) {
      final arg = rest[index];
      if (!arg.startsWith('-')) break;
      if ((arg == '-C' || arg == '--directory') && index + 1 < rest.length) {
        final directory = rest[index + 1];
        rest.removeRange(index, index + 2);
        return (directory: directory, args: rest);
      }
      for (final prefix in ['--directory=', '-C']) {
        if (arg.startsWith(prefix) && arg.length > prefix.length) {
          rest.removeAt(index);
          return (directory: arg.substring(prefix.length), args: rest);
        }
      }
    }
    return (directory: null, args: args);
  }

  /// Hand [directory] to the command [args] name when it reads one, unless
  /// the command was given its own.
  static List<String> _placeDirectory(
    CommandRunner<int> runner,
    List<String> args,
    String? directory,
  ) {
    if (directory == null) return args;
    var commands = runner.commands;
    ArgParser? parser;
    var index = 0;
    while (index < args.length && args[index].startsWith('-')) {
      index++;
    }
    for (; index < args.length; index++) {
      final command = commands[args[index]];
      if (command == null) break;
      parser = command.argParser;
      commands = command.subcommands;
    }
    final own = args
        .skip(index)
        .any((arg) => arg.startsWith('-C') || arg.startsWith('--directory'));
    if (own || !(parser?.options.containsKey('directory') ?? false)) {
      return args;
    }
    return _insertOptions(args, ['--directory', directory]);
  }

  static List<String> _insertOptions(List<String> args, List<String> options) {
    final separator = args.indexOf('--');
    final insertion = separator < 0 ? args.length : separator;
    return [...args.take(insertion), ...options, ...args.skip(insertion)];
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

/// The lines a usage error prints: the error, the commands beside this one
/// that take an unknown option, and where to read this command's options.
String usageFailureMessage(
  CommandRunner<int> runner,
  List<String> args,
  String message,
) {
  final path = <String>[];
  Map<String, Command<int>> siblings = runner.commands;
  Map<String, Command<int>> commands = runner.commands;
  for (final arg in args) {
    if (arg.startsWith('-')) continue;
    final command = commands[arg];
    if (command == null) break;
    path.add(command.name);
    siblings = commands;
    commands = command.subcommands;
  }
  final lines = [message];
  final option = RegExp(r'option named "--?([^"]+)"').firstMatch(message);
  if (option != null && path.isNotEmpty) {
    final name = option.group(1)!;
    final parent = path.sublist(0, path.length - 1).join(' ');
    final takers = [
      for (final command in siblings.values)
        if (!command.hidden &&
            command.name != path.last &&
            command.argParser.options.containsKey(name))
          'restage ${parent.isEmpty ? '' : '$parent '}${command.name}',
    ];
    if (takers.isNotEmpty)
      lines.add('--$name is an option of ${takers.join(', ')}.');
  }
  final helpPath = ['restage', ...path].join(' ');
  lines.add('Run `$helpPath --help` to see its options.');
  return lines.join('\n');
}

final class _RestageRunner extends CommandRunner<int> {
  _RestageRunner(
    super.executableName,
    super.description, {
    required this.defaultEndpoint,
  });

  final Uri defaultEndpoint;

  @override
  String get usageFooter =>
      'Commands use the server you signed in to, ${defaultEndpoint.origin} '
      'by default. Run `restage login --endpoint <url>` to use another.';
}
