import 'package:args/command_runner.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_cli/src/tui/console_controller.dart';
import 'package:restage_cli/src/tui/restage_tui.dart';

class ConsoleCommand extends Command<int> {
  ConsoleCommand({
    required ConsoleController Function() controllerFactory,
    required ConsoleLauncher launcher,
    required Interactive interactive,
  }) : _controllerFactory = controllerFactory,
       _launcher = launcher,
       _interactive = interactive;

  final ConsoleController Function() _controllerFactory;
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
    return _launcher(_controllerFactory());
  }
}
