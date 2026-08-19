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

    test('top-level help makes surface the manifest-driven path', () async {
      final stdout = StringBuffer();
      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: StringBuffer(),
      ).run(const ['--help']);

      expect(exitCode, 0);
      expect(
        stdout.toString(),
        contains('Manifest-driven publication and lifecycle'),
      );
      expect(
        stdout.toString(),
        contains('Compatibility commands for specialized paywalls'),
      );
    });

    test(
      'surface publication help marks compatibility selectors clearly',
      () async {
        final stdout = StringBuffer();
        final exitCode = await RestageCli(
          stdout: stdout,
          stderr: StringBuffer(),
        ).run(const ['surface', 'publish', '--help']);

        expect(exitCode, 0);
        expect(
          stdout.toString(),
          contains('Deprecated validation/disambiguation selector only'),
        );
        expect(
          stdout.toString(),
          contains('generated manifest is authoritative'),
        );
        expect(stdout.toString(), isNot(contains('--path')));
      },
    );

    test('lifecycle help defaults to generated identity', () async {
      final stdout = StringBuffer();
      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: StringBuffer(),
      ).run(const ['surface', 'status', '--help']);

      expect(exitCode, 0);
      expect(
        stdout.toString(),
        contains('Deprecated validation/disambiguation selector only'),
      );
      expect(
        stdout.toString(),
        contains('generated manifest, which is authoritative'),
      );
    });

    test('init help identifies the canonical starter annotation', () async {
      final stdout = StringBuffer();
      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: StringBuffer(),
      ).run(const ['init', '--help']);

      expect(exitCode, 0);
      expect(stdout.toString(), contains('canonical `@Paywall` starter'));
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

    test('no arguments in a TTY launches the console', () async {
      var launched = false;
      final exitCode = await RestageCli(
        stdout: StringBuffer(),
        stderr: StringBuffer(),
        hasTerminal: () => true,
        consoleLauncher: (_) async {
          launched = true;
          return 0;
        },
      ).run(const <String>[]);

      expect(exitCode, 0);
      expect(launched, isTrue);
    });

    test(
      'no arguments outside a TTY prints usage and does not launch console',
      () async {
        var launched = false;
        final stdout = StringBuffer();
        final exitCode = await RestageCli(
          stdout: stdout,
          stderr: StringBuffer(),
          hasTerminal: () => false,
          consoleLauncher: (_) async {
            launched = true;
            return 0;
          },
        ).run(const <String>[]);

        expect(exitCode, 0);
        expect(launched, isFalse);
        expect(stdout.toString(), contains('Usage:'));
      },
    );

    test('--help does not launch the console even in a TTY', () async {
      var launched = false;
      final stdout = StringBuffer();
      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: StringBuffer(),
        hasTerminal: () => true,
        consoleLauncher: (_) async {
          launched = true;
          return 0;
        },
      ).run(const ['--help']);

      expect(exitCode, 0);
      expect(launched, isFalse);
      expect(stdout.toString(), contains('Usage:'));
    });

    test(
      '--non-interactive with no command does not launch the console',
      () async {
        var launched = false;
        final stdout = StringBuffer();
        final exitCode = await RestageCli(
          stdout: stdout,
          stderr: StringBuffer(),
          hasTerminal: () => true,
          consoleLauncher: (_) async {
            launched = true;
            return 0;
          },
        ).run(const ['--non-interactive']);

        expect(exitCode, 0);
        expect(launched, isFalse);
        expect(stdout.toString(), contains('Usage:'));
      },
    );

    test('unknown command does not launch the console even in a TTY', () async {
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
      ).run(const ['not-a-command']);

      expect(exitCode, 1);
      expect(launched, isFalse);
      expect(stderr.toString(), contains('not-a-command'));
    });
  });
}
