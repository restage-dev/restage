import 'package:restage_cli/src/cli.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:test/test.dart';

void main() {
  test('restage console invokes the injected console launcher', () async {
    var launched = false;
    final stdout = StringBuffer();
    final exitCode = await RestageCli(
      stdout: stdout,
      stderr: StringBuffer(),
      hasTerminal: () => false,
      interactiveFactory: (_) => RealInteractive(
        readLine: () async => null,
        stdout: stdout,
        isInteractiveOverride: true,
      ),
      consoleLauncher: (_) async {
        launched = true;
        return 0;
      },
    ).run(const ['console']);

    expect(exitCode, 0);
    expect(launched, isTrue);
  });

  test('--non-interactive console fails before launching the TUI', () async {
    var launched = false;
    final stderr = StringBuffer();
    final exitCode = await RestageCli(
      stdout: StringBuffer(),
      stderr: stderr,
      hasTerminal: () => true,
      consoleLauncher: (_) async {
        launched = true;
        return 0;
      },
    ).run(const ['--non-interactive', 'console']);

    expect(exitCode, 1);
    expect(launched, isFalse);
    expect(stderr.toString(), contains('console requires an interactive'));
  });
}
