import 'package:analyzer/dart/ast/ast.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

import 'helpers.dart';

Future<Expression> parseModalSheetRoot(String expression) {
  return parseExpressionFromSourceForTest(
    '''
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' as cupertino;

Object x(
  BuildContext context, {
  bool condition = false,
  AnimationController? controller,
  BoxConstraints? constraints,
  RouteSettings? routeSettings,
}) => $expression;

Widget sheetBuilder(BuildContext context) => const Text('Sheet body');
''',
    rootPackage: 'apps_examples',
  );
}

TranslationResult translateModalSheetRoot(
  Expression expression, {
  List<CustomWidgetStateField>? rootState,
}) {
  return ExpressionTranslator(
    catalog: modalSheetTranslatorCatalog,
    helpers: HelperRegistry(),
  ).translate(expression, rootState: rootState);
}

Future<TranslationResult> translateModalSheetSource(String expression) async {
  return translateModalSheetRoot(await parseModalSheetRoot(expression));
}

final Catalog modalSheetTranslatorCatalog = catalogWith(
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
      name: 'GestureDetector',
      properties: [
        prop('onTap', PropertyType.event),
        prop('onLongPress', PropertyType.event),
        prop('child', PropertyType.widget),
      ],
      fires: const [
        WidgetEventName.onTap,
        WidgetEventName.onLongPress,
      ],
      flutterType:
          'package:flutter/src/widgets/gesture_detector.dart#GestureDetector',
    ),
    entry(
      name: 'Text',
      properties: [
        prop('text', PropertyType.string, positional: true),
      ],
      flutterType: 'package:flutter/src/widgets/text.dart#Text',
    ),
    entry(
      name: 'Column',
      childrenSlot: ChildrenSlot.list,
      properties: [
        prop('children', PropertyType.widgetList),
      ],
      flutterType: 'package:flutter/src/widgets/basic.dart#Column',
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
