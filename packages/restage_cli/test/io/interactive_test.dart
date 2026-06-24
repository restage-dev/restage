import 'dart:async';

import 'package:restage_cli/src/io/interactive.dart';
import 'package:test/test.dart';

/// Drives a [RealInteractive] from a scripted list of input lines so the
/// tests can assert behaviour without touching a real TTY.
class _ScriptedStdin {
  _ScriptedStdin(List<String> lines) : _lines = List<String>.from(lines);

  final List<String> _lines;

  Future<String?> nextLine() async {
    if (_lines.isEmpty) return null;
    return _lines.removeAt(0);
  }
}

void main() {
  group('RealInteractive.prompt', () {
    test('returns the typed value', () async {
      final stdin = _ScriptedStdin(['hello']);
      final stdout = StringBuffer();
      final interactive = RealInteractive(
        readLine: stdin.nextLine,
        stdout: stdout,
        isInteractiveOverride: true,
      );

      final answer = await interactive.prompt('What is your name?');

      expect(answer, 'hello');
      expect(stdout.toString(), contains('What is your name?'));
    });

    test('returns the default when the user presses enter', () async {
      final stdin = _ScriptedStdin(['']);
      final stdout = StringBuffer();
      final interactive = RealInteractive(
        readLine: stdin.nextLine,
        stdout: stdout,
        isInteractiveOverride: true,
      );

      final answer = await interactive.prompt(
        'Project slug?',
        defaultValue: 'my-project',
      );

      expect(answer, 'my-project');
      expect(stdout.toString(), contains('[my-project]'));
    });

    test('re-prompts when input is empty and no default is set', () async {
      final stdin = _ScriptedStdin(['', '', 'finally']);
      final stdout = StringBuffer();
      final interactive = RealInteractive(
        readLine: stdin.nextLine,
        stdout: stdout,
        isInteractiveOverride: true,
      );

      final answer = await interactive.prompt('Required');

      expect(answer, 'finally');
    });
  });

  group('RealInteractive.confirm', () {
    test('accepts y/Y as yes', () async {
      final stdin = _ScriptedStdin(['y']);
      final stdout = StringBuffer();
      final interactive = RealInteractive(
        readLine: stdin.nextLine,
        stdout: stdout,
        isInteractiveOverride: true,
      );

      expect(await interactive.confirm('Apply?'), isTrue);
    });

    test('accepts n/N as no', () async {
      final stdin = _ScriptedStdin(['NO']);
      final stdout = StringBuffer();
      final interactive = RealInteractive(
        readLine: stdin.nextLine,
        stdout: stdout,
        isInteractiveOverride: true,
      );

      expect(await interactive.confirm('Apply?'), isFalse);
    });

    test('honours the defaultYes on empty input', () async {
      final stdin = _ScriptedStdin(['', '']);
      final stdout = StringBuffer();
      final interactive = RealInteractive(
        readLine: stdin.nextLine,
        stdout: stdout,
        isInteractiveOverride: true,
      );

      expect(await interactive.confirm('A?', defaultYes: true), isTrue);
      expect(await interactive.confirm('B?', defaultYes: false), isFalse);
    });

    test('re-prompts on unrecognised input', () async {
      final stdin = _ScriptedStdin(['maybe', 'y']);
      final stdout = StringBuffer();
      final interactive = RealInteractive(
        readLine: stdin.nextLine,
        stdout: stdout,
        isInteractiveOverride: true,
      );

      expect(await interactive.confirm('Q?'), isTrue);
      expect(stdout.toString(), contains('Q?'));
    });
  });

  group('RealInteractive.select', () {
    test('returns the value at the chosen index', () async {
      final stdin = _ScriptedStdin(['2']);
      final stdout = StringBuffer();
      final interactive = RealInteractive(
        readLine: stdin.nextLine,
        stdout: stdout,
        isInteractiveOverride: true,
      );

      final pick = await interactive.select<String>('Pick a colour', const [
        (label: 'Red', value: 'r'),
        (label: 'Green', value: 'g'),
        (label: 'Blue', value: 'b'),
      ]);

      expect(pick, 'g');
      final out = stdout.toString();
      expect(out, contains('1) Red'));
      expect(out, contains('2) Green'));
      expect(out, contains('3) Blue'));
    });

    test('returns the defaultValue on empty input', () async {
      final stdin = _ScriptedStdin(['']);
      final stdout = StringBuffer();
      final interactive = RealInteractive(
        readLine: stdin.nextLine,
        stdout: stdout,
        isInteractiveOverride: true,
      );

      final pick = await interactive.select<String>('Pick', const [
        (label: 'A', value: 'a'),
        (label: 'B', value: 'b'),
      ], defaultValue: 'b');

      expect(pick, 'b');
    });

    test('re-prompts on out-of-range input', () async {
      final stdin = _ScriptedStdin(['9', '1']);
      final stdout = StringBuffer();
      final interactive = RealInteractive(
        readLine: stdin.nextLine,
        stdout: stdout,
        isInteractiveOverride: true,
      );

      final pick = await interactive.select<String>('Pick', const [
        (label: 'Only', value: 'only'),
      ]);

      expect(pick, 'only');
    });
  });

  group('RealInteractive.secret', () {
    test('reads a value from stdin', () async {
      final stdin = _ScriptedStdin(['s3cret']);
      final stdout = StringBuffer();
      final interactive = RealInteractive(
        readLine: stdin.nextLine,
        stdout: stdout,
        isInteractiveOverride: true,
      );

      final value = await interactive.secret('Token:');

      expect(value, 's3cret');
    });
  });

  group('Spinner', () {
    test(
      'non-TTY mode prints the message once and the final on stop',
      () async {
        final stdout = StringBuffer();
        final interactive = RealInteractive(
          readLine: () async => null,
          stdout: stdout,
          isInteractiveOverride: false,
        );

        final spinner = interactive.spinner('Working');
        spinner.start();
        spinner.update('Working (12s)');
        spinner.stop(finalMessage: 'Done.');

        final out = stdout.toString();
        expect(out, contains('Working'));
        expect(out, contains('Done.'));
      },
    );

    test('TTY mode emits at least one carriage-return frame', () async {
      final stdout = StringBuffer();
      final interactive = RealInteractive(
        readLine: () async => null,
        stdout: stdout,
        isInteractiveOverride: true,
        // Drive the frame timer manually so the test is deterministic.
        spinnerFrameInterval: Duration.zero,
      );

      final spinner = interactive.spinner('Loading');
      spinner.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      spinner.stop(finalMessage: 'OK');

      final out = stdout.toString();
      // A spinner frame ends with `\r` (so the next frame overwrites it).
      expect(out, contains('\r'));
      expect(out, contains('OK'));
    });
  });

  group('NonInteractive', () {
    test('prompt returns the supplied default', () async {
      const interactive = NonInteractive();
      expect(await interactive.prompt('q', defaultValue: 'x'), 'x');
    });

    test('prompt throws when no default is supplied', () async {
      const interactive = NonInteractive();
      expect(
        () => interactive.prompt('q'),
        throwsA(isA<NonInteractiveDefaultMissing>()),
      );
    });

    test('confirm returns the defaultYes', () async {
      const interactive = NonInteractive();
      expect(await interactive.confirm('q'), isFalse);
      expect(await interactive.confirm('q', defaultYes: true), isTrue);
    });

    test('select throws when no default value is supplied', () async {
      const interactive = NonInteractive();
      expect(
        () => interactive.select<String>('q', const [(label: 'A', value: 'a')]),
        throwsA(isA<NonInteractiveDefaultMissing>()),
      );
    });

    test('spinner is a no-op that prints the final message on stop', () {
      final stdout = StringBuffer();
      final interactive = NonInteractive(stdout: stdout);
      final spinner = interactive.spinner('Work')
        ..start()
        ..update('Update')
        ..stop(finalMessage: 'Done');
      // Suppress the unused-local warning in tests; the spinner is the
      // value under test.
      expect(spinner, isNotNull);
      expect(stdout.toString(), contains('Done'));
    });
  });

  group('isInteractive', () {
    test('RealInteractive honours the override', () {
      expect(
        RealInteractive(
          readLine: () async => null,
          stdout: StringBuffer(),
          isInteractiveOverride: true,
        ).isInteractive,
        isTrue,
      );
      expect(
        RealInteractive(
          readLine: () async => null,
          stdout: StringBuffer(),
          isInteractiveOverride: false,
        ).isInteractive,
        isFalse,
      );
    });

    test('NonInteractive is always non-interactive', () {
      expect(const NonInteractive().isInteractive, isFalse);
    });
  });
}
