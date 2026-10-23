import 'dart:async';
import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/surface_funnel_api.dart';
import 'package:restage_cli/src/commands/authed.dart';
import 'package:restage_cli/src/commands/lifecycle_support.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_cli/src/operations/operation.dart';
import 'package:restage_cli/src/output/held_count.dart';
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
  }) : _io = CommandIo(
         stdout: stdout,
         stderr: stderr,
         interactive: interactive,
         credentialStore: credentialStore,
         httpClient: httpClient,
       ),
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
            '--until. The read starts at that UTC day.',
      )
      ..addOption(
        'until',
        help:
            'End of the window, exclusive, as an ISO-8601 instant. '
            'Defaults to now. The read runs to the end of that UTC day.',
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

  final CommandIo _io;
  final DateTime Function() _now;

  @override
  String get name => 'results';

  @override
  String get description =>
      "Read one surface's funnel: views, steps, drop-off and completions per "
      'published version.';

  @override
  String get invocation => 'restage surface results <surface>';

  @override
  Future<int> run() async {
    final rest = argResults?.rest ?? const <String>[];
    if (rest.length != 1) {
      _io.stderr.writeln(
        'Name exactly one surface, by slug or measurement id.',
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
      _io.stderr.writeln(error.message);
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
      _io.stderr.writeln(error.message);
      return 1;
    }

    return runAuthed(_io, argResults, OperationScope.target, (ctx) async {
      final context = ctx.target!;
      try {
        final view = await SurfaceFunnelApi(ctx.api).read(
          target: TargetCoordinate(
            organizationId: OrganizationId(context.organizationId),
            appId: ApplicationId(context.appId),
            environmentTargetId: EnvironmentTargetId(
              context.environmentTargetId,
            ),
            namedEnvironmentId: NamedEnvironmentId(context.namedEnvironmentId),
            runtimePlane: switch (context.runtimePlane) {
              RuntimePlane.live => measurement.RuntimePlane.live,
              RuntimePlane.sandbox => measurement.RuntimePlane.sandbox,
            },
          ),
          selection: selection,
        );
        _io.stdout.writeln(
          asJson ? jsonEncode(view.toJson()) : renderSurfaceFunnel(view),
        );
        return 0;
      } on SurfaceFunnelMismatchException catch (error) {
        _io.stderr.writeln(error);
        return 2;
      } on CanonicalFormatException {
        _io.stderr.writeln('The service returned an invalid funnel reading.');
        return 2;
      }
    });
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
    '  read ${_utcDay(view.windowStartMicros)} through '
        '${_utcDay(view.windowEndExclusiveMicros - 1)} UTC',
  ];
  if (view.versions.isEmpty) {
    lines.add('  No version of this surface was served in this window.');
  }
  for (final version in view.versions) {
    lines.add(
      '  v${version.revisionOrdinal} ${version.surfaceRevisionId} '
      '[${version.status.wireName}]',
    );
    final counts = version.counts;
    if (counts == null) {
      lines.add('    views $heldCountText');
      continue;
    }
    lines.add(_countsLine(counts));
    for (final step in version.steps) {
      final stepCounts = step.counts;
      final onward = step.transitionTargets.isEmpty
          ? ''
          : ' -> ${step.transitionTargets.join(', ')}';
      if (stepCounts == null) {
        lines.add('    step ${step.stateId}: views $heldCountText$onward');
        continue;
      }
      lines.add(
        '    step ${step.stateId}: views ${countText(stepCounts.views)} of '
        '${countText(stepCounts.eligibleRoots)}, onward '
        '${countText(stepCounts.reachedAnotherStep)}$onward',
      );
    }
    for (final band in version.bands) {
      final bandCounts = band.counts;
      if (bandCounts == null) {
        lines.add('    ${band.point.label}: reach $heldCountText');
        continue;
      }
      final dropOff = bandCounts.dropOffRate;
      lines.add(
        '    ${band.point.label}: reach ${countText(bandCounts.reach)} of '
        '${countText(bandCounts.eligibleRoots)}'
        '${dropOff == null ? '' : ', drop-off ${dropOff.decimal} '
                  '(${dropOff.numerator}/${dropOff.denominator})'}',
      );
    }
  }
  return lines.join('\n');
}

String _countsLine(SurfaceFunnelCountsV1 counts) {
  final conversion = counts.conversionRate;
  return '    views ${countText(counts.views)} of '
      '${countText(counts.eligibleRoots)}, '
      'completions ${countText(counts.completions)}, '
      'skips ${countText(counts.skips)}, '
      'dismissals ${countText(counts.dismissals)}'
      '${conversion == null ? '' : ', conversion ${conversion.decimal} '
                '(${conversion.numerator}/${conversion.denominator})'}';
}

/// The UTC calendar day [micros] falls on, as YYYY-MM-DD.
String _utcDay(int micros) => DateTime.fromMicrosecondsSinceEpoch(
  micros,
  isUtc: true,
).toIso8601String().substring(0, 10);
