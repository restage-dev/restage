// Translator-side coverage for the device-as-data mechanism: recognising
// MediaQuery / platform / locale reads and emitting the `data.device.*`
// references the SDK publishes on every mount.

import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/widget_classification.dart';
import 'package:restage_shared/restage_shared.dart'
    show kDeviceContractPathKinds, kDeviceContractPaths;
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('kDeviceContractPathKinds keys exactly match kDeviceContractPaths', () {
    expect(kDeviceContractPathKinds.keys.toSet(), kDeviceContractPaths);
  });

  group('ExpressionTranslator — device value reads', () {
    late ExpressionTranslator translator;

    setUp(() {
      translator = ExpressionTranslator(
        catalog: kEmptyCatalog,
        helpers: HelperRegistry(),
      );
    });

    Future<TranslationResult> lower(String source) async =>
        translator.translate(await parseExpressionForTest(source));

    const shapes = <String, String>{
      'MediaQuery.sizeOf(context).width': 'screenWidth',
      'MediaQuery.sizeOf(context).height': 'screenHeight',
      'MediaQuery.of(context).size.width': 'screenWidth',
      'MediaQuery.of(context).size.height': 'screenHeight',
      'MediaQuery.sizeOf(context).shortestSide': 'shortestSide',
      'MediaQuery.sizeOf(context).longestSide': 'longestSide',
      'MediaQuery.of(context).size.shortestSide': 'shortestSide',
      'MediaQuery.orientationOf(context)': 'orientation',
      'MediaQuery.of(context).orientation': 'orientation',
      'MediaQuery.devicePixelRatioOf(context)': 'pixelRatio',
      'MediaQuery.of(context).devicePixelRatio': 'pixelRatio',
      'MediaQuery.paddingOf(context).top': 'safeAreaTop',
      'MediaQuery.paddingOf(context).bottom': 'safeAreaBottom',
      'MediaQuery.paddingOf(context).left': 'safeAreaLeft',
      'MediaQuery.paddingOf(context).right': 'safeAreaRight',
      'MediaQuery.of(context).padding.top': 'safeAreaTop',
      'MediaQuery.of(context).padding.right': 'safeAreaRight',
      'Localizations.localeOf(context).languageCode': 'languageCode',
      'Localizations.localeOf(context).countryCode': 'countryCode',
      'defaultTargetPlatform': 'platform',
      'Theme.of(context).platform': 'platform',
    };

    for (final entry in shapes.entries) {
      test('${entry.key} → data.device.${entry.value}', () async {
        final result = await lower(entry.key);

        expect(result.issues, isEmpty);
        expect(result.dsl, 'data.device.${entry.value}');
      });
    }

    test('a prefixed framework import is recognised', () async {
      final result = await lower('widgets.MediaQuery.sizeOf(context).width');

      expect(result.issues, isEmpty);
      expect(result.dsl, 'data.device.screenWidth');
    });

    test('a parenthesized chain segment is recognised', () async {
      final result = await lower('(MediaQuery.sizeOf(context)).width');

      expect(result.issues, isEmpty);
      expect(result.dsl, 'data.device.screenWidth');
    });

    test('an out-of-contract MediaQuery member refuses loud', () async {
      final result = await lower('MediaQuery.viewPaddingOf(context).top');

      expect(result.dsl, '');
      expect(result.issues.single.code, IssueCode.themeReadOutOfContract);
      expect(result.issues.single.message, contains('data.device'));
    });

    test('an out-of-contract MediaQueryData member refuses loud', () async {
      final result = await lower('MediaQuery.of(context).size.aspectRatio');

      expect(result.dsl, '');
      expect(result.issues.single.code, IssueCode.themeReadOutOfContract);
    });

    test('a whole-Locale read refuses loud', () async {
      final result = await lower('Localizations.localeOf(context)');

      expect(result.dsl, '');
      expect(result.issues.single.code, IssueCode.themeReadOutOfContract);
    });

    test('a non-device Theme chain stays with the theme recogniser', () async {
      final result = await lower('Theme.of(context).textTheme.bodyLarge');

      expect(result.dsl, '');
      // The theme recogniser owns the diagnostic, whichever theme read it is.
      expect(result.issues.single.message, contains('theme read'));
      expect(result.issues.single.message, isNot(contains('data.device')));
    });
  });

  group('ExpressionTranslator — device reads in property slots', () {
    late ExpressionTranslator translator;

    setUp(() {
      translator = ExpressionTranslator(
        catalog: catalogWith([
          entry(
            name: 'SizedBox',
            flutterType: 'package:flutter/widgets.dart#SizedBox',
            properties: [
              prop('width', PropertyType.length),
              prop('height', PropertyType.length),
            ],
          ),
          entry(
            name: 'Padding',
            flutterType: 'package:flutter/widgets.dart#Padding',
            properties: [prop('padding', PropertyType.edgeInsets)],
          ),
          entry(
            name: 'Text',
            flutterType: 'package:flutter/widgets.dart#Text',
            properties: [prop('data', PropertyType.string, positional: true)],
          ),
        ]),
        helpers: HelperRegistry(),
      );
    });

    Future<TranslationResult> lower(String source) async =>
        translator.translate(await parseExpressionForTest(source));

    test('a screen dimension fills a length slot', () async {
      final result = await lower(
        'SizedBox(width: MediaQuery.sizeOf(context).width)',
      );

      expect(result.issues, isEmpty);
      expect(result.dsl, 'SizedBox(width: data.device.screenWidth)');
    });

    test('a safe-area inset fills an EdgeInsets slot', () async {
      final result = await lower(
        'Padding(padding: EdgeInsets.only(top: '
        'MediaQuery.paddingOf(context).top))',
      );

      expect(result.issues, isEmpty);
      expect(result.dsl, contains('data.device.safeAreaTop'));
    });

    test('the platform token fills a string slot', () async {
      final result = await lower('Text(defaultTargetPlatform)');

      expect(result.issues, isEmpty);
      expect(result.dsl, 'Text(data: data.device.platform)');
    });

    test('a token in a length slot is a property type mismatch', () async {
      final result = await lower(
        'SizedBox(width: Localizations.localeOf(context).languageCode)',
      );

      expect(result.issues.single.code, IssueCode.propertyValueTypeMismatch);
      expect(
        result.issues.single.message,
        contains("Device value 'data.device.languageCode'"),
      );
    });

    test('a screen dimension in a string slot is a mismatch', () async {
      final result = await lower('Text(MediaQuery.sizeOf(context).width)');

      expect(result.issues.single.code, IssueCode.propertyValueTypeMismatch);
      expect(
        result.issues.single.message,
        contains("Device value 'data.device.screenWidth'"),
      );
    });
  });

  group('ExpressionTranslator — device token conditionals', () {
    late ExpressionTranslator translator;

    setUp(() {
      translator = ExpressionTranslator(
        catalog: catalogWith([
          entry(
            name: 'Text',
            flutterType: 'package:flutter/widgets.dart#Text',
            properties: [prop('data', PropertyType.string, positional: true)],
          ),
        ]),
        helpers: HelperRegistry(),
      );
    });

    Future<TranslationResult> lower(String source) async =>
        translator.translate(await parseExpressionForTest(source));

    void expectParses(String dsl) {
      expect(
        () => fmt.parseLibraryFile('widget Root = Text(data: $dsl);'),
        returnsNormally,
      );
    }

    test('a platform equality lowers to a two-arm switch', () async {
      final result = await lower(
        "defaultTargetPlatform == TargetPlatform.iOS ? 'a' : 'b'",
      );

      expect(result.issues, isEmpty);
      expect(
        result.dsl,
        'switch data.device.platform { "iOS": "a", default: "b" }',
      );
      expectParses(result.dsl);
    });

    test('the literal-on-the-left form lowers the same way', () async {
      final result = await lower(
        "TargetPlatform.android == defaultTargetPlatform ? 'a' : 'b'",
      );

      expect(result.issues, isEmpty);
      expect(
        result.dsl,
        'switch data.device.platform { "android": "a", default: "b" }',
      );
    });

    test('a `!=` swaps the arms', () async {
      final result = await lower(
        "defaultTargetPlatform != TargetPlatform.iOS ? 'a' : 'b'",
      );

      expect(result.issues, isEmpty);
      expect(
        result.dsl,
        'switch data.device.platform { "iOS": "b", default: "a" }',
      );
    });

    test('a same-path else-chain flattens into one N-arm switch', () async {
      final result = await lower(
        "defaultTargetPlatform == TargetPlatform.iOS ? 'a' : "
        "defaultTargetPlatform == TargetPlatform.android ? 'b' : 'c'",
      );

      expect(result.issues, isEmpty);
      expect(
        result.dsl,
        'switch data.device.platform '
        '{ "iOS": "a", "android": "b", default: "c" }',
      );
      expectParses(result.dsl);
    });

    test('a languageCode equality lowers to a switch on the subtag', () async {
      final result = await lower(
        "Localizations.localeOf(context).languageCode == 'en' ? 'a' : 'b'",
      );

      expect(result.issues, isEmpty);
      expect(
        result.dsl,
        'switch data.device.languageCode { "en": "a", default: "b" }',
      );
      expectParses(result.dsl);
    });

    test('an orientation equality lowers to a switch on the token', () async {
      final result = await lower(
        'MediaQuery.orientationOf(context) == Orientation.portrait '
        "? 'a' : 'b'",
      );

      expect(result.issues, isEmpty);
      expect(
        result.dsl,
        'switch data.device.orientation { "portrait": "a", default: "b" }',
      );
      expectParses(result.dsl);
    });

    test('kIsWeb lowers to the web platform key', () async {
      final result = await lower("kIsWeb ? 'a' : 'b'");

      expect(result.issues, isEmpty);
      expect(
        result.dsl,
        'switch data.device.platform { "web": "a", default: "b" }',
      );
    });

    const platformFlags = <String, String>{
      'Platform.isIOS': 'iOS',
      'Platform.isAndroid': 'android',
      'Platform.isMacOS': 'macOS',
      'Platform.isWindows': 'windows',
      'Platform.isLinux': 'linux',
      'Platform.isFuchsia': 'fuchsia',
    };

    for (final flag in platformFlags.entries) {
      test('${flag.key} lowers to the ${flag.value} platform key', () async {
        final result = await lower("${flag.key} ? 'a' : 'b'");

        expect(result.issues, isEmpty);
        expect(
          result.dsl,
          'switch data.device.platform '
          '{ "${flag.value}": "a", default: "b" }',
        );
        expectParses(result.dsl);
      });
    }

    test('an unrelated Platform member is not a platform flag', () async {
      final result = await lower("Platform.isBeta ? 'a' : 'b'");

      expect(result.dsl, '');
      expect(result.issues, isNotEmpty);
    });

    test('a numeric comparison on device data refuses loud', () async {
      final result = await lower(
        "MediaQuery.sizeOf(context).width > 600 ? 'a' : 'b'",
      );

      expect(result.dsl, '');
      expect(result.issues.single.code, IssueCode.themeReadOutOfContract);
      expect(result.issues.single.message, contains('numeric comparison'));
    });

    test('a platform compared to a non-TargetPlatform value refuses', () async {
      final result = await lower("defaultTargetPlatform == 'ios' ? 'a' : 'b'");

      expect(result.dsl, '');
      expect(result.issues.single.code, IssueCode.themeReadOutOfContract);
    });

    test('a whole-Locale comparison refuses loud', () async {
      final result = await lower(
        "Localizations.localeOf(context) == const Locale('en') ? 'a' : 'b'",
      );

      expect(result.dsl, '');
      expect(result.issues, isNotEmpty);
      expect(
        result.issues.any((i) => i.code == IssueCode.themeReadOutOfContract),
        isTrue,
      );
    });
  });

  group('WidgetClassifier — device reads inside a custom widget', () {
    Future<WidgetClassification> classify(String build) => classifyFixture(
          {
            'lib/plate.dart': """
$kFlutterClassifierStubs

class Box extends StatelessWidget {
  const Box({this.width, this.label, super.key});
  final double? width;
  final String? label;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'AcmePlate',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'plate',
)
class AcmePlate extends StatelessWidget {
  const AcmePlate({super.key});
  @override
  Widget build(BuildContext context) => $build;
}
""",
          },
          inputPath: 'lib/plate.dart',
          widgetName: 'AcmePlate',
          catalog: catalogWith([
            entry(
              name: 'Box',
              flutterType: 'package:apps_examples/plate.dart#Box',
              properties: [
                prop('width', PropertyType.length),
                prop('label', PropertyType.string),
              ],
            ),
          ]),
        );

    test('a platform comparison as a ternary condition inlines', () async {
      final result = await classify(
        'Box(label: defaultTargetPlatform == TargetPlatform.iOS '
        "? 'a' : 'b')",
      );

      expect(result, isA<ComposableWidget>());
      expect(
        (result as ComposableWidget).requiredMechanisms,
        contains(InliningMechanism.themeAsData),
      );
    });

    test('a locale-subtag comparison as a ternary condition inlines', () async {
      final result = await classify(
        "Box(label: Localizations.localeOf(context).languageCode == 'en' "
        "? 'a' : 'b')",
      );

      expect(result, isA<ComposableWidget>());
    });

    test('a dart:io platform flag as a ternary condition inlines', () async {
      final result = await classify("Box(label: Platform.isIOS ? 'a' : 'b')");

      expect(result, isA<ComposableWidget>());
    });

    test('a device value read inlines', () async {
      final result =
          await classify('Box(width: MediaQuery.sizeOf(context).width)');

      expect(result, isA<ComposableWidget>());
    });
  });
}
