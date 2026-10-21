// An interpolated value can be any String the surface reads: host data, a
// State field, a build() local or a condition over them.

import 'package:build/build.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const String _package = 'apps_examples';

String _paywall(String name, String body) => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@Paywall()
class $name extends StatefulWidget {
  const $name({super.key, required this.yearlyPrice, required this.monthlyPrice});
  final String yearlyPrice;
  final String monthlyPrice;

  @override
  State<$name> createState() => _${name}State();
}

class _${name}State extends State<$name> {
  bool yearly = true;

  @override
  Widget build(BuildContext context) {
    $body
  }
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

String _rfwtxt(TestBuilderResult result, String id) =>
    result.readerWriter.testing.readString(
      AssetId(_package, 'assets/paywalls/$id.rfwtxt'),
    );

void main() {
  group('lowers', () {
    late TestBuilderResult result;

    setUpAll(() async {
      result = await _build({
        'local': r'''
    final price = yearly ? widget.yearlyPrice : widget.monthlyPrice;
    return Text('$price billed');''',
        'inline_condition': r'''
    return Text('${yearly ? widget.yearlyPrice : widget.monthlyPrice} billed');''',
        'string_slot': r'''
    final price = yearly ? widget.yearlyPrice : widget.monthlyPrice;
    return Semantics(
      label: yearly ? '$price a year' : 'Monthly at $price',
      child: const Text('Plans'),
    );''',
      });
    });

    test('a build() local interpolates', () {
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      final text = _rfwtxt(result, 'local');
      expect(text, contains('data.context.yearlyPrice'));
      expect(text, contains('data.context.monthlyPrice'));
      expect(text, contains('" billed"'));
    });

    test('a String property joins its parts', () {
      final text = _rfwtxt(result, 'string_slot');
      expect(text, contains('label: switch state.yearly'));
      expect(text, contains('" a year"]'));
      expect(text, contains('["Monthly at ", '));
    });

    test('a condition interpolates', () {
      expect(
        _rfwtxt(result, 'inline_condition'),
        allOf(contains('switch state.yearly'), contains('" billed"')),
      );
    });
  });

  test('a value that is not a String is refused with what is allowed',
      () async {
    final result = await _build({
      'number': r'''
    return Text('${42} days');''',
    });
    expect(
      result.errors.join('\n'),
      allOf(
        contains(IssueCode.unsupportedInterpolation.name),
        contains('must be a non-null String'),
      ),
    );
  });
}
