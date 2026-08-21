import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/api/measurement_wire.dart';
import 'package:restage_cli/src/api/programmatic_mutation_api.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/commands/experimental_gate.dart';
import 'package:restage_cli/src/commands/lifecycle_support.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    as measurement;

/// Applies one exact canonical mutation request.
class ProgrammaticMutationCommand extends Command<int> {
  /// Creates the canonical mutation command.
  ProgrammaticMutationCommand({
    required StringSink stdout,
    required StringSink stderr,
    required Interactive interactive,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
    Map<String, String>? environment,
  }) : _stdout = stdout,
       _stderr = stderr,
       _interactive = interactive,
       _credentialStore = credentialStore,
       _httpClient = httpClient,
       _environment = environment {
    addLifecycleOptions(argParser, withType: false, withReason: false);
    argParser
      ..addOption(
        'request',
        help: 'Path to an exact canonical mutation request file (required).',
      )
      ..addOption(
        'response',
        help: 'Path for the exact canonical mutation response file (required).',
      );
  }

  final StringSink _stdout;
  final StringSink _stderr;
  final Interactive _interactive;
  final FileCredentialStore? _credentialStore;
  final http.Client? _httpClient;
  final Map<String, String>? _environment;

  @override
  String get name => 'mutation';

  @override
  String get description => 'Apply one exact canonical mutation request.';

  @override
  bool get hidden => !experimentalCommandsEnabled(_environment);

  @override
  Future<int> run() async {
    if (!experimentalCommandsEnabled(_environment)) {
      _stderr.writeln(experimentalCommandRefusal(name));
      return 1;
    }
    final requestPath = _requiredPath('request');
    final responsePath = _requiredPath('response');
    if (requestPath == null || responsePath == null) return 1;

    final requestFile = File(requestPath);
    final responseFile = File(responsePath);
    if (p.normalize(requestFile.absolute.path) ==
        p.normalize(responseFile.absolute.path)) {
      _stderr.writeln('--request and --response must name different files.');
      return 1;
    }

    final input = await _readCanonicalRequest(requestFile);
    if (input == null) return 1;

    final context = await loadLifecycleContext(
      argResults: argResults,
      interactive: _interactive,
      stderr: _stderr,
      credentialStore: _credentialStore,
      httpClient: _httpClient,
    );
    if (context == null) return 1;

    final RestageApi api;
    try {
      api = RestageApi(
        endpoint: context.apiEndpoint,
        httpClient: _httpClient,
        credential: context.credential,
      );
    } on InsecureEndpointException catch (error) {
      _stderr.writeln(error);
      return 1;
    }

    try {
      final response = await ProgrammaticMutationApi(api).mutateCanonicalBytes(
        projectSlug: context.project,
        appSlug: context.app,
        environmentSlug: context.environment,
        organizationId: context.organizationId,
        appId: context.appId,
        namedEnvironmentId: context.namedEnvironmentId,
        environmentTargetId: context.environmentTargetId,
        runtimePlane: context.runtimePlane,
        canonicalRequestBytes: input,
      );
      if (!await _writeResponse(responseFile, response.canonicalBytes)) {
        return 2;
      }
      _stdout.writeln('Wrote canonical response to ${responseFile.path}.');
      return 0;
    } on ProgrammaticMutationTargetMismatchException {
      _stderr.writeln(
        'The canonical request targets a different organization, app, '
        'named environment, environment target, or runtime plane. Confirm '
        '--project, --app, --env, and --plane, then use a request for that '
        'exact target.',
      );
      return 1;
    } on RestageApiException catch (error) {
      _stderr.writeln(
        'The canonical mutation was not accepted (HTTP ${error.statusCode}). '
        'Confirm the selected target and authorization, then retry.',
      );
      return error.statusCode >= 500 ? 2 : 1;
    } on measurement.CanonicalFormatException {
      _stderr.writeln('The service returned an invalid canonical response.');
      return 2;
    } on FormatException {
      _stderr.writeln('The service returned an invalid canonical response.');
      return 2;
    } finally {
      if (_httpClient == null) api.close();
    }
  }

  String? _requiredPath(String option) {
    final value = (argResults?[option] as String?)?.trim();
    if (value != null && value.isNotEmpty) return value;
    _stderr.writeln('Required: --$option <path>.');
    return null;
  }

  Future<Uint8List?> _readCanonicalRequest(File file) async {
    final int length;
    try {
      length = await file.length();
    } on FileSystemException {
      _stderr.writeln('Could not read the request file.');
      return null;
    }
    if (length == 0 || length > kMaximumProgrammaticMutationWireBytes) {
      _stderr.writeln(
        'Request file must contain 1..'
        '$kMaximumProgrammaticMutationWireBytes bytes.',
      );
      return null;
    }

    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on FileSystemException {
      _stderr.writeln('Could not read the request file.');
      return null;
    }
    if (bytes.isEmpty || bytes.length > kMaximumProgrammaticMutationWireBytes) {
      _stderr.writeln(
        'Request file must contain 1..'
        '$kMaximumProgrammaticMutationWireBytes bytes.',
      );
      return null;
    }
    try {
      ProgrammaticMutationRequestWireV1.fromCanonicalBytes(bytes);
      return Uint8List.fromList(bytes);
    } on measurement.CanonicalFormatException {
      _stderr.writeln(
        'Request file must contain one exact canonical mutation request.',
      );
      return null;
    }
  }

  Future<bool> _writeResponse(File file, List<int> bytes) async {
    if (!await file.parent.exists()) {
      _stderr.writeln('Response directory does not exist.');
      return false;
    }
    try {
      await file.writeAsBytes(bytes, flush: true);
      return true;
    } on FileSystemException {
      _stderr.writeln('Could not write the response file.');
      return false;
    }
  }
}
