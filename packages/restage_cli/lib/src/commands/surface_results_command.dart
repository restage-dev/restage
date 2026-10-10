import 'dart:async';
import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/surface_funnel_api.dart';
import 'package:restage_cli/src/api/typed_error_renderer.dart';
import 'package:restage_cli/src/commands/lifecycle_support.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    hide RuntimePlane;
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    as measurement
    show RuntimePlane;

/// Days of history one read covers when the caller names no window.
const int kSurfaceResultsDefaultWindowDays = 30;

/// Reads one surface's funnel: views, steps, drop-off, completions.
class SurfaceResultsCommand extends Command<int> {
  /// Construct a results command.
  SurfaceResultsCommand({
    required StringSink stdout,
    required StringSink stderr,
    required Interactive interactive,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
    DateTime Function()? now,
  }) : _stdout = stdout,
       _stderr = stderr,
       _interactive = interactive,
       _credentialStore = credentialStore,
       _httpClient = httpClient,
       _now = now ?? DateTime.now {
    addLifecycleOptions(
      argParser,
      withType: false,
      withReason: false,
      withContractVersion: false,
      withSourceKind: false,
    );
    argParser
      ..addOption(
        'from',
        help:
            'Start of the window, inclusive, as an ISO-8601 instant. '
            'Defaults to $kSurfaceResultsDefaultWindowDays days before '
            '--until.',
      )
      ..addOption(
        'until',
        help:
            'End of the window, exclusive, as an ISO-8601 instant. '
            'Defaults to now.',
      )
      ..addMultiOption(
        'version',
        help:
            'Read only this published version. Repeat to name several; '
            'omit for every version served in the window.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print the reading as JSON, including every exact rate pair.',
      );
  }

  final StringSink _stdout;
  final StringSink _stderr;
  final Interactive _interactive;
  final FileCredentialStore? _credentialStore;
  final http.Client? _httpClient;
  final DateTime Function() _now;

  @override
  String get name => 'results';

  @override
  String get description =>
      "Read one surface's funnel: views, steps, drop-off and completions per "
      'published version.';

  @override
  String get invocation => 'restage surface results <surface-id>';

  @override
  Future<int> run() async {
    final rest = argResults?.rest ?? const <String>[];
    if (rest.length != 1) {
      _stderr.writeln(
        'Name exactly one surface identity, as discovery reports it.',
      );
      return 1;
    }
    final asJson = argResults?['json'] as bool? ?? false;

    final DateTime until;
    final DateTime from;
    try {
      until = _instant('until') ?? _now().toUtc();
      from =
          _instant('from') ??
          until.subtract(
            const Duration(days: kSurfaceResultsDefaultWindowDays),
          );
    } on FormatException catch (error) {
      _stderr.writeln(error.message);
      return 1;
    }

    // Built before the read opens, so a value the caller supplied is reported
    // as the caller's with the field named.
    final SurfaceFunnelSelectionV1 selection;
    try {
      final versions = argResults?['version'] as List<String>? ?? const [];
      selection = SurfaceFunnelSelectionV1(
        surfaceId: rest.single,
        windowStartMicros: from.microsecondsSinceEpoch,
        windowEndExclusiveMicros: until.microsecondsSinceEpoch,
        surfaceRevisionIds: versions.isEmpty ? null : versions,
      );
    } on CanonicalFormatException catch (error) {
      _stderr.writeln(error.message);
      return 1;
    }

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
      final view = await SurfaceFunnelApi(api).read(
        target: TargetCoordinate(
          organizationId: OrganizationId(context.organizationId),
          appId: ApplicationId(context.appId),
          environmentTargetId: EnvironmentTargetId(context.environmentTargetId),
          namedEnvironmentId: NamedEnvironmentId(context.namedEnvironmentId),
          runtimePlane: switch (context.runtimePlane) {
            RuntimePlane.live => measurement.RuntimePlane.live,
            RuntimePlane.sandbox => measurement.RuntimePlane.sandbox,
          },
        ),
        selection: selection,
      );
      if (asJson) {
        _stdout.writeln(jsonEncode(view.toJson()));
      } else {
        _stdout.writeln(renderSurfaceFunnel(view));
      }
      return 0;
    } on SurfaceFunnelMismatchException catch (error) {
      _stderr.writeln(error);
      return 2;
    } on CanonicalFormatException {
      _stderr.writeln('The service returned an invalid funnel reading.');
      return 2;
    } on RestageApiException catch (error) {
      return _renderError(error);
    } finally {
      if (_httpClient == null) api.close();
    }
  }

  DateTime? _instant(String option) {
    final raw = (argResults?[option] as String?)?.trim();
    if (raw == null || raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      throw FormatException('--$option must be an ISO-8601 instant.');
    }
    return parsed.toUtc();
  }

  int _renderError(RestageApiException error) {
    final outcome = renderGenericTypedError(error);
    if (outcome != null) {
      _stderr.writeln(outcome.message);
      return outcome.exitCode;
    }
    _stderr.writeln(error);
    return 1;
  }
}

/// Renders one funnel reading for a human reader.
///
/// The exact fraction behind each decimal is in the reading itself; `--json`
/// prints it.
String renderSurfaceFunnel(SurfaceFunnelViewV1 view) {
  final lines = <String>[
    'Funnel for ${view.surfaceId}'
        '${view.surfaceType == null ? '' : ' (${view.surfaceType})'}, '
        '${view.versions.length} version(s), '
        'floor ${view.disclosureFloor}:',
  ];
  for (final version in view.versions) {
    lines.add(
      '  v${version.revisionOrdinal} ${version.surfaceRevisionId} '
      '[${version.status.wireName}]',
    );
    final counts = version.counts;
    if (counts == null) {
      lines.add('    no figures (${version.disclosure.wireName})');
      continue;
    }
    lines.add(_countsLine(counts));
    for (final step in version.steps) {
      final stepCounts = step.counts;
      final onward = step.transitionTargets.isEmpty
          ? ''
          : ' -> ${step.transitionTargets.join(', ')}';
      if (stepCounts == null) {
        lines.add(
          '    step ${step.stateId}: no figures '
          '(${step.disclosure.wireName})$onward',
        );
        continue;
      }
      lines.add(
        '    step ${step.stateId}: views ${stepCounts.views} of '
        '${stepCounts.eligibleRoots}, onward ${stepCounts.reachedAnotherStep}'
        '$onward',
      );
    }
    for (final band in version.bands) {
      final bandCounts = band.counts;
      if (bandCounts == null) {
        lines.add(
          '    ${band.point.label}: no figures '
          '(${band.disclosure.wireName})',
        );
        continue;
      }
      final dropOff = bandCounts.dropOffRate;
      lines.add(
        '    ${band.point.label}: reach ${bandCounts.reach} of '
        '${bandCounts.eligibleRoots}'
        '${dropOff == null ? '' : ', drop-off ${dropOff.decimal} '
                  '(${dropOff.numerator}/${dropOff.denominator})'}',
      );
    }
  }
  return lines.join('\n');
}

String _countsLine(SurfaceFunnelCountsV1 counts) {
  final conversion = counts.conversionRate;
  return '    views ${counts.views} of ${counts.eligibleRoots}, '
      'completions ${counts.completions}, '
      'skips ${counts.skips}, dismissals ${counts.dismissals}'
      '${conversion == null ? '' : ', conversion ${conversion.decimal} '
                '(${conversion.numerator}/${conversion.denominator})'}';
}
