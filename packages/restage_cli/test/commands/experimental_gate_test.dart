import 'package:restage_cli/src/cli.dart';
import 'package:restage_cli/src/commands/experimental_gate.dart';
import 'package:test/test.dart';

void main() {
  group('experimentalCommandsEnabled', () {
    test('is off when the variable is unset', () {
      expect(experimentalCommandsEnabled(const {}), isFalse);
    });

    test('accepts the documented truthy spellings, case-insensitively', () {
      for (final value in ['1', 'true', 'TRUE', 'yes', ' Yes ']) {
        expect(
          experimentalCommandsEnabled({experimentalOptInVariable: value}),
          isTrue,
          reason: '$value should enable experimental commands',
        );
      }
    });

    test('treats any other value as off', () {
      for (final value in ['0', 'false', 'no', '', 'maybe']) {
        expect(
          experimentalCommandsEnabled({experimentalOptInVariable: value}),
          isFalse,
          reason: '$value should not enable experimental commands',
        );
      }
    });
  });

  group('default help', () {
    test('does not list the experimental commands', () async {
      final stdout = StringBuffer();
      final cli = RestageCli(
        stdout: stdout,
        stderr: StringBuffer(),
        hasTerminal: () => false,
        environment: const {},
      );

      await cli.run(['--help']);

      expect(stdout.toString(), isNot(contains('mutation')));
      expect(stdout.toString(), isNot(contains('experiment-activation')));
      // Control: ordinary commands are listed, so the assertions above are
      // reading real help output rather than an empty buffer.
      expect(stdout.toString(), contains('surface'));
    });

    test('lists them once the session opts in', () async {
      final stdout = StringBuffer();
      final cli = RestageCli(
        stdout: stdout,
        stderr: StringBuffer(),
        hasTerminal: () => false,
        environment: const {experimentalOptInVariable: '1'},
      );

      await cli.run(['--help']);

      expect(stdout.toString(), contains('mutation'));
    });
  });

  group('invocation without the opt-in', () {
    test('refuses, names the reason, and does not exit zero', () async {
      final stderr = StringBuffer();
      final cli = RestageCli(
        stdout: StringBuffer(),
        stderr: stderr,
        hasTerminal: () => false,
        environment: const {},
      );

      final exitCode = await cli.run([
        'mutation',
        '--request',
        'unused.json',
        '--response',
        'unused-out.json',
      ]);

      expect(exitCode, isNot(0));
      expect(stderr.toString(), contains('experimental'));
      expect(stderr.toString(), contains('not served by production yet'));
      expect(stderr.toString(), contains(experimentalOptInVariable));
    });
  });
}
