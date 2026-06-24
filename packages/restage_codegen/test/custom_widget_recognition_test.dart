import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/widget_classification.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// The classKey `parseExpressionFromSourceForTest` produces for a class
/// named `AcmeWidget` — the synthetic probe file is mounted at
/// `package:restage_codegen/_expr_probe.dart`.
const String _key = 'package:restage_codegen/_expr_probe.dart#AcmeWidget';

const String _acmeWidgetSource = '''
  class AcmeWidget { const AcmeWidget(); }
  Object x() => const AcmeWidget();
''';

void main() {
  group('ExpressionTranslator — custom-widget recognition', () {
    test(
        'a composable widget needing a deferred mechanism emits '
        'customWidgetInliningDeferred', () async {
      // An inlinable-now composable widget is inlined (see
      // custom_widget_inlining_test.dart). A class-4a widget that still
      // needs an unimplemented mechanism — here declarative state, which
      // a later codegen increment will deliver — is recognised but
      // deferred rather than emitted.
      final translator = ExpressionTranslator(
        catalog: kEmptyCatalog,
        helpers: HelperRegistry(),
        customWidgetClassifications: {
          _key: ComposableWidget(
            _key,
            requiredMechanisms: const {InliningMechanism.declarativeState},
            composedCustomWidgets: const [],
          ),
        },
      );
      final expr = await parseExpressionFromSourceForTest(_acmeWidgetSource);
      final result = translator.translate(expr);

      expect(result.issues, hasLength(1));
      expect(
        result.issues.single.code,
        IssueCode.customWidgetInliningDeferred,
      );
    });

    test('an imperative custom widget emits customWidgetImperative', () async {
      final translator = ExpressionTranslator(
        catalog: kEmptyCatalog,
        helpers: HelperRegistry(),
        customWidgetClassifications: {
          _key: ImperativeWidget(
            _key,
            blockers: const [
              Blocker(
                kind: BlockerKind.customPainter,
                location: '$_key@9:7',
                detail: 'CustomPaint(painter: ChartPainter())',
              ),
            ],
          ),
        },
      );
      final expr = await parseExpressionFromSourceForTest(_acmeWidgetSource);
      final result = translator.translate(expr);

      expect(result.issues, hasLength(1));
      expect(result.issues.single.code, IssueCode.customWidgetImperative);
      expect(result.issues.single.message, contains('CustomPaint'));
      expect(result.issues.single.location, '$_key@9:7');
    });

    test('an unclassifiable custom widget emits customWidgetUnclassified',
        () async {
      final translator = ExpressionTranslator(
        catalog: kEmptyCatalog,
        helpers: HelperRegistry(),
        customWidgetClassifications: {
          _key: const UnclassifiableWidget(
            _key,
            reason: 'build() body is not a single returned expression',
          ),
        },
      );
      final expr = await parseExpressionFromSourceForTest(_acmeWidgetSource);
      final result = translator.translate(expr);

      expect(result.issues, hasLength(1));
      expect(result.issues.single.code, IssueCode.customWidgetUnclassified);
    });

    test(
        "an UnclassifiableWidget's diagnosticCode override flows through "
        '(e.g. themeReadIntermediateVariable)', () async {
      final translator = ExpressionTranslator(
        catalog: kEmptyCatalog,
        helpers: HelperRegistry(),
        customWidgetClassifications: {
          _key: const UnclassifiableWidget(
            _key,
            reason: 'build() reads Theme.of(...) into an intermediate '
                'variable; the transpiler cannot follow intermediate variables',
            diagnosticCode: IssueCode.themeReadIntermediateVariable,
          ),
        },
      );
      final expr = await parseExpressionFromSourceForTest(_acmeWidgetSource);
      final result = translator.translate(expr);

      expect(result.issues, hasLength(1));
      expect(
        result.issues.single.code,
        IssueCode.themeReadIntermediateVariable,
      );
      expect(result.issues.single.message, contains('intermediate variable'));
    });

    test('an unknown widget absent from the map still errors unknownWidget',
        () async {
      final translator = ExpressionTranslator(
        catalog: kEmptyCatalog,
        helpers: HelperRegistry(),
      );
      final expr = await parseExpressionFromSourceForTest(_acmeWidgetSource);
      final result = translator.translate(expr);

      expect(result.issues, hasLength(1));
      expect(result.issues.single.code, IssueCode.unknownWidget);
      // The normalised wording points the author at @RestageWidget rather
      // than claiming custom widgets are unsupported.
      expect(result.issues.single.message, contains('@RestageWidget'));
    });
  });

  group('RestageCodegenBuilder — custom-widget recognition', () {
    test(
        'a paywall referencing a custom widget surfaces the classified '
        'diagnostic, not unknownWidget', () async {
      const source = '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class PaywallSource {
  const PaywallSource({required this.id, this.slot});
  final String id;
  final String? slot;
}
class Widget { const Widget(); }
class BuildContext {}
class StatelessWidget extends Widget { const StatelessWidget(); }
class CustomPainter { const CustomPainter(); }
class CustomPaint extends StatelessWidget {
  const CustomPaint({this.painter});
  final CustomPainter? painter;
  Widget build(BuildContext context) => const Widget();
}
class ChartPainter extends CustomPainter {
  const ChartPainter();
}

@RestageWidget(
  name: 'AcmeChart',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.display,
  description: 'chart',
)
class AcmeChart extends StatelessWidget {
  const AcmeChart();
  Widget build(BuildContext context) =>
      CustomPaint(painter: ChartPainter());
}

@PaywallSource(id: 'promo')
class Promo extends StatelessWidget {
  const Promo();
  Widget build(BuildContext context) => AcmeChart();
}
''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: false,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/paywalls/promo.dart'),
        source,
      );

      final logs = <String>[];
      await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/paywalls/promo.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: const {},
        onLog: (record) => logs.add(record.message),
      );

      final log = logs.join('\n');
      expect(log, contains('[customWidgetImperative]'));
      expect(log, isNot(contains('[unknownWidget]')));
    });
  });
}
