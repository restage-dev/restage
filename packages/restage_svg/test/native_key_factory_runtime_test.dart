import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/rfw.dart';
import 'package:rfw/formats.dart' as rfw;

import 'fixtures/native_key_factories.g.dart' as f;
import 'fixtures/native_key_widget.dart';

const contract = NativeBindingContract(type: 'flutter.Key');

class EqualModel {
  @override
  bool operator ==(Object other) => other is EqualModel;
  @override
  int get hashCode => 1;
}

Map<String, dynamic> fixture(String name) =>
    jsonDecode(
          File(
            '../restage_codegen/test/fixtures/$name.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

Runtime runtimeFor(String dsl) => Runtime()
  ..update(
    const LibraryName(['key', 'factories']),
    LocalWidgetLibrary({
      'Text': f.buildText,
      'Icon': f.buildIcon,
      'Row': f.buildRow,
      'AnimatedAlign': f.buildAnimatedAlign,
      'LayoutBuilder': f.buildLayoutBuilder,
      'SvgPictureString': f.buildSvgPictureString,
      'NativeKeyWidget': f.buildNativeKeyWidget,
      'DefaultNativeKeyWidget': f.buildDefaultNativeKeyWidget,
      kBuilderContinuationWidgetName: buildRestageBuilderContinuation,
    }),
  )
  ..update(
    const LibraryName(['test']),
    rfw.parseLibraryFile('import key.factories; widget Root=$dsl;'),
  );

Widget host(
  Runtime runtime,
  DynamicContent data,
  Map<String, NativeBinding<Object?>> bindings,
) => Directionality(
  textDirection: TextDirection.ltr,
  child: RestageNativeValues(
    bindings: bindings,
    child: RemoteWidget(
      runtime: runtime,
      data: data,
      widget: const FullyQualifiedWidgetName(LibraryName(['test']), 'Root'),
    ),
  ),
);

void main() {
  testWidgets('production Icon factory preserves the native Icon owner', (
    tester,
  ) async {
    InstalledIconTable.install(
      RestageIconTable.fromFamilies(
        families: {
          RestageIconTable.materialIconsFamily: {
            Icons.check.codePoint: Icons.check,
          },
        },
      ),
    );
    addTearDown(InstalledIconTable.reset);
    final key = GlobalKey();
    final runtime = runtimeFor(
      'Icon(iconCodepoint:${Icons.check.codePoint},key:data.context.item)',
    );
    await tester.pumpWidget(
      host(
        runtime,
        DynamicContent({
          'context': {'item': contract.reference('item')},
        }),
        {'item': NativeBinding<Key>(contract: contract, value: key)},
      ),
    );
    final actual = tester.widget<Icon>(find.byKey(key));
    expect(actual.icon, Icons.check);
    expect(actual.key, same(key));
    expect(key.currentWidget, same(actual));
    expect(key.currentContext, same(tester.element(find.byKey(key))));
    expect(tester.takeException(), isNull);
  });

  for (final nullable in [false, true]) {
    testWidgets(
      'generated native key frame attaches original Text nullable=$nullable',
      (tester) async {
        final spec = fixture('native_key_lazy_$nullable');
        final binding = NativeBindingContract(
          type: 'flutter.Key',
          nullable: nullable,
        );
        final key = GlobalKey();
        final runtime = runtimeFor(spec['dsl'] as String);
        final slot = spec['slot'] as String;
        final data = DynamicContent({
          'context': {slot: binding.reference(slot)},
        });
        await tester.pumpWidget(
          host(runtime, data, {
            slot: NativeBinding<Key?>(contract: binding, value: key),
          }),
        );
        final actual = tester.widget<Text>(find.byKey(key));
        expect(actual.key, same(key));
        expect(key.currentWidget, same(actual));
        expect(key.currentContext, same(tester.element(find.byKey(key))));
        expect(tester.takeException(), isNull);
        if (nullable) {
          await tester.pumpWidget(
            host(runtime, data, {
              slot: NativeBinding<Key?>(contract: binding, value: null),
            }),
          );
          expect(key.currentWidget, isNull);
          expect(find.text('item'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
  testWidgets('generated SVG constructor owns its exact native GlobalKey', (
    tester,
  ) async {
    final key = GlobalKey();
    final runtime = runtimeFor(
      'SvgPictureString(string:"<svg xmlns=\\"http://www.w3.org/2000/svg\\" width=\\"1\\" height=\\"1\\"></svg>",key:data.context.item)',
    );
    final data = DynamicContent({
      'context': {'item': contract.reference('item')},
    });
    await tester.pumpWidget(
      host(runtime, data, {
        'item': NativeBinding<Key>(contract: contract, value: key),
      }),
    );
    await tester.pump();
    final actual = tester.widget<SvgPicture>(find.byKey(key));
    expect(actual.key, same(key));
    expect(key.currentWidget, same(actual));
    expect(key.currentContext, same(tester.element(find.byKey(key))));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'native constructor key default distinguishes omission and explicit null',
    (tester) async {
      final spec = fixture('native_key_defaults');
      final key = GlobalKey();
      final slot = spec['slot'] as String;
      for (final entry in (spec['sources'] as Map).entries) {
        final runtime = runtimeFor(entry.value as String);
        await tester.pumpWidget(
          host(
            runtime,
            DynamicContent({
              'context': {slot: contract.reference(slot)},
            }),
            {slot: NativeBinding<Key>(contract: contract, value: key)},
          ),
        );
        final actual = tester.widget<DefaultNativeKeyWidget>(
          find.byType(DefaultNativeKeyWidget),
        );
        switch (entry.key) {
          case 'omitted':
            expect(actual.key, same(const ObjectKey('default')));
          case 'explicitNull':
          case 'parenthesizedNull':
          case 'constantNull':
          case 'constantNullAlias':
            expect(actual.key, isNull);
          case 'borrowed':
            expect(actual.key, same(key));
            expect(key.currentWidget, same(actual));
        }
        expect(tester.takeException(), isNull);
      }
    },
  );
  for (final (name, body, guardedType) in [
    ('Row', 'Row(children:[],', RestageRow),
    (
      'AnimatedAlign',
      'AnimatedAlign(duration:0,alignment:{x:0.0,y:0.0},',
      RestageAnimatedAlign,
    ),
  ]) {
    testWidgets(
      'guarded $name refuses a raw native key and retains null behavior',
      (tester) async {
        final key = GlobalKey();
        final runtime = runtimeFor('${body}key:data.context.item)');
        await tester.pumpWidget(
          host(
            runtime,
            DynamicContent({
              'context': {'item': contract.reference('item')},
            }),
            {'item': NativeBinding<Key>(contract: contract, value: key)},
          ),
        );
        final error = tester.takeException();
        expect(error, isA<UnsupportedError>());
        expect(error.toString(), contains('original $name owner'));
        expect(key.currentWidget, isNull);
        expect(find.byType(guardedType), findsNothing);
        await tester.pumpWidget(
          host(runtimeFor('${body}key:data.absent)'), DynamicContent({}), {}),
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(guardedType), findsOneWidget);
      },
    );
  }

  for (final global in [false, true]) {
    testWidgets(
      'source to generated custom factory preserves reorder and owner global=$global',
      (tester) async {
        final spec = fixture('native_key_custom_reorder');
        final first = global
            ? GlobalKey<NativeKeyWidgetState>()
            : ObjectKey(EqualModel());
        final second = global
            ? GlobalKey<NativeKeyWidgetState>()
            : ObjectKey(EqualModel());
        expect(first == second, isFalse);
        final slots = (spec['bindings'] as Map).cast<String, String>();
        final runtime = runtimeFor(spec['dsl'] as String);
        final context = <String, Object?>{
          'reverse': false,
          for (final slot in slots.keys) slot: contract.reference(slot),
        };
        final data = DynamicContent({'context': context});
        final bindings = <String, NativeBinding<Object?>>{
          for (final entry in slots.entries)
            entry.key: NativeBinding<Key>(
              contract: contract,
              value: entry.value == 'itemKey' ? first : second,
            ),
        };
        await tester.pumpWidget(host(runtime, data, bindings));
        final state1 = tester.state(find.byKey(first));
        final state2 = tester.state(find.byKey(second));
        expect(state1, isA<NativeKeyWidgetState>());
        expect(state2, isNot(same(state1)));
        data.update('context', {...context, 'reverse': true});
        await tester.pump();
        expect(tester.state(find.byKey(first)), same(state1));
        expect(tester.state(find.byKey(second)), same(state2));
        expect(
          tester.getTopLeft(find.byKey(second)).dx,
          lessThan(tester.getTopLeft(find.byKey(first)).dx),
        );
        if (first is GlobalKey<NativeKeyWidgetState>) {
          expect(
            first.currentWidget,
            same(tester.widget<NativeKeyWidget>(find.byKey(first))),
          );
          expect(first.currentState, same(state1));
          expect(first.currentContext, same(tester.element(find.byKey(first))));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
