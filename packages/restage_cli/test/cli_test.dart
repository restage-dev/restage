import 'package:args/args.dart';
import 'package:restage_cli/src/cli.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:test/test.dart';

void main() {
  group('RestageCli.run', () {
    test('--non-interactive resolves to a NonInteractive surface', () async {
      Interactive? captured;
      final stdout = StringBuffer();
      final stderr = StringBuffer();
      await RestageCli(
        stdout: stdout,
        stderr: stderr,
        interactiveFactory: (ArgResults globalResults) {
          final nonInteractive =
              (globalResults['non-interactive'] as bool? ?? false) ||
              (globalResults['yes'] as bool? ?? false);
          captured = nonInteractive
              ? const NonInteractive()
              : RealInteractive(
                  readLine: () async => null,
                  stdout: stdout,
                  isInteractiveOverride: false,
                );
          return captured!;
        },
      ).run(const ['--non-interactive', '--help']);
      expect(captured, isA<NonInteractive>());
    });

    test('--yes is an alias for --non-interactive', () async {
      Interactive? captured;
      final stdout = StringBuffer();
      final stderr = StringBuffer();
      await RestageCli(
        stdout: stdout,
        stderr: stderr,
        interactiveFactory: (ArgResults globalResults) {
          final nonInteractive =
              (globalResults['non-interactive'] as bool? ?? false) ||
              (globalResults['yes'] as bool? ?? false);
          captured = nonInteractive
              ? const NonInteractive()
              : RealInteractive(
                  readLine: () async => null,
                  stdout: stdout,
                  isInteractiveOverride: false,
                );
          return captured!;
        },
      ).run(const ['--yes', '--help']);
      expect(captured, isA<NonInteractive>());
    });

    test('default mode (no flag) resolves to RealInteractive', () async {
      Interactive? captured;
      final stdout = StringBuffer();
      final stderr = StringBuffer();
      await RestageCli(
        stdout: stdout,
        stderr: stderr,
        interactiveFactory: (ArgResults globalResults) {
          final nonInteractive =
              (globalResults['non-interactive'] as bool? ?? false) ||
              (globalResults['yes'] as bool? ?? false);
          captured = nonInteractive
              ? const NonInteractive()
              : RealInteractive(
                  readLine: () async => null,
                  stdout: stdout,
                  isInteractiveOverride: false,
                );
          return captured!;
        },
      ).run(const ['--help']);
      expect(captured, isA<RealInteractive>());
    });
  });

  group('RestageCli.run', () {
    test('--help exits 0 and prints a banner naming the binary', () async {
      final stdout = StringBuffer();
      final stderr = StringBuffer();
      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
      ).run(const ['--help']);
      expect(exitCode, 0);
      expect(stdout.toString(), contains('restage'));
      expect(stdout.toString(), contains('Usage:'));
    });

    test('unknown command exits 1 with the command name in stderr', () async {
      final stdout = StringBuffer();
      final stderr = StringBuffer();
      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
      ).run(const ['totally-not-a-command']);
      expect(exitCode, 1);
      expect(stderr.toString(), contains('totally-not-a-command'));
    });

    test('no arguments exits 0 and prints the top-level usage', () async {
      final stdout = StringBuffer();
      final stderr = StringBuffer();
      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
      ).run(const <String>[]);
      expect(exitCode, 0);
      expect(stdout.toString(), contains('Usage:'));
    });
  });
}
