// Lowering coverage for the `data.theme.brightness` read: a Dart ternary
// testing the ambient brightness becomes an RFW switch on the published token.

import 'package:build/build.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const String _package = 'apps_examples';

String _paywall(String name, String body) => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@Paywall()
class $name extends StatelessWidget {
  const $name({super.key});

  @override
  Widget build(BuildContext context) {
$body
  }
}
''';

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

void main() {
  group('brightness ternary → switch (recognition)', () {
    late ExpressionTranslator translator;

    setUp(() {
      translator = ExpressionTranslator(
        catalog: catalogWith([
          entry(
            name: 'Text',
            properties: [prop('text', PropertyType.string, positional: true)],
          ),
          entry(
            name: 'Icon',
            properties: [prop('color', PropertyType.color)],
          ),
        ]),
        helpers: HelperRegistry(),
      );
    });

    Future<TranslationResult> lower(String source) async =>
        translator.translate(await parseExpressionForTest(source));

    test('== Brightness.dark keys the dark arm', () async {
      final result = await lower(
        'Theme.of(context).brightness == Brightness.dark '
        "? Text('night') : Text('day')",
      );

      expect(result.issues, isEmpty);
      expect(
        result.dsl,
        'switch data.theme.brightness '
        '{ "dark": Text(text: "night"), default: Text(text: "day") }',
      );
    });

    test('== Brightness.light keys the light arm', () async {
      final result = await lower(
        'Theme.of(context).brightness == Brightness.light '
        "? Text('day') : Text('night')",
      );

      expect(result.issues, isEmpty);
      expect(
        result.dsl,
        'switch data.theme.brightness '
        '{ "light": Text(text: "day"), default: Text(text: "night") }',
      );
    });

    test('!= Brightness.dark swaps the arms', () async {
      final result = await lower(
        'Theme.of(context).brightness != Brightness.dark '
        "? Text('day') : Text('night')",
      );

      expect(result.issues, isEmpty);
      expect(
        result.dsl,
        'switch data.theme.brightness '
        '{ "dark": Text(text: "night"), default: Text(text: "day") }',
      );
    });

    test('the literal may sit on the left', () async {
      final result = await lower(
        'Brightness.dark == Theme.of(context).brightness '
        "? Text('night') : Text('day')",
      );

      expect(result.issues, isEmpty);
      expect(
        result.dsl,
        'switch data.theme.brightness '
        '{ "dark": Text(text: "night"), default: Text(text: "day") }',
      );
    });

    test('the colorScheme chain names the same value', () async {
      final result = await lower(
        'Theme.of(context).colorScheme.brightness == Brightness.dark '
        "? Text('night') : Text('day')",
      );

      expect(result.issues, isEmpty);
      expect(
        result.dsl,
        'switch data.theme.brightness '
        '{ "dark": Text(text: "night"), default: Text(text: "day") }',
      );
    });

    test('a bare colorScheme.brightness read is out of contract', () async {
      final result = await lower(
        'Icon(color: Theme.of(context).colorScheme.brightness)',
      );

      expect(result.dsl, '');
      expect(
        result.issues.any(
          (i) => i.code == IssueCode.themeReadOutOfContract,
        ),
        isTrue,
      );
    });

    test('lowers inside a colour slot', () async {
      final result = await lower(
        'Icon(color: Theme.of(context).brightness == Brightness.dark '
        '? 0xFFFFFFFF : 0xFF000000)',
      );

      expect(result.issues, isEmpty);
      expect(
        result.dsl,
        'Icon(color: switch data.theme.brightness '
        '{ "dark": 4294967295, default: 4278190080 })',
      );
    });

    test('the emitted switch parses as RFW', () async {
      final result = await lower(
        'Theme.of(context).brightness == Brightness.dark '
        "? Text('night') : Text('day')",
      );

      expect(
        () => fmt.parseLibraryFile('widget Root = ${result.dsl};'),
        returnsNormally,
      );
    });

    test('an ordering comparison on brightness refuses loudly', () async {
      final result = await lower(
        'Theme.of(context).brightness == 1 '
        "? Text('night') : Text('day')",
      );

      expect(result.dsl, '');
      expect(result.issues, isNotEmpty);
      expect(
        result.issues.first.code,
        IssueCode.themeReadOutOfContract,
      );
    });

    test('a bare brightness read into a colour slot refuses', () async {
      final result = await lower('Icon(color: Theme.of(context).brightness)');

      expect(result.issues, isNotEmpty);
      expect(
        result.issues.any(
          (i) => i.code == IssueCode.propertyValueTypeMismatch,
        ),
        isTrue,
      );
    });
  });

  group('brightness ternary → switch (resolved)', () {
    late TestBuilderResult result;

    setUpAll(() async {
      final sources = <String, String>{
        '$_package|lib/paywalls/direct.dart': _paywall('Direct', '''
    return Container(
      color: Theme.of(context).brightness == Brightness.dark
          ? Colors.black
          : Colors.white,
      height: 20,
    );'''),
        '$_package|lib/paywalls/bound_flag.dart': _paywall('BoundFlag', '''
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? Colors.black : Colors.white,
      height: 20,
    );'''),
        '$_package|lib/paywalls/bound_read.dart': _paywall('BoundRead', '''
    final mode = Theme.of(context).brightness;
    return Container(
      color: mode == Brightness.dark ? Colors.black : Colors.white,
      height: 20,
    );'''),
        '$_package|lib/paywalls/scheme_read.dart': _paywall('SchemeRead', '''
    return Container(
      color: Theme.of(context).colorScheme.brightness == Brightness.dark
          ? Colors.black
          : Colors.white,
      height: 20,
    );'''),
      };
      result = await testBuilders(
        [restageCodegenBuilder(BuilderOptions.empty)],
        sources,
        rootPackage: _package,
        readerWriter: await _seeded(sources),
        flattenOutput: true,
      );
    });

    String text(String id) => result.readerWriter.testing
        .readString(AssetId(_package, 'assets/paywalls/$id.rfwtxt'));

    test('every brightness fixture compiles', () {
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      expect(result.errors, isEmpty);
    });

    test('a direct brightness ternary lowers to the switch', () {
      expect(
        text('direct'),
        contains('switch data.theme.brightness { "dark": 0xFF000000'),
      );
    });

    test('a bound boolean flag lowers identically', () {
      expect(
          text('bound_flag'), text('direct').replaceAll('Direct', 'BoundFlag'));
    });

    test('a bound brightness read lowers identically', () {
      expect(
          text('bound_read'), text('direct').replaceAll('Direct', 'BoundRead'));
    });

    test('the colorScheme chain lowers identically', () {
      expect(
        text('scheme_read'),
        text('direct').replaceAll('Direct', 'SchemeRead'),
      );
    });
  });
}
