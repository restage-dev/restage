import 'package:restage_codegen/src/factory_emitter.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

void main() {
  group('runtime realization routing', () {
    for (final realization in <({String name, String runtimeName})>[
      (name: 'Align', runtimeName: 'RestageAlign'),
      (name: 'AnimatedAlign', runtimeName: 'RestageAnimatedAlign'),
      (name: 'AnimatedPadding', runtimeName: 'RestageAnimatedPadding'),
      (name: 'AnimatedSize', runtimeName: 'RestageAnimatedSize'),
      (name: 'Center', runtimeName: 'RestageCenter'),
      (name: 'ListView', runtimeName: 'RestageListView'),
      (name: 'Padding', runtimeName: 'RestagePadding'),
      (name: 'Row', runtimeName: 'RestageRow'),
      (name: 'Stack', runtimeName: 'RestageStack'),
      (name: 'Column', runtimeName: 'RestageColumn'),
      (name: 'Wrap', runtimeName: 'RestageWrap'),
      (name: 'Image', runtimeName: 'RestageImage.network'),
      (name: 'ImageAsset', runtimeName: 'RestageImage.asset'),
      (
        name: 'FadeInImageAssetNetwork',
        runtimeName: 'RestageFadeInImage.assetNetwork',
      ),
    ]) {
      test('constructs ${realization.name} with its runtime realization', () {
        final source = emitFactoryFunction(_entryFor(realization.name))!;

        expect(source, contains('return ${realization.runtimeName}('));
        expect(source, isNot(contains('return ${realization.name}(')));
      });
    }

    test('constructs FractionallySizedBox with its runtime realization', () {
      final source = emitFactoryFunction(
        _entryFor('FractionallySizedBox'),
      )!;

      expect(source, contains('return RestageFractionallySizedBox('));
      expect(source, isNot(contains('return FractionallySizedBox(')));
    });

    test('constructs IntrinsicWidth with its runtime realization', () {
      final source = emitFactoryFunction(
        _entryFor('IntrinsicWidth'),
      )!;

      expect(source, contains('return RestageIntrinsicWidth('));
      expect(source, isNot(contains('return IntrinsicWidth(')));
    });

    test('constructs AspectRatio with its runtime realization', () {
      final source = emitFactoryFunction(_entryFor('AspectRatio'))!;

      expect(source, contains('return RestageAspectRatio('));
      expect(source, isNot(contains('return AspectRatio(')));
    });

    test('constructs FittedBox with its runtime realization', () {
      final source = emitFactoryFunction(_entryFor('FittedBox'))!;

      expect(source, contains('return RestageFittedBox('));
      expect(source, isNot(contains('return FittedBox(')));
    });

    test('constructs a non-overridden widget with its framework class', () {
      final source = emitFactoryFunction(_entryFor('SizedBox'))!;

      expect(source, contains('return SizedBox('));
    });

    for (final realization in <({
      String name,
      String runtimeName,
      String sourceUri,
    })>[
      (
        name: 'Align',
        runtimeName: 'RestageAlign',
        sourceUri: 'package:flutter/src/widgets/basic.dart',
      ),
      (
        name: 'AnimatedAlign',
        runtimeName: 'RestageAnimatedAlign',
        sourceUri: 'package:flutter/src/widgets/implicit_animations.dart',
      ),
      (
        name: 'AnimatedPadding',
        runtimeName: 'RestageAnimatedPadding',
        sourceUri: 'package:flutter/src/widgets/implicit_animations.dart',
      ),
      (
        name: 'AnimatedSize',
        runtimeName: 'RestageAnimatedSize',
        sourceUri: 'package:flutter/src/widgets/animated_size.dart',
      ),
      (
        name: 'Center',
        runtimeName: 'RestageCenter',
        sourceUri: 'package:flutter/src/widgets/basic.dart',
      ),
      (
        name: 'FractionallySizedBox',
        runtimeName: 'RestageFractionallySizedBox',
        sourceUri: 'package:flutter/src/widgets/basic.dart',
      ),
      (
        name: 'ListView',
        runtimeName: 'RestageListView',
        sourceUri: 'package:flutter/src/widgets/scroll_view.dart',
      ),
      (
        name: 'Padding',
        runtimeName: 'RestagePadding',
        sourceUri: 'package:flutter/src/widgets/basic.dart',
      ),
      (
        name: 'IntrinsicWidth',
        runtimeName: 'RestageIntrinsicWidth',
        sourceUri: 'package:flutter/src/widgets/basic.dart',
      ),
      (
        name: 'AspectRatio',
        runtimeName: 'RestageAspectRatio',
        sourceUri: 'package:flutter/src/widgets/basic.dart',
      ),
      (
        name: 'FittedBox',
        runtimeName: 'RestageFittedBox',
        sourceUri: 'package:flutter/src/widgets/basic.dart',
      ),
      (
        name: 'FadeInImageAssetNetwork',
        runtimeName: 'RestageFadeInImage.assetNetwork',
        sourceUri: 'package:flutter/src/widgets/fade_in_image.dart',
      ),
      (
        name: 'Image',
        runtimeName: 'RestageImage.network',
        sourceUri: 'package:flutter/src/widgets/image.dart',
      ),
      (
        name: 'ImageAsset',
        runtimeName: 'RestageImage.asset',
        sourceUri: 'package:flutter/src/widgets/image.dart',
      ),
      (
        name: 'Row',
        runtimeName: 'RestageRow',
        sourceUri: 'package:flutter/src/widgets/basic.dart',
      ),
      (
        name: 'Stack',
        runtimeName: 'RestageStack',
        sourceUri: 'package:flutter/src/widgets/basic.dart',
      ),
      (
        name: 'Column',
        runtimeName: 'RestageColumn',
        sourceUri: 'package:flutter/src/widgets/basic.dart',
      ),
      (
        name: 'Wrap',
        runtimeName: 'RestageWrap',
        sourceUri: 'package:flutter/src/widgets/basic.dart',
      ),
    ]) {
      test('keeps a same-named custom ${realization.name} qualified', () {
        const customUri = 'package:acme/widgets.dart';
        final source = emitFactoryFunction(
          _entryFor(
            realization.name,
            library: const WidgetLibrary.custom('acme.widgets'),
            flutterType: '$customUri#${realization.name}',
          ),
          aliases: const {customUri: 's0'},
        )!;

        expect(source, contains('return s0.${realization.name}('));
        expect(source, isNot(contains('return ${realization.runtimeName}(')));
      });

      test('keeps custom ${realization.name} with the framework source type',
          () {
        final source = emitFactoryFunction(
          _entryFor(
            realization.name,
            library: const WidgetLibrary.custom('acme.widgets'),
            flutterType: '${realization.sourceUri}#${realization.name}',
          ),
          aliases: {realization.sourceUri: 's0'},
        )!;

        expect(source, contains('return s0.${realization.name}('));
        expect(source, isNot(contains('return ${realization.runtimeName}(')));
      });

      test('keeps built-in ${realization.name} with a different source type',
          () {
        const otherUri = 'package:flutter/src/widgets/framework.dart';
        final source = emitFactoryFunction(
          _entryFor(
            realization.name,
            flutterType: '$otherUri#${realization.name}',
          ),
          aliases: const {otherUri: 's0'},
        )!;

        expect(source, contains('return s0.${realization.name}('));
        expect(source, isNot(contains('return ${realization.runtimeName}(')));
      });
    }
  });
}

WidgetEntry _entryFor(
  String widgetName, {
  WidgetLibrary library = WidgetLibrary.core,
  String? flutterType,
}) {
  return WidgetEntry(
    wireId: WireId.unallocatedWidget,
    name: widgetName,
    library: library,
    category: WidgetCategory.decoration,
    description: 'Runtime realization routing fixture.',
    flutterType: flutterType ??
        switch (widgetName) {
          'AnimatedAlign' =>
            'package:flutter/src/widgets/implicit_animations.dart#AnimatedAlign',
          'AnimatedPadding' =>
            'package:flutter/src/widgets/implicit_animations.dart#AnimatedPadding',
          'AnimatedSize' =>
            'package:flutter/src/widgets/animated_size.dart#AnimatedSize',
          'Image' => 'package:flutter/src/widgets/image.dart#Image.network',
          'ImageAsset' => 'package:flutter/src/widgets/image.dart#Image.asset',
          'FadeInImageAssetNetwork' =>
            'package:flutter/src/widgets/fade_in_image.dart#FadeInImage.assetNetwork',
          'ListView' => 'package:flutter/src/widgets/scroll_view.dart#ListView',
          _ => 'package:flutter/src/widgets/basic.dart#$widgetName',
        },
    childrenSlot: ChildrenSlot.none,
    properties: const [],
  );
}
