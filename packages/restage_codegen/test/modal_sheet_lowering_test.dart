import 'package:analyzer/dart/ast/ast.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/rfw_emitter.dart';
import 'package:restage_codegen/src/widget_classification.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const _resultDropMessage =
    "the sheet's result value cannot be observed declaratively";

void main() {
  group('Modal sheet lowering recognition', () {
    test('admits expression-bodied showModalBottomSheet on onPressed',
        () async {
      final result = await _classifyFlutterFixture(
        'AcmeModalButton',
        '''
ElevatedButton(
  onPressed: () => showModalBottomSheet<void>(
    context: context,
    builder: (_) => const SizedBox(),
  ),
  child: const SizedBox(),
)
''',
      );

      _expectRecognisedModalSheet(
        result,
        widgetName: 'AcmeModalButton',
        functionName: 'showModalBottomSheet',
      );
    });

    test('admits block-bodied showModalBottomSheet on onPressed', () async {
      final result = await _classifyFlutterFixture(
        'AcmeBlockModalButton',
        '''
ElevatedButton(
  onPressed: () {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => const SizedBox(),
    );
  },
  child: const SizedBox(),
)
''',
      );

      _expectRecognisedModalSheet(
        result,
        widgetName: 'AcmeBlockModalButton',
        functionName: 'showModalBottomSheet',
      );
    });

    test('admits showCupertinoSheet on onPressed', () async {
      final result = await _classifyFlutterFixture(
        'AcmeCupertinoSheetButton',
        '''
ElevatedButton(
  onPressed: () => cupertino.showCupertinoSheet<void>(
    context: context,
    builder: (_) => const SizedBox(),
  ),
  child: const SizedBox(),
)
''',
      );

      _expectRecognisedModalSheet(
        result,
        widgetName: 'AcmeCupertinoSheetButton',
        functionName: 'showCupertinoSheet',
      );
    });

    test('admits showModalBottomSheet on GestureDetector onTap', () async {
      final result = await _classifyFlutterFixture(
        'AcmeTapSheet',
        '''
GestureDetector(
  onTap: () => showModalBottomSheet<void>(
    context: context,
    builder: (_) => const SizedBox(),
  ),
  child: const SizedBox(),
)
''',
      );

      _expectRecognisedModalSheet(
        result,
        widgetName: 'AcmeTapSheet',
        functionName: 'showModalBottomSheet',
      );
    });

    test('admits showModalBottomSheet on InkWell onTap', () async {
      final result = await _classifyFlutterFixture(
        'AcmeInkSheet',
        '''
InkWell(
  onTap: () => showModalBottomSheet<void>(
    context: context,
    builder: (_) => const SizedBox(),
  ),
  child: const SizedBox(),
)
''',
      );

      _expectRecognisedModalSheet(
        result,
        widgetName: 'AcmeInkSheet',
        functionName: 'showModalBottomSheet',
      );
    });
  });

  group('Modal sheet lowering result-drop guard', () {
    for (final entry in <String, String>{
      'async expression body':
          '() async => showModalBottomSheet<void>(context: context, '
              'builder: (_) => const SizedBox())',
      'await in async block': '''
() async {
  await showModalBottomSheet<void>(
    context: context,
    builder: (_) => const SizedBox(),
  );
}
''',
      'then chain': '() => showModalBottomSheet<void>(context: context, '
          'builder: (_) => const SizedBox()).then((_) {})',
      'assigned result': '''
() {
  final r = showModalBottomSheet<void>(
    context: context,
    builder: (_) => const SizedBox(),
  );
}
''',
      'unawaited wrapper': '''
() {
  unawaited(showModalBottomSheet<void>(
    context: context,
    builder: (_) => const SizedBox(),
  ));
}
''',
    }.entries) {
      test('${entry.key} is a named fatal result-drop', () async {
        final classification = await _classifyFlutterCallback(
          'Acme${entry.key.replaceAll(RegExp("[^A-Za-z0-9]"), "")}',
          entry.value,
        );

        _expectModalSheetFormUnsupported(classification);
      });
    }

    test('multi-statement body that calls a sheet is a named fatal result-drop',
        () async {
      final classification = await _classifyFlutterCallback(
        'AcmeMultiStatement',
        '''
() {
  showModalBottomSheet<void>(
    context: context,
    builder: (_) => const SizedBox(),
  );
  const SizedBox();
}
''',
      );

      _expectModalSheetFormUnsupported(classification);
    });
  });

  group('Modal sheet lowering non-recognition', () {
    test('non-show closure at onPressed keeps the existing unclassifiable path',
        () async {
      final classification = await _classifyFlutterCallback(
        'AcmeDebugButton',
        "() => debugPrint('tap')",
      );

      expect(classification, isA<UnclassifiableWidget>());
      expect(
        (classification as UnclassifiableWidget).diagnosticCode.name,
        isNot('modalSheetFormUnsupported'),
      );
      expect(classification.reason, contains('inline event-handler closure'));
    });

    test('showModalBottomSheet in an unsupported slot uses the named reason',
        () async {
      final result = await _classifyFlutterFixture(
        'AcmeLongPressSheet',
        '''
GestureDetector(
  onLongPress: () => showModalBottomSheet<void>(
    context: context,
    builder: (_) => const SizedBox(),
  ),
  child: const SizedBox(),
)
''',
      );
      const key = 'package:apps_examples/modal_sheet.dart#AcmeLongPressSheet';
      final classification = result.classifications[key];

      expect(classification, isA<UnclassifiableWidget>());
      final unclassifiable = classification! as UnclassifiableWidget;
      expect(
        unclassifiable.diagnosticCode.name,
        'modalSheetFormUnsupported',
      );
    });

    test('non-Flutter showModalBottomSheet look-alike is not recognized',
        () async {
      final result = await classifyFixture(
        {
          'lib/modal_sheet.dart': '''
$kClassifierStubs

class SizedBox extends StatelessWidget {
  const SizedBox();
  Widget build(BuildContext context) => const Widget();
}

class ElevatedButton extends StatelessWidget {
  const ElevatedButton({this.onPressed, this.child});
  final void Function()? onPressed;
  final Widget? child;
  Widget build(BuildContext context) => const Widget();
}

Future<void> showModalBottomSheet({
  required BuildContext context,
  required Widget Function(BuildContext) builder,
}) async {}

@RestageWidget(
  name: 'AcmeLookalike',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.input,
  description: 'lookalike',
)
class AcmeLookalike extends StatelessWidget {
  const AcmeLookalike();
  Widget build(BuildContext context) => ElevatedButton(
    onPressed: () => showModalBottomSheet(
      context: context,
      builder: (_) => const SizedBox(),
    ),
    child: const SizedBox(),
  );
}
''',
        },
        inputPath: 'lib/modal_sheet.dart',
        widgetName: 'AcmeLookalike',
        catalog: _localButtonCatalog,
      );

      expect(result, isA<UnclassifiableWidget>());
      expect(
        (result as UnclassifiableWidget).diagnosticCode.name,
        isNot('modalSheetFormUnsupported'),
      );
    });
  });

  group('IssueCode.modalSheetFormUnsupported', () {
    test('is fatal, not informational', () {
      final code = IssueCode.values.byName('modalSheetFormUnsupported');
      expect(code.isInformational, isFalse);
    });
  });

  group('Modal sheet lowering emit', () {
    test('stateless root mints state, rewrites trigger, and root-hoists',
        () async {
      final result = _translateModalRoot(
        await _parseFlutterRoot('''
ElevatedButton(
  onPressed: () => showModalBottomSheet<void>(
    context: context,
    builder: (_) => const Text('Sheet body'),
  ),
  child: const Text('Open'),
)
'''),
      );

      expect(result.issues, isEmpty);
      expect(result.rootWidgetState, {'_restageSheet0Open': 'false'});
      expect(result.dsl, startsWith('RestageModalSheet('));
      expect(result.dsl, contains('open: state._restageSheet0Open'));
      expect(result.dsl, contains('underlay: ElevatedButton('));
      expect(
        result.dsl,
        contains('onPressed: set state._restageSheet0Open = true'),
      );
      expect(result.dsl, contains('child: Text(text: "Sheet body")'));
      // showModalBottomSheet pins the Material library per source function,
      // matching Flutter (Material on every platform).
      expect(result.dsl, contains('presentation: "material"'));
      expect(
        result.dsl,
        contains('onSheetDismissed: set state._restageSheet0Open = false'),
      );
      fmt.parseLibraryFile(
        emitPaywallLibrary(
          result.dsl,
          rootWidgetState: result.rootWidgetState,
        ),
      );
    });

    test('synthetic flag bumps when author state already uses the name',
        () async {
      final result = _translateModalRoot(
        await _parseFlutterRoot('''
ElevatedButton(
  onPressed: () => showModalBottomSheet<void>(
    context: context,
    builder: (_) => const Text('Sheet body'),
  ),
  child: const Text('Open'),
)
'''),
        rootState: const [
          CustomWidgetStateField(
            name: '_restageSheet0Open',
            isNumeric: false,
            initialValue: false,
          ),
        ],
      );

      expect(result.issues, isEmpty);
      expect(
        result.rootWidgetState,
        {'_restageSheet0Open': 'false', '_restageSheet1Open': 'false'},
      );
      expect(result.dsl, contains('open: state._restageSheet1Open'));
      expect(
        result.dsl,
        contains('onPressed: set state._restageSheet1Open = true'),
      );
    });

    test('mapped styling args and AnimationStyle slots emit in catalog order',
        () async {
      final result = _translateModalRoot(
        await _parseFlutterRoot('''
ElevatedButton(
  onPressed: () => showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    backgroundColor: Colors.white,
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 300),
      curve: Curves.easeIn,
    ),
    builder: (_) => const Text('Sheet body'),
  ),
  child: const Text('Open'),
)
'''),
      );

      expect(result.issues, isEmpty);
      expect(result.dsl, contains('isDismissible: false'));
      expect(result.dsl, contains('backgroundColor: 0xFFFFFFFF'));
      expect(result.dsl, contains('enterDuration: 300'));
      expect(result.dsl, contains('enterCurve: "easeIn"'));
      expect(
        result.dsl.indexOf('open:'),
        lessThan(result.dsl.indexOf('child: Text(text: "Sheet body")')),
      );
      expect(
        result.dsl.indexOf('child: Text(text: "Sheet body")'),
        lessThan(result.dsl.indexOf('isDismissible: false')),
      );
      expect(
        result.dsl.indexOf('underlay:'),
        lessThan(result.dsl.indexOf('onSheetDismissed:')),
      );
    });

    test('defer-only material args fatal-defer loudly', () async {
      final result = _translateModalRoot(
        await _parseFlutterRoot('''
ElevatedButton(
  onPressed: () => showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    builder: (_) => const Text('Sheet body'),
  ),
  child: const Text('Open'),
)
'''),
      );

      expect(result.dsl, isEmpty);
      expect(
        result.issues.map((issue) => issue.code),
        contains(IssueCode.modalSheetFormUnsupported),
      );
      expect(result.issues.single.message, contains('useRootNavigator'));
    });

    test('showCupertinoSheet lowers pageBuilder to child', () async {
      final result = _translateModalRoot(
        await _parseFlutterRoot('''
ElevatedButton(
  onPressed: () => cupertino.showCupertinoSheet<void>(
    context: context,
    pageBuilder: (_) => const Text('Cupertino body'),
    showDragHandle: true,
  ),
  child: const Text('Open'),
)
'''),
      );

      expect(result.issues, isEmpty);
      expect(result.dsl, startsWith('RestageModalSheet('));
      expect(result.dsl, contains('child: Text(text: "Cupertino body")'));
      expect(result.dsl, contains('showDragHandle: true'));
      // showCupertinoSheet pins the Cupertino library per source function,
      // matching Flutter (Cupertino on every platform).
      expect(result.dsl, contains('presentation: "cupertino"'));
    });

    test('a catalog RestageModalSheet without presentation fatal-defers',
        () async {
      // The per-function presentation is load-bearing: a silently-dropped
      // slot degrades to the adaptive default and renders the wrong
      // platform's sheet. If the loaded catalog lacks the slot (a codegen /
      // catalog version skew), the lowering must fail loudly, not emit a
      // RestageModalSheet without presentation.
      final catalogWithoutPresentation = catalogWith(
        [
          entry(
            name: 'ElevatedButton',
            library: WidgetLibrary.material,
            properties: [
              prop('onPressed', PropertyType.event),
              prop('child', PropertyType.widget),
            ],
            fires: const [WidgetEventName.onPressed],
            flutterType:
                'package:flutter/src/material/elevated_button.dart#ElevatedButton',
          ),
          entry(
            name: 'Text',
            properties: [prop('text', PropertyType.string, positional: true)],
            flutterType: 'package:flutter/src/widgets/text.dart#Text',
          ),
          entry(
            name: 'RestageModalSheet',
            library: WidgetLibrary.material,
            properties: [
              prop('open', PropertyType.boolean, required: true),
              prop('child', PropertyType.widget, required: true),
              prop('underlay', PropertyType.widget),
              prop('onSheetDismissed', PropertyType.event),
              // presentation intentionally omitted (a stale pre-fix catalog).
            ],
            fires: const [WidgetEventName.onSheetDismissed],
            flutterType:
                'package:restage_material/src/widgets/restage_modal_sheet.dart#RestageModalSheet',
          ),
        ],
        library: WidgetLibrary.material,
      );

      final result = ExpressionTranslator(
        catalog: catalogWithoutPresentation,
        helpers: HelperRegistry(),
      ).translate(
        await _parseFlutterRoot('''
ElevatedButton(
  onPressed: () => showModalBottomSheet<void>(
    context: context,
    builder: (_) => const Text('Sheet body'),
  ),
  child: const Text('Open'),
)
'''),
      );

      expect(result.dsl, isEmpty);
      expect(
        result.issues.map((issue) => issue.code),
        contains(IssueCode.modalSheetFormUnsupported),
      );
    });

    test('showCupertinoSheet defer-only args fatal-defer loudly', () async {
      final result = _translateModalRoot(
        await _parseFlutterRoot('''
ElevatedButton(
  onPressed: () => cupertino.showCupertinoSheet<void>(
    context: context,
    topGap: 24.0,
    builder: (_) => const Text('Cupertino body'),
  ),
  child: const Text('Open'),
)
'''),
      );

      expect(result.dsl, isEmpty);
      expect(
        result.issues.map((issue) => issue.code),
        contains(IssueCode.modalSheetFormUnsupported),
      );
      expect(result.issues.single.message, contains('topGap'));
    });

    test('in-sheet Navigator.pop(context) closes the synthetic flag', () async {
      final result = _translateModalRoot(
        await _parseFlutterRoot('''
ElevatedButton(
  onPressed: () => showModalBottomSheet<void>(
    context: context,
    builder: (_) => ElevatedButton(
      onPressed: () => Navigator.pop(context),
      child: const Text('Close'),
    ),
  ),
  child: const Text('Open'),
)
'''),
      );

      expect(result.issues, isEmpty);
      expect(
        result.dsl,
        contains('onPressed: set state._restageSheet0Open = false'),
      );
    });

    test('Navigator.pop(context, result) fatal-defers loudly', () async {
      final result = _translateModalRoot(
        await _parseFlutterRoot('''
ElevatedButton(
  onPressed: () => showModalBottomSheet<void>(
    context: context,
    builder: (_) => ElevatedButton(
      onPressed: () => Navigator.pop(context, true),
      child: const Text('Close'),
    ),
  ),
  child: const Text('Open'),
)
'''),
      );

      expect(result.dsl, isEmpty);
      expect(
        result.issues.map((issue) => issue.code),
        contains(IssueCode.modalSheetFormUnsupported),
      );
      expect(result.issues.single.message, contains('Navigator.pop'));
    });
  });

  group('Modal sheet lowering correctness-boundary hardening', () {
    test('a nested result-bearing sheet call is a named fatal result-drop',
        () async {
      final classification = await _classifyFlutterCallback(
        'AcmeNestedSheet',
        '''
() => showModalBottomSheet<void>(
  context: context,
  barrierLabel: showModalBottomSheet<void>(
    context: context,
    builder: (_) => const SizedBox(),
  ).toString(),
  builder: (_) => const SizedBox(),
)
''',
      );

      _expectModalSheetFormUnsupported(classification);
    });

    test('a dynamic-receiver show*Sheet look-alike is not recognized',
        () async {
      final classification = await _classifyFlutterCallback(
        'AcmeDynamicReceiver',
        '''
() => (context as dynamic).showModalBottomSheet(
  context: context,
  builder: (_) => const SizedBox(),
)
''',
      );

      expect(classification, isA<UnclassifiableWidget>());
      expect(
        (classification as UnclassifiableWidget).diagnosticCode.name,
        isNot('modalSheetFormUnsupported'),
      );
    });

    test('a definite blocker wins over a result-drop sheet diagnostic',
        () async {
      final result = await _classifyFlutterFixture(
        'AcmeBlockerWins',
        '''
ElevatedButton(
  onPressed: () {
    final r = showModalBottomSheet<void>(
      context: context,
      builder: (_) => const SizedBox(),
    );
  },
  child: const CustomPaint(),
)
''',
      );
      const key = 'package:apps_examples/modal_sheet.dart#AcmeBlockerWins';

      expect(result.classifications[key], isA<ImperativeWidget>());
    });

    test('a parenthesized single sheet call is recognized', () async {
      final result = await _classifyFlutterFixture(
        'AcmeParenSheet',
        '''
ElevatedButton(
  onPressed: () => (showModalBottomSheet<void>(
    context: context,
    builder: (_) => const SizedBox(),
  )),
  child: const SizedBox(),
)
''',
      );

      _expectRecognisedModalSheet(
        result,
        widgetName: 'AcmeParenSheet',
        functionName: 'showModalBottomSheet',
      );
    });
  });
}

Future<WidgetClassification> _classifyFlutterCallback(
  String widgetName,
  String callback,
) async {
  final result = await _classifyFlutterFixture(
    widgetName,
    '''
ElevatedButton(
  onPressed: $callback,
  child: const SizedBox(),
)
''',
  );
  final key = 'package:apps_examples/modal_sheet.dart#$widgetName';
  final classification = result.classifications[key];
  if (classification == null) {
    throw StateError('missing classification for $key');
  }
  return classification;
}

Future<ClassificationResult> _classifyFlutterFixture(
  String widgetName,
  String buildExpression,
) {
  return classifyFixtureResult(
    {
      'lib/modal_sheet.dart': '''
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' as cupertino;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageWidget(
  name: '$widgetName',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.input,
  description: 'modal sheet',
)
class $widgetName extends StatelessWidget {
  const $widgetName({super.key});
  @override
  Widget build(BuildContext context) => $buildExpression;
}
''',
    },
    inputPath: 'lib/modal_sheet.dart',
    widgetName: widgetName,
    catalog: _flutterModalCatalog,
  );
}

Future<Expression> _parseFlutterRoot(String expression) {
  return parseExpressionFromSourceForTest(
    '''
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' as cupertino;

Object x(BuildContext context) => $expression;
''',
    rootPackage: 'apps_examples',
  );
}

TranslationResult _translateModalRoot(
  Expression expression, {
  List<CustomWidgetStateField>? rootState,
}) {
  return ExpressionTranslator(
    catalog: _translatorModalCatalog,
    helpers: HelperRegistry(),
  ).translate(expression, rootState: rootState);
}

void _expectRecognisedModalSheet(
  ClassificationResult result, {
  required String widgetName,
  required String functionName,
}) {
  final key = 'package:apps_examples/modal_sheet.dart#$widgetName';
  final classification = result.classifications[key];
  expect(classification, isA<ComposableWidget>());
  final composable = classification! as ComposableWidget;
  expect(
    composable.requiredMechanisms.map((m) => m.name),
    contains('modalSheet'),
  );

  final blueprint = result.blueprints[key]!;
  final modalSheets = blueprint.modalSheets;
  expect(modalSheets, hasLength(1));
  final trigger = modalSheets.single;
  expect(trigger.function.name, functionName);
  expect(trigger.call.methodName.name, functionName);
}

void _expectModalSheetFormUnsupported(WidgetClassification classification) {
  expect(classification, isA<UnclassifiableWidget>());
  final unclassifiable = classification as UnclassifiableWidget;
  expect(unclassifiable.diagnosticCode.name, 'modalSheetFormUnsupported');
  expect(unclassifiable.reason, contains(_resultDropMessage));
}

final Catalog _flutterModalCatalog = Catalog(
  schemaVersion: kSupportedSchemaVersion,
  generatedAt: '1970-01-01T00:00:00Z',
  libraries: <WidgetLibrary, LibraryInfo>{
    WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
    WidgetLibrary.material: const LibraryInfo(version: '0.1.0'),
    WidgetLibrary.cupertino: const LibraryInfo(version: '0.1.0'),
  },
  widgets: [
    entry(
      name: 'ElevatedButton',
      library: WidgetLibrary.material,
      properties: const [],
      flutterType:
          'package:flutter/src/material/elevated_button.dart#ElevatedButton',
    ),
    entry(
      name: 'GestureDetector',
      properties: const [],
      flutterType:
          'package:flutter/src/widgets/gesture_detector.dart#GestureDetector',
    ),
    entry(
      name: 'InkWell',
      library: WidgetLibrary.material,
      properties: const [],
      flutterType: 'package:flutter/src/material/ink_well.dart#InkWell',
    ),
    entry(
      name: 'SizedBox',
      properties: const [],
      flutterType: 'package:flutter/src/widgets/basic.dart#SizedBox',
    ),
  ],
);

final Catalog _localButtonCatalog = catalogWith([
  entry(
    name: 'ElevatedButton',
    properties: const [],
    flutterType: 'package:apps_examples/modal_sheet.dart#ElevatedButton',
  ),
  entry(
    name: 'SizedBox',
    properties: const [],
    flutterType: 'package:apps_examples/modal_sheet.dart#SizedBox',
  ),
]);

final Catalog _translatorModalCatalog = catalogWith(
  [
    entry(
      name: 'ElevatedButton',
      library: WidgetLibrary.material,
      properties: [
        prop('onPressed', PropertyType.event),
        prop('child', PropertyType.widget),
      ],
      fires: const [WidgetEventName.onPressed],
      flutterType:
          'package:flutter/src/material/elevated_button.dart#ElevatedButton',
    ),
    entry(
      name: 'Text',
      properties: [
        prop('text', PropertyType.string, positional: true),
      ],
      flutterType: 'package:flutter/src/widgets/text.dart#Text',
    ),
    entry(
      name: 'RestageModalSheet',
      library: WidgetLibrary.material,
      properties: [
        prop('open', PropertyType.boolean, required: true),
        prop('child', PropertyType.widget, required: true),
        prop('isDismissible', PropertyType.boolean),
        prop('enableDrag', PropertyType.boolean),
        prop('showDragHandle', PropertyType.boolean),
        prop('dragHandleColor', PropertyType.color),
        prop('isScrollControlled', PropertyType.boolean),
        prop('scrollControlDisabledMaxHeightRatio', PropertyType.real),
        prop('backgroundColor', PropertyType.color),
        prop('elevation', PropertyType.real),
        prop('shape', PropertyType.shapeBorder),
        prop('clipBehavior', PropertyType.enumValue),
        prop('useSafeArea', PropertyType.boolean),
        prop('barrierColor', PropertyType.color),
        prop('barrierLabel', PropertyType.string),
        prop('anchorPoint', PropertyType.offset),
        prop('enterDuration', PropertyType.duration),
        prop('exitDuration', PropertyType.duration),
        prop('enterCurve', PropertyType.curve),
        prop('exitCurve', PropertyType.curve),
        prop('presentation', PropertyType.enumValue),
        prop('underlay', PropertyType.widget),
        prop('onSheetDismissed', PropertyType.event),
      ],
      fires: const [WidgetEventName.onSheetDismissed],
      flutterType:
          'package:restage_material/src/widgets/restage_modal_sheet.dart#RestageModalSheet',
    ),
  ],
  library: WidgetLibrary.material,
);
