import 'package:args/args.dart';
import 'package:restage_cli/src/commands/lifecycle_support.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  // ---------------------------------------------------------------------------
  // confirmDestructive
  // ---------------------------------------------------------------------------
  group('confirmDestructive', () {
    test('rejects --yes on production', () async {
      final err = StringBuffer();
      final proceed = await confirmDestructive(
        interactive: const NonInteractive(),
        stdout: StringBuffer(),
        stderr: err,
        environment: 'production',
        yesFlag: true,
        impactLine: 'kill pro (v7)',
      );
      expect(proceed, isFalse);
      expect(err.toString(), contains('production'));
    });

    test('proceeds on --yes for a non-prod env', () async {
      final proceed = await confirmDestructive(
        interactive: const NonInteractive(),
        stdout: StringBuffer(),
        stderr: StringBuffer(),
        environment: 'staging',
        yesFlag: true,
        impactLine: 'kill pro (v7)',
      );
      expect(proceed, isTrue);
    });

    test('fails closed when prod + non-interactive + no yes', () async {
      final err = StringBuffer();
      final proceed = await confirmDestructive(
        interactive: const NonInteractive(),
        stdout: StringBuffer(),
        stderr: err,
        environment: 'production',
        yesFlag: false,
        impactLine: 'kill pro (v7)',
      );
      expect(proceed, isFalse);
      expect(err.toString(), contains('destructive'));
    });

    test(
      'prints impact line and uses confirm result for interactive prod',
      () async {
        final out = StringBuffer();
        // Simulate an interactive surface that always answers "no".
        final interactive = _FakeInteractive(confirmAnswer: false);
        final proceed = await confirmDestructive(
          interactive: interactive,
          stdout: out,
          stderr: StringBuffer(),
          environment: 'production',
          yesFlag: false,
          impactLine: 'kill my-surface (v42)',
        );
        expect(proceed, isFalse);
        expect(out.toString(), contains('kill my-surface (v42)'));
      },
    );

    test('proceeds when interactive prod user confirms yes', () async {
      final interactive = _FakeInteractive(confirmAnswer: true);
      final proceed = await confirmDestructive(
        interactive: interactive,
        stdout: StringBuffer(),
        stderr: StringBuffer(),
        environment: 'production',
        yesFlag: false,
        impactLine: 'kill my-surface (v42)',
      );
      expect(proceed, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // requireReason
  // ---------------------------------------------------------------------------
  group('requireReason', () {
    test('returns the flag value when provided', () async {
      final args = _parseWith({'reason': 'rolling back bad layout'});
      final result = await requireReason(
        argResults: args,
        interactive: const NonInteractive(),
        stderr: StringBuffer(),
      );
      expect(result, 'rolling back bad layout');
    });

    test('trims whitespace from the flag value', () async {
      final args = _parseWith({'reason': '  fix   '});
      final result = await requireReason(
        argResults: args,
        interactive: const NonInteractive(),
        stderr: StringBuffer(),
      );
      expect(result, 'fix');
    });

    test(
      'returns null and prints error when flag is absent non-interactive',
      () async {
        final args = _parseWith({});
        final err = StringBuffer();
        final result = await requireReason(
          argResults: args,
          interactive: const NonInteractive(),
          stderr: err,
        );
        expect(result, isNull);
        expect(err.toString(), contains('--reason'));
      },
    );

    test(
      'prompts when interactive and flag is absent, returns entered value',
      () async {
        final args = _parseWith({});
        final interactive = _FakeInteractive(promptAnswer: 'user typed reason');
        final result = await requireReason(
          argResults: args,
          interactive: interactive,
          stderr: StringBuffer(),
        );
        expect(result, 'user typed reason');
      },
    );

    test(
      'returns null after interactive prompt when user enters empty string',
      () async {
        final args = _parseWith({});
        final err = StringBuffer();
        final interactive = _FakeInteractive(promptAnswer: '');
        final result = await requireReason(
          argResults: args,
          interactive: interactive,
          stderr: err,
        );
        expect(result, isNull);
        expect(err.toString(), contains('--reason'));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // resolveSingleSlug
  // ---------------------------------------------------------------------------
  group('resolveSingleSlug', () {
    test('returns the single positional argument', () {
      final args = _parseWith({}, rest: ['my-surface']);
      final slug = resolveSingleSlug(argResults: args, stderr: StringBuffer());
      expect(slug, 'my-surface');
    });

    test('returns null and prints error when no positional arguments', () {
      final err = StringBuffer();
      final args = _parseWith({});
      final slug = resolveSingleSlug(argResults: args, stderr: err);
      expect(slug, isNull);
      expect(err.toString(), contains('<slug>'));
    });

    test(
      'returns null and prints error when more than one positional argument',
      () {
        final err = StringBuffer();
        final args = _parseWith({}, rest: ['a', 'b']);
        final slug = resolveSingleSlug(argResults: args, stderr: err);
        expect(slug, isNull);
        expect(err.toString(), isNotEmpty);
      },
    );

    test('returns null when argResults is null', () {
      final err = StringBuffer();
      final slug = resolveSingleSlug(argResults: null, stderr: err);
      expect(slug, isNull);
      expect(err.toString(), contains('<slug>'));
    });
  });

  // ---------------------------------------------------------------------------
  // resolveSurfaceTypeArg
  // ---------------------------------------------------------------------------
  group('resolveSurfaceTypeArg', () {
    test('returns fixedType immediately when set', () {
      final result = resolveSurfaceTypeArg(
        argResults: null,
        fixedType: SurfaceType.paywall,
        stderr: StringBuffer(),
      );
      expect(result, SurfaceType.paywall);
    });

    test('parses a valid --type flag', () {
      final args = _parseWith({'type': 'onboarding'});
      final result = resolveSurfaceTypeArg(
        argResults: args,
        fixedType: null,
        stderr: StringBuffer(),
      );
      expect(result, SurfaceType.onboarding);
    });

    test('returns null and prints error for missing --type', () {
      final err = StringBuffer();
      final result = resolveSurfaceTypeArg(
        argResults: _parseWith({}),
        fixedType: null,
        stderr: err,
      );
      expect(result, isNull);
      expect(err.toString(), contains('--type'));
    });

    test('returns null and prints error for invalid --type value', () {
      final err = StringBuffer();
      final args = _parseWith({'type': 'notatype'});
      final result = resolveSurfaceTypeArg(
        argResults: args,
        fixedType: null,
        stderr: err,
      );
      expect(result, isNull);
      expect(err.toString(), contains('notatype'));
    });

    test('accepts all four lifecycle surface types', () {
      for (final t in [
        SurfaceType.onboarding,
        SurfaceType.message,
        SurfaceType.survey,
        SurfaceType.paywall,
      ]) {
        final args = _parseWith({'type': t.wireName});
        final result = resolveSurfaceTypeArg(
          argResults: args,
          fixedType: null,
          stderr: StringBuffer(),
        );
        expect(result, t, reason: 'Expected ${t.wireName} to be accepted');
      }
    });
  });
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Build a real [ArgResults] from flag key/value pairs and optional
/// positional args, so tests exercise the same accessors the production code
/// uses rather than a hand-rolled fake.
ArgResults _parseWith(
  Map<String, String> flags, {
  List<String> rest = const <String>[],
}) {
  final parser = ArgParser()
    ..addOption('reason')
    ..addOption('type')
    ..addOption('env')
    ..addOption('project')
    ..addOption('app')
    ..addOption('directory', defaultsTo: '.');
  final args = <String>[];
  for (final entry in flags.entries) {
    args
      ..add('--${entry.key}')
      ..add(entry.value);
  }
  args.addAll(rest);
  return parser.parse(args);
}

/// Scripted [Interactive] for unit tests.
class _FakeInteractive implements Interactive {
  _FakeInteractive({String? promptAnswer, bool confirmAnswer = false})
    : _promptAnswer = promptAnswer,
      _confirmAnswer = confirmAnswer;

  final String? _promptAnswer;
  final bool _confirmAnswer;

  @override
  bool get isInteractive => true;

  @override
  Future<String> prompt(String question, {String? defaultValue}) async =>
      _promptAnswer ?? defaultValue ?? '';

  @override
  Future<bool> confirm(String question, {bool defaultYes = false}) async =>
      _confirmAnswer;

  @override
  Future<T> select<T>(
    String question,
    List<({String label, T value})> options, {
    T? defaultValue,
  }) async {
    if (defaultValue != null) return defaultValue;
    return options.first.value;
  }

  @override
  Future<String> secret(String question) async => '';

  @override
  Spinner spinner(String message) => throw UnimplementedError();
}
