import 'package:nocterm/nocterm.dart' as nocterm;
import 'package:restage_cli/src/tui/console_app.dart';
import 'package:restage_cli/src/tui/console_controller.dart';

typedef ConsoleLauncher = Future<int> Function(ConsoleController controller);
typedef NoctermAppRunner =
    Future<void> Function(
      nocterm.Component app, {
      bool enableHotReload,
      nocterm.TerminalBackend? backend,
    });

Future<int> runRestageConsole(ConsoleController controller) =>
    runRestageConsoleWithRunner(controller, runApp: nocterm.runApp);

Future<int> runRestageConsoleWithRunner(
  ConsoleController controller, {
  required NoctermAppRunner runApp,
}) async {
  await runApp(
    RestageConsoleApp(controller: controller),
    enableHotReload: false,
  );
  return controller.exitCode;
}
