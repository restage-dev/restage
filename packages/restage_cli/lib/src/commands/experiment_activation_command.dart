import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/api/experiment_activation_api.dart';
import 'package:restage_cli/src/api/experiment_activation_host_transport.dart';
import 'package:restage_cli/src/api/measurement_wire.dart';
import 'package:restage_cli/src/commands/experimental_gate.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    as measurement;

/// Applies one exact canonical experiment activation command.
///
/// The command is intentionally usable only when its embedding host injects
/// an authority transport. It does not select a backend endpoint or derive
/// any activation-owned values.
class ExperimentActivationCommand extends Command<int> {
  /// Creates the command over an already-composed activation API boundary.
  ExperimentActivationCommand({
    required ExperimentActivationApi api,
    required StringSink stdout,
    required StringSink stderr,
    Map<String, String>? environment,
  }) : _api = api,
       _stdout = stdout,
       _stderr = stderr,
       _environment = environment {
    argParser
      ..addOption(
        'request',
        help: 'Path to an exact canonical activation command file (required).',
      )
      ..addOption(
        'response',
        help: 'Path for the exact canonical activation result file (required).',
      );
  }

  final ExperimentActivationApi _api;
  final StringSink _stdout;
  final StringSink _stderr;
  final Map<String, String>? _environment;

  @override
  String get name => 'experiment-activation';

  @override
  String get description => 'Apply one exact canonical experiment activation.';

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

    final requestBytes = await _readCommand(requestFile);
    if (requestBytes == null) return 1;

    final ExperimentActivationResultWireV1 result;
    try {
      result = await _api.executeCanonicalBytes(requestBytes);
    } on ExperimentActivationRouteProfileMismatchException {
      _stderr.writeln(
        'The canonical command does not match the configured activation '
        'target.',
      );
      return 1;
    } on ExperimentActivationTransportUnavailableException {
      _stderr.writeln('The configured activation transport is unavailable.');
      return 2;
    } on measurement.CanonicalFormatException {
      _stderr.writeln('The authority returned an invalid canonical result.');
      return 2;
    } on FormatException {
      _stderr.writeln('The authority returned an invalid canonical result.');
      return 2;
    }

    if (!await _writeResult(responseFile, result.canonicalBytes)) return 2;
    _stdout.writeln(
      'Wrote canonical activation result to ${responseFile.path}.',
    );
    return 0;
  }

  String? _requiredPath(String option) {
    final value = (argResults?[option] as String?)?.trim();
    if (value != null && value.isNotEmpty) return value;
    _stderr.writeln('Required: --$option <path>.');
    return null;
  }

  Future<Uint8List?> _readCommand(File file) async {
    final int length;
    try {
      length = await file.length();
    } on FileSystemException {
      _stderr.writeln('Could not read the command file.');
      return null;
    }
    if (length == 0 || length > kMaximumExperimentActivationWireBytes) {
      _stderr.writeln(
        'Command file must contain 1..'
        '$kMaximumExperimentActivationWireBytes bytes.',
      );
      return null;
    }

    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on FileSystemException {
      _stderr.writeln('Could not read the command file.');
      return null;
    }
    try {
      ExperimentActivationCommandWireV1.fromCanonicalBytes(bytes);
    } on measurement.CanonicalFormatException {
      _stderr.writeln(
        'Command file must contain one exact canonical activation command.',
      );
      return null;
    }
    return Uint8List.fromList(bytes);
  }

  Future<bool> _writeResult(File file, List<int> bytes) async {
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
