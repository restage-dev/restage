import 'dart:io';

import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/rfw_constructor_presence_protocol.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final catalog = decodeCatalog(
    File(
      '../restage_core/lib/src/widget_catalog/catalog.json',
    ).readAsStringSync(),
  );
  final translator = ExpressionTranslator(
    catalog: catalog,
    helpers: HelperRegistry()
      ..registerAll([
        HelperDefinition(
          name: 'eventFor',
          libraryOrigin: 'package:restage_codegen',
          returnCategory: HelperReturnCategory.voidCallback,
          translate: (args) => 'event ${args.positional.single} {}',
        ),
      ]),
  );

  Future<TranslationResult> lower(
    String recognizer, {
    String declarations = '',
  }) async {
    final expression = await parseExpressionFromSourceForTest('''
import 'package:flutter/widgets.dart';
import 'package:flutter/gestures.dart';
VoidCallback eventFor(String name) => () {};
$declarations
Object x() => Text.rich(TextSpan(text: 'Tap', recognizer: $recognizer));
''');
    return translator.translate(expression);
  }

  test(
    'ordinary native cascade carries callbacks and constructor presence',
    () async {
      final result = await lower(
        "TapGestureRecognizer(preAcceptSlopTolerance: null, postAcceptSlopTolerance: 9, supportedDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse})..onTap = eventFor('tap')..onTapCancel = eventFor('cancel')",
      );
      expect(result.issues.where((i) => !i.code.isInformational), isEmpty);
      expect(result.dsl, contains('kind: "tap"'));
      expect(result.dsl, contains('onTap: event "tap" {}'));
      expect(result.dsl, contains('onTapCancel: event "cancel" {}'));
      expect(
        result.dsl,
        contains(
          'preAcceptSlopTolerance: ${RfwConstructorPresenceEncoder.supplied('null')}',
        ),
      );
      expect(
        result.dsl,
        contains(
          'postAcceptSlopTolerance: ${RfwConstructorPresenceEncoder.supplied('9.0')}',
        ),
      );
      expect(result.dsl, contains('supportedDevices: ["touch", "mouse"]'));
    },
  );

  for (final (constructor, kind, callback) in [
    ('TapGestureRecognizer', 'tap', 'onSecondaryTap'),
    ('DoubleTapGestureRecognizer', 'doubleTap', 'onDoubleTap'),
    ('LongPressGestureRecognizer', 'longPress', 'onLongPressUp'),
  ]) {
    test(
      '$constructor preserves empty construction and native callbacks',
      () async {
        expect((await lower('$constructor()')).dsl, contains('kind: "$kind"'));
        final result = await lower(
          "($constructor()..$callback = eventFor('go'))",
        );
        expect(result.issues.where((i) => !i.code.isInformational), isEmpty);
        expect(result.dsl, contains('$callback: event "go" {}'));
      },
    );
  }

  for (final recipe in [
    'TapGestureRecognizer()..onTapDown = (details) => print(details.globalPosition)',
    'TapGestureRecognizer()..dispose()',
    'TapGestureRecognizer()..onTap = () { print("imperative"); }',
    'TapGestureRecognizer(allowedButtonsFilter: (buttons) => true)',
    'TapGestureRecognizer(debugOwner: Object())',
    'TapGestureRecognizer()..gestureSettings = const DeviceGestureSettings(touchSlop: 10)',
    'CustomTap()',
    'external',
  ]) {
    test('refuses $recipe without partial rich text', () async {
      final result = await lower(
        recipe,
        declarations:
            'class CustomTap extends TapGestureRecognizer {}\nfinal external = TapGestureRecognizer();',
      );
      expect(result.dsl, isEmpty);
      expect(result.issues.where((i) => !i.code.isInformational), isNotEmpty);
    });
  }

  test(
    'static nested collections preserve helper bindings and fresh evaluations',
    () async {
      final expr = await parseExpressionFromSourceForTest(r"""
import 'package:flutter/widgets.dart';
import 'package:flutter/gestures.dart';
VoidCallback eventFor(String name) => () {};
List<InlineSpan> tail(String value) => [TextSpan(text: value)];
const intro = [TextSpan(text: 'start')];
const List<InlineSpan>? absent = null;
Object x() => Text.rich(TextSpan(children: [
  ...intro, ...?absent,
  for (final label in const ['a', 'b']) ...[
    TextSpan(text: label, recognizer: TapGestureRecognizer()..onTap = eventFor(label)),
    if (true) ...tail('!'),
  ],
  const TextSpan(text: 'end', children: []),
]));
""");
      final result = translator.translate(expr);
      expect(result.issues.where((i) => !i.code.isInformational), isEmpty);
      expect('kind: "tap"'.allMatches(result.dsl), hasLength(2));
      expect(result.dsl, contains('onTap: event "a" {}'));
      expect(result.dsl, contains('onTap: event "b" {}'));
      expect(
        result.dsl.indexOf('text: "a"'),
        lessThan(result.dsl.indexOf('text: "b"')),
      );
      expect(result.dsl, contains('text: "end", children: []'));
    },
  );

  test('static span loop guards retain their iteration bindings', () async {
    final expression = await parseExpressionFromSourceForTest('''
import 'package:flutter/widgets.dart';
Object x() => Text.rich(TextSpan(children: [
  for (final label in const ['a', 'b'])
    if (label == 'a') TextSpan(text: label),
]));
''');
    final result = translator.translate(expression);
    expect(
      result.issues.where((issue) => !issue.code.isInformational),
      isEmpty,
    );
    expect(result.dsl, contains('{ text: "a" }'));
    rfw.parseLibraryFile('import restage.core; widget Root = ${result.dsl};');
  });

  test(
    'native aliased constructor retains its defining type identity',
    () async {
      final expr = await parseExpressionFromSourceForTest("""
import 'package:flutter/widgets.dart';
import 'package:flutter/gestures.dart' as gestures;
Object x() => Text.rich(TextSpan(text: 'Tap', recognizer: gestures.TapGestureRecognizer()));
""");
      final result = translator.translate(expr);
      expect(
        result.issues.where((issue) => !issue.code.isInformational),
        isEmpty,
      );
      expect(result.dsl, contains('kind: "tap"'));
    },
  );

  test('resolved application constructor lookalike refuses', () async {
    final expr = await parseExpressionFromSourceForTest('''
import 'package:flutter/widgets.dart';
class TapGestureRecognizer { TapGestureRecognizer(); }
Object x() => Text.rich(TextSpan(text: 'Tap', recognizer: TapGestureRecognizer()));
''');
    final result = translator.translate(expr);
    expect(result.dsl, isEmpty);
    expect(result.issues.where((i) => !i.code.isInformational), isNotEmpty);
  });
  test(
    'global lazy recognizer read requires an installed owner input',
    () async {
      final expression = await parseExpressionFromSourceForTest("""
import 'package:flutter/widgets.dart';
import 'package:flutter/gestures.dart';
final shared = TapGestureRecognizer();
Object x() => Text.rich(TextSpan(children: [
  TextSpan(text: 'First', recognizer: shared),
  TextSpan(text: 'Second', recognizer: shared),
]));
""", rootPackage: 'apps_examples');
      final result = translator.translate(expression, hoistInMount: true);
      expect(result.dsl, isEmpty);
      expect(
        result.issues.where((issue) => !issue.code.isInformational),
        isNotEmpty,
      );
    },
  );

  for (final reference in ['fresh', 'owner().recognizer']) {
    test('refuses unowned fresh recognizer through $reference', () async {
      final expression = await parseExpressionFromSourceForTest("""
import 'package:flutter/widgets.dart';
import 'package:flutter/gestures.dart';
GestureRecognizer get fresh => TapGestureRecognizer();
class Owner { final recognizer = TapGestureRecognizer(); }
Owner owner() => Owner();
Object x() => Text.rich(TextSpan(recognizer: $reference));
""", rootPackage: 'apps_examples');
      final result = translator.translate(expression, hoistInMount: true);
      expect(result.dsl, isEmpty);
      expect(
        result.issues.where((issue) => !issue.code.isInformational),
        isNotEmpty,
      );
    });
  }
  test('root BuildContext escape requires an installed owner', () async {
    final expression = await parseExpressionFromSourceForTest("""
import 'package:flutter/widgets.dart';
import 'package:flutter/gestures.dart';
void seen(BuildContext context, TapDownDetails details) {}
Widget x(BuildContext context) => Text.rich(TextSpan(
  text: 'Tap', recognizer: TapGestureRecognizer()
    ..onTapDown = ((details) => seen(context, details))));
""", rootPackage: 'apps_examples');
    final result = translator.translate(expression, hoistInMount: true);
    expect(result.dsl, isEmpty);
    expect(
      result.issues.where((issue) => !issue.code.isInformational),
      isNotEmpty,
    );
  });
}
