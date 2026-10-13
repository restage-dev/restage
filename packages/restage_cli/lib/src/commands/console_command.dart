import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_cli/src/tui/console_controller.dart';
import 'package:restage_cli/src/tui/restage_tui.dart';

class ConsoleCommand extends Command<int> {
  ConsoleCommand({
    required ConsoleController Function(Directory? directory) controllerFactory,
    required ConsoleLauncher launcher,
    required Interactive interactive,
  }) : _controllerFactory = controllerFactory,
       _launcher = launcher,
       _interactive = interactive {
    argParser.addOption(
      'directory',
      abbr: 'C',
      help: 'Directory to start the restage_config.yaml search from.',
    );
  }

  final ConsoleController Function(Directory? directory) _controllerFactory;
  final ConsoleLauncher _launcher;
  final Interactive _interactive;

  @override
  String get name => 'console';

  @override
  String get description => 'Open the full-screen Restage console.';

  @override
  Future<int> run() async {
    if (!_interactive.isInteractive) {
      usageException('console requires an interactive terminal');
    }
    final directory = argResults?['directory'] as String?;
    return _launcher(
      _controllerFactory(directory == null ? null : Directory(directory)),
    );
  }
}
