import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _root = 'test/fixtures/explicit_authoring';

void main() {
  test('the authoring corpus is syntactically valid Dart', () {
    final files = _dartFiles(Directory(_root));
    expect(files, isNotEmpty);

    for (final file in files) {
      final parsed = parseString(
        content: file.readAsStringSync(),
        path: file.path,
        throwIfDiagnostics: false,
      );
      expect(
        parsed.errors,
        isEmpty,
        reason: 'Dart parse errors in ${p.relative(file.path)}',
      );
    }
  });

  test('the corpus contains every approved authoring shape', () {
    final relative = _dartFiles(Directory(_root))
        .map((file) => p.relative(file.path, from: _root))
        .toSet();

    expect(
      relative,
      containsAll(<String>[
        'linear/new/lib/onboarding/flows/welcome_flow.dart',
        'branching/new/lib/survey/flows/setup_survey.dart',
        'completion/new/lib/onboarding/flows/completion_paths.dart',
        'cycle/new/lib/onboarding/flows/retry_flow.dart',
        'action/new/lib/onboarding/flows/permission_flow.dart',
        'subflow/new/lib/onboarding/flows/account_setup.dart',
        'paywall/new/lib/onboarding/flows/first_run_flow.dart',
        'paywall_cross_category/lib/general/flows/general_offer.dart',
        'categories/new/lib/general/flows/account_recovery.dart',
        'categories/new/lib/onboarding/flows/mismatch.dart',
        'categories/new/lib/onboarding/flows/complex_flow.dart',
        'identity/new/lib/general/flows/derived_flow.dart',
        'identity/new/lib/message/flows/moved_flow.dart',
        'negative/duplicate_implicit.dart',
        'negative/duplicate_implicit_flow.dart',
        'negative/duplicate_explicit.dart',
        'negative/two_terminals/lib/onboarding/flows/two_terminals.dart',
      ]),
    );
  });

  test('canonical sources carry code-level surface authority', () {
    for (final file in _dartFiles(Directory(_root))) {
      final relative = p.relative(file.path, from: _root);
      if (!relative.contains('/new/') &&
          !relative.startsWith('categories/new/') &&
          !relative.startsWith('identity/new/')) {
        continue;
      }
      final source = file.readAsStringSync();
      if (source.contains('@FlowGraph')) {
        expect(
          RegExp(r'@FlowGraph\([\s\S]*?surface:\s*Surface\.').hasMatch(
            source,
          ),
          isTrue,
          reason: '$relative must not infer its flow category from a path',
        );
      }
      expect(
        source,
        isNot(contains('Type.toString')),
        reason: '$relative must not identify a screen through Type.toString',
      );
      expect(
        source,
        isNot(matches(RegExp(r'\bto:\s*\x27'))),
        reason: '$relative must use analyzer-resolved targets, not strings',
      );
    }
  });

  test('the corpus includes neutral/general, paywall, and compatibility forms',
      () {
    final contents = _dartFiles(Directory(_root))
        .map((file) => file.readAsStringSync())
        .join('\n');

    expect(contents, contains('@Screen(surface: Surface.general)'));
    expect(contents, contains('@FlowGraph(surface: Surface.general)'));
    expect(contents, contains('@Paywall('));
    expect(contents, isNot(contains('@Paywall(surface:')));
    expect(contents, contains('@Screen()'));
    expect(contents, contains('@ScreenSource('));
    expect(contents, contains('@PaywallSource('));
    expect(contents, contains('@FlowSource('));
    expect(contents, contains('const retryRef = NodeRef('));
    expect(contents, contains('FlowStateRef<String>'));
    expect(contents, contains('FlowActionRef<void, bool>'));
    expect(contents, contains('Subflow('));
  });
}

List<File> _dartFiles(Directory directory) => directory
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'))
    .toList()
  ..sort((left, right) => left.path.compareTo(right.path));
