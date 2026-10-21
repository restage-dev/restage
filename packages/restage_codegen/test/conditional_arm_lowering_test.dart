// Conditional arms that are `null` or interpolated lower to RFW the parser
// accepts: a `null` arm yields no value, and an interpolated arm selects an
// inline span.

import 'package:build/build.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:test/test.dart';

import 'helpers.dart';

const String _package = 'apps_examples';

String _paywall(String name, String body) => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@Paywall()
class $name extends StatelessWidget {
  const $name({
    super.key,
    required this.busy,
    required this.days,
    required this.plan,
  });
  final bool busy;
  final String days;
  final String plan;

  @override
  Widget build(BuildContext context) {
    return $body;
  }

  Widget _card(String title, String chip) =>
      Column(children: [Text(title), if (chip != '') Text(chip)]);

  String _chip(String chip) => chip != '' ? chip : 'none';

  String _loop(String text) => _loop(text);
}
''';

Future<TestBuilderResult> _build(Map<String, String> bodies) async {
  final sources = {
    for (final MapEntry(:key, :value) in bodies.entries)
      '$_package|lib/paywalls/$key.dart': _paywall('P$key', value),
  };
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: _package,
    includeFlutter: true,
  );
  for (final entry in sources.entries) {
    readerWriter.testing.writeString(AssetId.parse(entry.key), entry.value);
  }
  return await testBuilders(
    [restageCodegenBuilder(BuilderOptions.empty)],
    sources,
    rootPackage: _package,
    readerWriter: readerWriter,
    flattenOutput: true,
  );
}

void main() {
  group('conditional arms', () {
    late TestBuilderResult result;

    setUpAll(() async {
      result = await _build({
        'event_then_null': 'FilledButton(onPressed: busy ? null : '
            "paywallEvent('go'), child: const Text('Go'))",
        'event_else_null': 'GestureDetector(onTap: busy ? '
            "paywallEvent('yearly') : null, child: const Text('x'))",
        'border_null': 'Container(decoration: BoxDecoration(border: busy ? '
            'null : Border.all(color: Colors.black)))',
        'keyed_null': "GestureDetector(onTap: plan == 'a' ? null : "
            "paywallEvent('go'), child: const Text('x'))",
        'interpolated_arm':
            r"Text(busy ? 'Starting...' : 'Start ${days}-day trial')",
        'helper_collection_if': "_card('Yearly', busy ? days : '')",
        'helper_ternary': "Text(_chip(busy ? days : ''))",
        'nested_interpolated_arm': "Text(busy ? 'Starting...' : plan == "
            r"'a' ? 'Plan ${plan}' : 'Start ${days}-day trial', "
            'textAlign: TextAlign.center)',
      });
    });

    String widget(String id) => result.readerWriter.testing
        .readString(AssetId(_package, 'assets/paywalls/$id.rfwtxt'))
        .split('\n')
        .singleWhere((line) => line.startsWith('widget '));

    void parses(String id) => expect(
          () => fmt.parseLibraryFile(widget(id)),
          returnsNormally,
        );

    test('every fixture compiles', () {
      expect(result.errors, isEmpty, reason: result.errors.join('\n'));
    });

    test('a null arm on an event slot is left out', () {
      expect(
        widget('event_then_null'),
        contains('onPressed: switch data.context.busy '
            '{ false: event "go" {} }'),
      );
      expect(
        widget('event_else_null'),
        contains('onTap: switch data.context.busy '
            '{ true: event "yearly" {} }'),
      );
      parses('event_then_null');
      parses('event_else_null');
    });

    test('a null arm on a structured value is left out', () {
      expect(
        widget('border_null'),
        contains('border: switch data.context.busy '
            '{ false: [{color: 0xFF000000}] }'),
      );
      parses('border_null');
    });

    test('a null arm beside a default selects no value', () {
      expect(
        widget('keyed_null'),
        contains('onTap: switch data.context.plan '
            '{ "a": switch false {}, default: event "go" {} }'),
      );
      parses('keyed_null');
    });

    test('an interpolated arm lowers to a switch over inline spans', () {
      expect(
        widget('interpolated_arm'),
        'widget Paywall = TextRich(textSpan: switch data.context.busy '
        '{ true: { text: "Starting..." }, false: { children: '
        '[{ text: "Start " }, { text: data.context.days }, '
        '{ text: "-day trial" }] } });',
      );
      parses('interpolated_arm');
    });

    test('an equality over a substituted conditional splits into its arms', () {
      expect(
        widget('helper_collection_if'),
        contains('...for presence in switch data.context.busy '
            '{ true: switch data.context.days { "": [], default: [0] }, '
            'false: [] }: Text('),
      );
      expect(
        widget('helper_ternary'),
        contains('Text(text: switch data.context.busy '
            '{ true: switch data.context.days { "": "none", default: '),
      );
      parses('helper_collection_if');
      parses('helper_ternary');
    });

    test('a nested interpolated arm keeps the carried Text properties', () {
      expect(
        widget('nested_interpolated_arm'),
        allOf(
          contains('switch data.context.plan { "a": { children: '
              '[{ text: "Plan " }, { text: data.context.plan }] }'),
          contains('textAlign: "center"'),
          isNot(contains('__rfw')),
        ),
      );
      parses('nested_interpolated_arm');
    });
  });

  group('refusals', () {
    late TestBuilderResult result;

    setUpAll(() async {
      result = await _build({
        'label':
            r"Semantics(label: 'Hi ${days} there', child: const Text('x'))",
        'recursive_text': 'Text(_loop(days))',
      });
    });

    String errorFor(String id, IssueCode code) => result.errors.firstWhere(
          (e) => e.contains('[${code.name}] lib/paywalls/$id.dart'),
        );

    test('an interpolation outside Text is refused at its source', () {
      expect(
        errorFor('label', IssueCode.unsupportedInterpolation),
        contains('only be the text of a Text widget'),
      );
    });

    test('a recursive String helper in Text is refused', () {
      expect(
        errorFor('recursive_text', IssueCode.buildMethodTooComplex),
        contains('recursive helper'),
      );
    });

    test('no refusal reaches the parser', () {
      expect(
        result.errors.where(
          (e) => e.contains(IssueCode.malformedTranslatorOutput.name),
        ),
        isEmpty,
      );
    });
  });

  test('a measured callback with a handler in each arm is refused', () async {
    final result = await _build({
      'two_handlers': "FilledButton(onPressed: busy ? paywallEvent('a') : "
          "paywallEvent('b'), child: const Text('Go'))",
    });
    expect(
      result.errors.join('\n'),
      allOf(
        contains('[invalidEventConfiguration] lib/paywalls/two_handlers.dart:'),
        contains('can run only one handler'),
      ),
    );
  });
}
