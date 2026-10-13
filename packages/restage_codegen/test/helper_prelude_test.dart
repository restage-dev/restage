import 'package:build/build.dart';
import 'package:restage_codegen/builder.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const String _package = 'apps_examples';

String _paywall(String name, String build, {String helper = ''}) => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@Paywall()
class $name extends StatelessWidget {
  const $name({super.key});

  @override
  Widget build(BuildContext context) {
$build
  }
$helper
}
''';

final Map<String, String> _fixtures = {
  'helper_locals': _paywall(
    'HelperLocals',
    "    return Column(children: [_card(context, 'A'), _card(context, 'B')]);",
    helper: '''
  Widget _card(BuildContext context, String title) {
    final scheme = Theme.of(context).colorScheme;
    final label = Text(title);
    return Container(color: scheme.primary, child: label);
  }''',
  ),
  'helper_inlined': _paywall(
    'HelperInlined',
    '''
    return Column(
      children: [
        Container(
          color: Theme.of(context).colorScheme.primary,
          child: const Text('A'),
        ),
        Container(
          color: Theme.of(context).colorScheme.primary,
          child: const Text('B'),
        ),
      ],
    );''',
  ),
  'top_level_helper_locals': '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

Widget _row(String title) {
  final label = Text(title);
  return Row(children: [label]);
}

@Paywall()
class TopLevelHelperLocals extends StatelessWidget {
  const TopLevelHelperLocals({super.key});

  @override
  Widget build(BuildContext context) => Column(children: [_row('A')]);
}
''',
  'top_level_helper_inlined': _paywall(
    'TopLevelHelperInlined',
    "    return Column(children: [Row(children: [const Text('A')])]);",
  ),
};

Future<TestReaderWriter> _seeded(Map<String, String> sources) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: _package,
    includeFlutter: true,
  );
  for (final entry in sources.entries) {
    readerWriter.testing.writeString(AssetId.parse(entry.key), entry.value);
  }
  return readerWriter;
}

String _text(TestBuilderResult result, String id) => result.readerWriter.testing
    .readString(AssetId(_package, 'assets/paywalls/$id.rfwtxt'));

Future<String> _log(
  String slug,
  String source, {
  Map<String, String> parts = const {},
}) async {
  final sources = {
    '$_package|lib/paywalls/$slug.dart': source,
    for (final entry in parts.entries)
      '$_package|lib/paywalls/${entry.key}': entry.value,
  };
  final logs = <String>[];
  await testBuilder(
    restageCodegenBuilder(BuilderOptions.empty),
    sources,
    rootPackage: _package,
    readerWriter: await _seeded(sources),
    outputs: const {},
    onLog: (record) => logs.add(record.message),
  );
  return logs.join('\n');
}

void main() {
  late TestBuilderResult result;

  setUpAll(() async {
    final sources = {
      for (final entry in _fixtures.entries)
        '$_package|lib/paywalls/${entry.key}.dart': entry.value,
    };
    result = await testBuilders(
      [restageCodegenBuilder(BuilderOptions.empty)],
      sources,
      rootPackage: _package,
      readerWriter: await _seeded(sources),
      flattenOutput: true,
    );
  });

  test('every helper fixture compiles', () {
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
  });

  test('a helper with final locals matches its inlined twin', () {
    expect(
      _text(result, 'helper_locals'),
      contains('data.theme.colorScheme.primary'),
    );
    expect(_text(result, 'helper_locals'), _text(result, 'helper_inlined'));
  });

  test('a top-level helper with a final local matches its inlined twin', () {
    expect(
      _text(result, 'top_level_helper_locals'),
      _text(result, 'top_level_helper_inlined'),
    );
  });

  test('an unread helper local is refused by name', () async {
    final log = await _log(
      'helper_unused_local',
      _paywall(
        'HelperUnusedLocal',
        '    return Column(children: [_card()]);',
        helper: '''
  Widget _card() {
    final unused = 'x';
    return const Text('A');
  }''',
      ),
    );
    expect(
      log,
      contains(
        "The helper '_card' cannot be inlined: the local 'unused' is declared "
        "in the helper '_card' but never read",
      ),
    );
    expect(log, isNot(contains('unknownWidget')));
  });

  test('an unsupported helper statement is refused by name', () async {
    final log = await _log(
      'helper_statement',
      _paywall(
        'HelperStatement',
        '    return Column(children: [_card(true)]);',
        helper: '''
  Widget _card(bool wide) {
    if (wide) return const Text('Wide');
    return const Text('Narrow');
  }''',
      ),
    );
    expect(
      log,
      contains(
        "The helper '_card' cannot be inlined: its body must be one returned "
        'expression',
      ),
    );
    expect(log, isNot(contains('unknownWidget')));
  });

  test('a refused helper in a part file is refused by name', () async {
    final log = await _log(
      'helper_part',
      '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'helper_part_cards.dart';

@Paywall()
class HelperPart extends StatelessWidget {
  const HelperPart({super.key});

  @override
  Widget build(BuildContext context) => Column(children: [_card(true)]);
}
''',
      parts: {
        'helper_part_cards.dart': '''
part of 'helper_part.dart';

Widget _card(bool wide) {
  if (wide) return const Text('Wide');
  return const Text('Narrow');
}
''',
      },
    );
    expect(
      log,
      contains(
        "The helper '_card' cannot be inlined: its body must be one returned "
        'expression',
      ),
    );
    expect(log, isNot(contains('unknownWidget')));
  });
}
