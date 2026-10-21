import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:restage_cli/src/libraries/library_contract_binding.dart';
import 'package:restage_shared/restage_shared.dart'
    show libraryContractDraftDirectory;

/// Parent of the custom widget library subcommands.
class LibraryCommand extends Command<int> {
  /// Construct a library command group.
  LibraryCommand({required StringSink stdout, required StringSink stderr}) {
    addSubcommand(LibraryRecordCommand(stdout: stdout, stderr: stderr));
  }

  @override
  String get name => 'library';

  @override
  String get description => 'Manage the contracts of your widget libraries.';
}

/// Records the contracts the last build drafted in this package.
class LibraryRecordCommand extends Command<int> {
  /// Construct a library record command.
  LibraryRecordCommand({required StringSink stdout, required StringSink stderr})
    : _stdout = stdout,
      _stderr = stderr {
    argParser
      ..addOption(
        'directory',
        abbr: 'C',
        defaultsTo: '.',
        help: 'The package directory.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Emit JSON instead of the default text output.',
      );
  }

  final StringSink _stdout;
  final StringSink _stderr;

  @override
  String get name => 'record';

  @override
  String get description =>
      "Record this package's widget library contracts from its last build. "
      'Run it before publishing a package; an app records them when it '
      'pushes.';

  @override
  Future<int> run() async {
    final root = libraryPackageRoot(
      Directory(argResults!['directory'] as String),
    );
    final LibraryRecordResult result;
    try {
      result = recordLibraryDrafts(root);
    } on FormatException catch (error) {
      _stderr.writeln(error.message);
      return 1;
    } on IOException catch (error) {
      _stderr.writeln('The library contracts could not be recorded: $error');
      return 1;
    }
    if (argResults!['json'] as bool) {
      _stdout.writeln(jsonEncode(libraryRecordJson(result)));
      return result.isEmpty ? 1 : 0;
    }
    if (result.isEmpty) {
      _stderr.writeln(
        'No library contracts in $libraryContractDraftDirectory. Run '
        '`dart run build_runner build` in the package first.',
      );
      return 1;
    }
    for (final contract in result.recorded) {
      _stdout.writeln(libraryRecordedLine(contract));
    }
    for (final (namespace, version) in result.alreadyRecorded) {
      _stdout.writeln('Library $namespace v$version is already recorded.');
    }
    return 0;
  }
}
