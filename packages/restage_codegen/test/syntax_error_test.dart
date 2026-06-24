import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/builder.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// The builder resolves paywall sources with `allowSyntaxErrors: true` so the
/// build does not crash with an opaque exception on a malformed input. That
/// tolerance let a malformed token whose parser-recovery happens to yield a
/// structurally-valid widget tree ship a clean blob with the bad token
/// silently dropped — e.g. an incomplete hex literal `0x` recovering to `0`,
/// or an unterminated string recovering to a closed one. These exercises lock
/// in that a genuine syntactic error now fails the build with an actionable
/// diagnostic instead of shipping a degraded blob.
Future<TestBuilderResult> _build(
  String body, {
  required List<String> logs,
}) async {
  final source = '''
    $kStubAnnotationsAndBases

    @PaywallSource(id: 'syntax_probe')
    class SyntaxProbePaywall extends StatelessWidget {
      const SyntaxProbePaywall();
      Widget build(BuildContext context) => $body;
    }
  ''';
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
    includeFlutter: false,
  );
  readerWriter.testing.writeString(
    AssetId('apps_examples', 'lib/paywalls/syntax_probe.dart'),
    source,
  );
  return testBuilder(
    restageCodegenBuilder(BuilderOptions.empty),
    {'apps_examples|lib/paywalls/syntax_probe.dart': source},
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    onLog: (record) => logs.add(record.message),
  );
}

void main() {
  group('syntactic-error detection', () {
    test(
        'an incomplete hex literal fails the build instead of shipping a '
        'silently-recovered blob', () async {
      final logs = <String>[];
      // `0x` is an incomplete hex literal (a scanner error). Parser recovery
      // yields `width: 0`, which normalises to a valid `0.0` and would
      // otherwise ship a clean blob with no record of the malformed source.
      final result = await _build('SizedBox(width: 0x)', logs: logs);

      expect(result.succeeded, isFalse);
      final log = logs.join('\n');
      expect(log, contains('[malformedSourceInput]'));
      // The diagnostic carries the analyzer's actual human-readable message
      // (not an opaque DiagnosticMessage object rendering), so it is
      // actionable. Scanner errors for `0x` mention a hex digit.
      expect(log.toLowerCase(), contains('hex'));
    });

    test(
        'an unterminated string fails the build instead of shipping a '
        'silently-recovered blob', () async {
      final logs = <String>[];
      final result = await _build("Text('hello)", logs: logs);

      expect(result.succeeded, isFalse);
      expect(logs.join('\n'), contains('[malformedSourceInput]'));
    });

    test(
        'a syntax error that prevents paywall discovery still fails the '
        'build instead of silently skipping', () async {
      // A top-level syntactic error severe enough that no `@PaywallSource`
      // class is discovered would otherwise hit the no-sources early-return
      // and silently produce no output — the paywall the author intended is
      // simply absent (a runtime load failure). The syntactic-error pass runs
      // before that early-return, so the malformed file is diagnosed.
      final logs = <String>[];
      const source = '''
        $kStubAnnotationsAndBases

        @PaywallSource(id: 'syntax_probe')
        class extends StatelessWidget {
          const SyntaxProbePaywall();
          Widget build(BuildContext context) => const SizedBox();
        }
      ''';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: false,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/paywalls/syntax_probe.dart'),
        source,
      );
      final result = await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/paywalls/syntax_probe.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        onLog: (record) => logs.add(record.message),
      );

      expect(result.succeeded, isFalse);
      expect(logs.join('\n'), contains('[malformedSourceInput]'));
    });

    test('a well-formed source still builds (no false positive)', () async {
      final logs = <String>[];
      final result = await _build(
        'Center(child: SizedBox(width: 64.0, height: 64.0))',
        logs: logs,
      );

      expect(result.succeeded, isTrue);
      expect(logs.join('\n'), isNot(contains('[malformedSourceInput]')));
    });
  });
}
