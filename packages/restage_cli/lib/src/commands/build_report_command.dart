import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:restage_cli/src/libraries/build_report.dart';
import 'package:restage_cli/src/libraries/generated_part_check.dart';

/// Reports what the last local build compiled, compared with the committed
/// baseline.
final class BuildReportCommand extends Command<int> {
  BuildReportCommand({
    required StringSink stdout,
    required StringSink stderr,
    GeneratedPartAnalyzer? analyze,
  }) : _stdout = stdout,
       _stderr = stderr,
       _analyze = analyze {
    argParser
      ..addOption(
        'directory',
        abbr: 'C',
        defaultsTo: '.',
        help: 'Directory to start the restage_config.yaml search from.',
      )
      ..addFlag('json', negatable: false, help: 'Print the report as JSON.')
      ..addFlag(
        'accept',
        negatable: false,
        help: 'Record this build as the baseline in $buildReportBaselineName.',
      )
      ..addFlag(
        'check',
        negatable: false,
        help: 'Exit 1 when this build differs from the baseline.',
      );
  }

  final StringSink _stdout;
  final StringSink _stderr;
  final GeneratedPartAnalyzer? _analyze;

  @override
  String get name => 'report';

  @override
  String get description =>
      'Report what the last build delivers and what renders from the app.';

  @override
  Future<int> run() async {
    final json = argResults?['json'] as bool? ?? false;
    final accept = argResults?['accept'] as bool? ?? false;
    final check = argResults?['check'] as bool? ?? false;
    final BuildReport report;
    final List<BuildReportChange>? changes;
    final List<GeneratedPartError> broken;
    try {
      (:report, :changes, :broken) = await readBuildReport(
        Directory(argResults?['directory'] as String? ?? '.'),
        accept: accept,
        analyze: _analyze,
      );
    } on BuildReportException catch (error) {
      _stderr.writeln(error.message);
      return 1;
    }
    if (json) {
      _stdout.writeln(
        const JsonEncoder.withIndent('  ').convert(
          buildReportJson((report: report, changes: changes, broken: broken)),
        ),
      );
    } else {
      for (final part in broken) {
        _stdout.writeln(generatedPartErrorSentence(part));
      }
      report.lines.forEach(_stdout.writeln);
      _stdout.writeln(switch (changes) {
        _ when accept => buildReportAcceptedSentence,
        null => buildReportNoBaselineSentence,
        [] => buildReportUnchangedSentence,
        final changes => [
          buildReportChangesHeading,
          for (final change in changes) '  ${change.sentence}',
        ].join('\n'),
      });
    }
    if (check && broken.isNotEmpty) return 1;
    if (!check || accept) return 0;
    if (changes == null || changes.isNotEmpty) {
      _stderr.writeln(
        changes == null
            ? buildReportNoBaselineSentence
            : buildReportCheckSentence,
      );
      return 1;
    }
    return 0;
  }
}
