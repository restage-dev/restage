import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/measurement_page_api.dart';
import 'package:restage_cli/src/commands/authed.dart';
import 'package:restage_cli/src/commands/lifecycle_support.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_cli/src/measurement/page_read.dart';
import 'package:restage_cli/src/measurement/page_views/page_view_support.dart';
import 'package:restage_cli/src/operations/operation.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    hide RuntimePlane;
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    as measurement
    show RuntimePlane;

/// The exact measurement coordinate a resolved lifecycle context names.
TargetCoordinate targetCoordinateOf(LifecycleContext context) =>
    TargetCoordinate(
      organizationId: OrganizationId(context.organizationId),
      appId: ApplicationId(context.appId),
      environmentTargetId: EnvironmentTargetId(context.environmentTargetId),
      namedEnvironmentId: NamedEnvironmentId(context.namedEnvironmentId),
      runtimePlane: switch (context.runtimePlane) {
        RuntimePlane.live => measurement.RuntimePlane.live,
        RuntimePlane.sandbox => measurement.RuntimePlane.sandbox,
      },
    );

/// One dashboard page read as a command.
class MeasurementPageCommand extends Command<int> {
  /// Construct the command for [read].
  MeasurementPageCommand(
    this.read, {
    required StringSink stdout,
    required StringSink stderr,
    required Interactive interactive,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
    DateTime Function()? now,
  }) : _io = CommandIo(
         stdout: stdout,
         stderr: stderr,
         interactive: interactive,
         credentialStore: credentialStore,
         httpClient: httpClient,
       ),
       _now = now ?? DateTime.now {
    addLifecycleOptions(argParser, withType: false, withReason: false);
    argParser
      ..addOption(
        'from',
        help:
            'Start of the window, inclusive, as an ISO-8601 instant. '
            'Defaults to $kPageReadDefaultWindowDays days before --until.',
      )
      ..addOption(
        'until',
        help:
            'End of the window, exclusive, as an ISO-8601 instant. '
            'Defaults to now.',
      );
    for (final param in read.params) {
      switch (param.kind) {
        case PageParamKind.stringList:
          argParser.addMultiOption(
            param.cli,
            help: param.help,
            allowed: param.allowed,
          );
        case PageParamKind.flag:
          argParser.addFlag(param.cli, negatable: false, help: param.help);
        case PageParamKind.string || PageParamKind.integer:
          argParser.addOption(
            param.cli,
            help: param.help,
            allowed: param.allowed,
          );
      }
    }
    argParser.addFlag(
      'json',
      negatable: false,
      help: "Print the service's reply unchanged.",
    );
  }

  /// The read this command runs.
  final PageRead read;

  final CommandIo _io;
  final DateTime Function() _now;

  @override
  String get name => read.cliPath.split(' ').last;

  @override
  String get description => read.summary;

  @override
  String get invocation => 'restage ${read.cliPath} [options]';

  @override
  Future<int> run() async {
    final Map<String, Object?> values;
    final PageWindowMicros? window;
    try {
      values = _values();
      window = resolvePageWindow(
        read,
        startMicros: _instant('from'),
        endMicros: _instant('until'),
        now: _now(),
      );
    } on FormatException catch (error) {
      _io.stderr.writeln(error.message);
      return 1;
    }
    final asJson = argResults?['json'] as bool? ?? false;
    final chosen = read.select(values);

    return runAuthed(_io, argResults, OperationScope.target, (ctx) async {
      try {
        final reply = await MeasurementPageApi(ctx.api).read(
          chosen,
          PageRequest(
            target: targetCoordinateOf(ctx.target!),
            values: values,
            window: window,
          ),
        );
        if (asJson) {
          _io.stdout.writeln(reply);
        } else {
          renderPageReply(_io.stdout, reply, chosen.render);
        }
        return 0;
      } on MeasurementPageMismatchException catch (error) {
        _io.stderr.writeln(error);
        return 2;
      }
    });
  }

  Map<String, Object?> _values() {
    final values = <String, Object?>{};
    for (final param in read.params) {
      switch (param.kind) {
        case PageParamKind.stringList:
          final list = argResults?[param.cli] as List<String>? ?? const [];
          if (list.isNotEmpty) values[param.key] = list;
        case PageParamKind.flag:
          if (argResults?[param.cli] == true) values[param.key] = true;
        case PageParamKind.string:
          if (argResults?[param.cli] case final String value) {
            values[param.key] = value;
          }
        case PageParamKind.integer:
          if (argResults?[param.cli] case final String text) {
            final value = int.tryParse(text);
            if (value == null || value < 1) {
              throw FormatException(
                '--${param.cli} must be a whole number of 1 or more.',
              );
            }
            values[param.key] = value;
          }
      }
      if (param.required && !values.containsKey(param.key)) {
        throw FormatException('Required: --${param.cli}.');
      }
    }
    return values;
  }

  int? _instant(String option) {
    final raw = (argResults?[option] as String?)?.trim();
    if (raw == null || raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      throw FormatException('--$option must be an ISO-8601 instant.');
    }
    return parsed.toUtc().microsecondsSinceEpoch;
  }
}

/// The `analytics` group: every read of the Analytics pages.
class AnalyticsCommand extends Command<int> {
  /// Construct the group over the analytics page reads.
  AnalyticsCommand({
    required StringSink stdout,
    required StringSink stderr,
    required Interactive interactive,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
  }) {
    for (final read in pageReads) {
      if (!read.cliPath.startsWith('analytics ')) continue;
      addSubcommand(
        MeasurementPageCommand(
          read,
          stdout: stdout,
          stderr: stderr,
          interactive: interactive,
          credentialStore: credentialStore,
          httpClient: httpClient,
        ),
      );
    }
  }

  @override
  String get name => 'analytics';

  @override
  String get description => 'Read the Analytics pages for one target.';
}
