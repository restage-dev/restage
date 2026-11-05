import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:restage_cli/src/config/restage_config.dart'
    show loadRestageConfig;
import 'package:restage_cli/src/libraries/build_report.dart';
import 'package:restage_cli/src/libraries/island_promotion.dart';

/// Commands on the app's own widgets.
final class WidgetCommand extends Command<int> {
  WidgetCommand({required StringSink stdout, required StringSink stderr}) {
    addSubcommand(PromoteCommand(stdout: stdout, stderr: stderr));
  }

  @override
  String get name => 'widget';

  @override
  String get description => "Work with the app's own widgets.";
}

/// Moves a part of a screen that renders from the app into a widget class of
/// the app's own.
final class PromoteCommand extends Command<int> {
  PromoteCommand({required StringSink stdout, required StringSink stderr})
    : _stdout = stdout,
      _stderr = stderr {
    argParser
      ..addOption(
        'directory',
        abbr: 'C',
        defaultsTo: '.',
        help: 'Directory to start the restage_config.yaml search from.',
      )
      ..addOption('name', help: 'The new widget class name.')
      ..addOption(
        'library',
        help:
            'The widget library to export it from, when the package has '
            'several.',
      );
  }

  final StringSink _stdout;
  final StringSink _stderr;

  @override
  String get name => 'promote';

  @override
  String get invocation => 'restage $promoteCommandName <file>:<line>';

  @override
  String get description =>
      "Move a widget that renders from the app into a widget class of the "
      "app's own, as `restage build report` lists it.";

  @override
  Future<int> run() async {
    final rest = argResults?.rest ?? const <String>[];
    if (rest.length != 1) {
      usageException('Name one place, as <file>:<line>.');
    }
    final directory = Directory(argResults?['directory'] as String? ?? '.');
    final loaded = await loadRestageConfig(from: directory);
    final root = loaded?.source.parent ?? directory.absolute;
    try {
      final result = promoteIsland(
        root,
        BuildReport.read(root),
        rest.single,
        name: argResults?['name'] as String?,
        library: argResults?['library'] as String?,
      );
      _stdout.writeln(promotedSentence(result));
      return 0;
    } on BuildReportException catch (error) {
      _stderr.writeln(error.message);
      return 1;
    }
  }
}
